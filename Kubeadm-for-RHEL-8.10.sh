#!/usr/bin/env bash
# ==============================================================================
# RHEL 8.x Kubernetes prerequisites + kubeadm bootstrap helper
#
# Key behavior for RHEL 8.10:
# - Uses containerd as the CRI runtime
# - Enables cgroups v2 for Kubernetes 1.35+
# - Exits cleanly and asks for a reboot if the host is still on cgroups v1
# - Opens common kubeadm + Cilium firewall ports when firewalld is active
#
# Usage:
#   sudo bash setup-k8s-rhel8-v3.sh master
#   sudo bash setup-k8s-rhel8-v3.sh worker
#
# Optional environment variables:
#   K8S_MINOR=v1.35
#   CILIUM_VERSION=1.19.3
#   CONTROL_PLANE_HOSTNAME=master
#   WORKER_HOSTNAME=worker
#   API_ADVERTISE_ADDRESS=<ip>
# ==============================================================================

set -Eeuo pipefail

trap 'rc=$?; echo -e "\033[1;31m[ERROR]\033[0m Line ${LINENO}: command failed: ${BASH_COMMAND}" >&2; exit "$rc"' ERR

K8S_MINOR="${K8S_MINOR:-v1.35}"
CILIUM_VERSION="${CILIUM_VERSION:-1.19.3}"
CONTROL_PLANE_HOSTNAME="${CONTROL_PLANE_HOSTNAME:-master}"
WORKER_HOSTNAME="${WORKER_HOSTNAME:-worker}"
NODE_ROLE="${1:-}"
API_ADVERTISE_ADDRESS="${API_ADVERTISE_ADDRESS:-}"
CONTAINERD_SOCK="unix:///run/containerd/containerd.sock"
REBOOT_MARKER="/var/lib/k8s-rhel-needs-reboot"

log() {
  echo -e "\033[1;34m$(date '+%Y-%m-%d %H:%M:%S') : [INFO] $*\033[0m"
}

warn() {
  echo -e "\033[1;33m$(date '+%Y-%m-%d %H:%M:%S') : [WARN] $*\033[0m"
}

error_exit() {
  echo -e "\033[1;31m[ERROR] $*\033[0m" >&2
  exit 1
}

require_root() {
  if [[ ${EUID} -ne 0 ]]; then
    error_exit "Please run this script as root, for example: sudo bash setup-k8s-rhel8-v3.sh master"
  fi
}

verify_os() {
  [[ -r /etc/os-release ]] || error_exit "/etc/os-release not found. Cannot verify OS."
  # shellcheck disable=SC1091
  source /etc/os-release

  local major="${VERSION_ID%%.*}"
  local ok=0

  if [[ "${major}" == "8" ]]; then
    case "${ID:-}" in
      rhel|rocky|almalinux|centos)
        ok=1
        ;;
    esac

    if [[ ${ok} -eq 0 && " ${ID_LIKE:-} " == *" rhel "* ]]; then
      ok=1
    fi
  fi

  [[ ${ok} -eq 1 ]] || error_exit "This script is intended for RHEL 8.x compatible systems. Detected: ID=${ID:-unknown}, VERSION_ID=${VERSION_ID:-unknown}."
  log "Detected supported OS: ${PRETTY_NAME:-$ID}"
}

detect_arch() {
  case "$(uname -m)" in
    x86_64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) error_exit "Unsupported architecture: $(uname -m). Supported: x86_64, aarch64/arm64." ;;
  esac
}

choose_role() {
  if [[ -z "${NODE_ROLE}" ]]; then
    read -r -p "Enter node role [master/worker]: " NODE_ROLE
  fi

  case "${NODE_ROLE,,}" in
    master|control-plane|controlplane)
      NODE_ROLE="master"
      ;;
    worker)
      NODE_ROLE="worker"
      ;;
    *)
      error_exit "Invalid node role: ${NODE_ROLE}. Use 'master' or 'worker'."
      ;;
  esac

  log "Selected node role: ${NODE_ROLE}"
}

update_system() {
  log "Refreshing package metadata and upgrading installed packages..."
  dnf -y makecache
  dnf -y upgrade
}

install_prereqs() {
  log "Installing prerequisite packages..."
  dnf -y install \
    ca-certificates \
    curl \
    tar \
    dnf-plugins-core \
    device-mapper-persistent-data \
    lvm2 \
    conntrack-tools \
    socat \
    ebtables \
    ethtool \
    iproute \
    iptables \
    bash-completion \
    grubby
}

configure_selinux() {
  if command -v getenforce >/dev/null 2>&1; then
    local mode
    mode="$(getenforce || true)"
    if [[ "${mode}" != "Disabled" ]]; then
      log "Setting SELinux to permissive mode..."
      setenforce 0 || true
      if [[ -f /etc/selinux/config ]]; then
        sed -ri 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config
      fi
    else
      log "SELinux is disabled; no change needed."
    fi
  fi
}

configure_modules_and_sysctl() {
  log "Loading required kernel modules..."
  cat > /etc/modules-load.d/k8s.conf <<'MODS'
overlay
br_netfilter
MODS

  modprobe overlay
  modprobe br_netfilter

  log "Applying Kubernetes sysctl settings..."
  cat > /etc/sysctl.d/99-kubernetes-cri.conf <<'SYSCTL'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
SYSCTL

  sysctl --system >/dev/null
}

configure_swap() {
  log "Disabling swap..."
  swapoff -a || true

  if [[ -f /etc/fstab ]]; then
    cp -a /etc/fstab "/etc/fstab.bak.$(date +%Y%m%d%H%M%S)"
    sed -ri '/\sswap\s/s/^([^#].*)$/# \1/' /etc/fstab
  fi
}

current_cgroup_mode() {
  if [[ "$(stat -fc %T /sys/fs/cgroup 2>/dev/null || true)" == "cgroup2fs" ]]; then
    echo "v2"
  else
    echo "v1"
  fi
}

enable_cgroup_v2_boot() {
  local changed=0

  [[ -x /usr/sbin/grubby || -x /sbin/grubby || -x /usr/bin/grubby ]] || error_exit "grubby is required but not available."

  log "Configuring kernel boot parameters for cgroups v2..."
  grubby --update-kernel=ALL --remove-args="systemd.unified_cgroup_hierarchy=0 systemd.legacy_systemd_cgroup_controller" || true

  if ! grubby --info=ALL | grep -q 'systemd.unified_cgroup_hierarchy=1'; then
    grubby --update-kernel=ALL --args="systemd.unified_cgroup_hierarchy=1"
    changed=1
  fi

  if [[ "$(current_cgroup_mode)" != "v2" ]]; then
    mkdir -p "$(dirname "${REBOOT_MARKER}")"
    echo "reboot-required-for-cgroup-v2" > "${REBOOT_MARKER}"

    if [[ ${changed} -eq 1 ]]; then
      warn "This host is currently booted with cgroups v1."
      warn "cgroups v2 has been enabled for the next boot. Please reboot this server, then rerun the script."
    else
      warn "cgroups v2 is already configured for boot, but this server has not been rebooted yet."
      warn "Please reboot this server, then rerun the script."
    fi

    exit 20
  fi

  log "Detected active cgroups v2."
  rm -f "${REBOOT_MARKER}" || true
}

install_containerd() {
  log "Removing conflicting container packages if present..."
  dnf -y remove \
    docker \
    docker-client \
    docker-client-latest \
    docker-common \
    docker-latest \
    docker-latest-logrotate \
    docker-logrotate \
    docker-engine \
    podman \
    runc || true

  log "Adding Docker repository for containerd.io..."
  dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo

  log "Installing containerd.io..."
  dnf -y install containerd.io

  log "Generating default containerd configuration..."
  mkdir -p /etc/containerd
  containerd config default > /etc/containerd/config.toml

  log "Configuring containerd to use SystemdCgroup=true..."
  sed -ri 's/^([[:space:]]*)SystemdCgroup = false/\1SystemdCgroup = true/' /etc/containerd/config.toml

  log "Enabling and restarting containerd..."
  systemctl daemon-reload
  systemctl enable --now containerd
  systemctl restart containerd

  systemctl is-active --quiet containerd || error_exit "containerd is not active after restart."
}

install_kubernetes_packages() {
  log "Configuring Kubernetes RPM repository (${K8S_MINOR})..."
  cat > /etc/yum.repos.d/kubernetes.repo <<EOF_REPO
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF_REPO

  log "Installing kubelet, kubeadm and kubectl..."
  dnf -y install kubelet kubeadm kubectl --disableexcludes=kubernetes

  log "Enabling kubelet service..."
  systemctl enable --now kubelet
}

verify_installation() {
  log "Verifying installed versions..."
  kubeadm version -o short
  kubelet --version
  kubectl version --client
}

detect_private_ip() {
  local detected=""

  detected="$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"
  if [[ -z "${detected}" ]]; then
    detected="$(ip route get 8.8.8.8 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"
  fi
  if [[ -z "${detected}" ]]; then
    detected="$(hostname -I 2>/dev/null | awk '{print $1}')"
  fi

  [[ -n "${detected}" ]] || error_exit "Could not determine private IP automatically. Set API_ADVERTISE_ADDRESS manually and rerun."
  echo "${detected}"
}

ensure_hostname_mapping() {
  local ip="$1"
  local short_host fqdn_host

  short_host="$(hostname -s)"
  fqdn_host="$(hostname -f 2>/dev/null || true)"

  if ! grep -Eq "^[^#]*[[:space:]]${short_host}([[:space:]]|$)" /etc/hosts; then
    if [[ -n "${fqdn_host}" && "${fqdn_host}" != "${short_host}" ]]; then
      echo "${ip} ${fqdn_host} ${short_host}" >> /etc/hosts
    else
      echo "${ip} ${short_host}" >> /etc/hosts
    fi
  fi
}

configure_firewalld() {
  if systemctl is-active --quiet firewalld; then
    log "firewalld is active. Opening required Kubernetes and Cilium ports..."

    if [[ "${NODE_ROLE}" == "master" ]]; then
      firewall-cmd --permanent --add-port=6443/tcp
      firewall-cmd --permanent --add-port=2379-2380/tcp
      firewall-cmd --permanent --add-port=10250/tcp
      firewall-cmd --permanent --add-port=10257/tcp
      firewall-cmd --permanent --add-port=10259/tcp
    else
      firewall-cmd --permanent --add-port=10250/tcp
      firewall-cmd --permanent --add-port=30000-32767/tcp
    fi

    firewall-cmd --permanent --add-port=8472/udp
    firewall-cmd --permanent --add-port=4240/tcp
    firewall-cmd --reload
  else
    log "firewalld is not active; skipping firewall changes."
  fi
}

configure_kubectl_access() {
  local target_user target_home
  target_user="${SUDO_USER:-root}"
  target_home="$(eval echo "~${target_user}")"

  export KUBECONFIG=/etc/kubernetes/admin.conf

  mkdir -p /root/.kube
  cp -f /etc/kubernetes/admin.conf /root/.kube/config
  chown root:root /root/.kube/config

  if [[ "${target_user}" != "root" && -d "${target_home}" ]]; then
    mkdir -p "${target_home}/.kube"
    cp -f /etc/kubernetes/admin.conf "${target_home}/.kube/config"
    chown -R "${target_user}:${target_user}" "${target_home}/.kube"
  fi
}
install_cilium_cli() {
  log "Installing Cilium CLI..."
  local cli_arch cli_version
  cli_arch="$(detect_arch)"
  cli_version="$(curl -fsSL https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)"

  curl -L --fail --remote-name-all \
    "https://github.com/cilium/cilium-cli/releases/download/${cli_version}/cilium-linux-${cli_arch}.tar.gz" \
    "https://github.com/cilium/cilium-cli/releases/download/${cli_version}/cilium-linux-${cli_arch}.tar.gz.sha256sum"

  # Check checksum (Optional)
  sha256sum --check "cilium-linux-${cli_arch}.tar.gz.sha256sum" || warn "Checksum validation skipped"

  # Extract to /usr/local/bin ensuring it's executable
  tar -C /usr/local/bin -xzvf "cilium-linux-${cli_arch}.tar.gz"
  rm -f "cilium-linux-${cli_arch}.tar.gz" "cilium-linux-${cli_arch}.tar.gz.sha256sum"

  # Ensure the binary is in PATH
  export PATH="/usr/local/bin:$PATH"

  # Verify installation
  if ! command -v cilium >/dev/null 2>&1; then
    error_exit "Cilium CLI was not installed correctly."
  fi

  log "Cilium CLI installed successfully"
}

install_hubble_cli() {
  log "Installing Hubble CLI..."
  local hubble_arch hubble_version
  hubble_arch="$(detect_arch)"
  hubble_version="$(curl -fsSL https://raw.githubusercontent.com/cilium/hubble/master/stable.txt)"

  curl -L --fail --remote-name-all \
    "https://github.com/cilium/hubble/releases/download/${hubble_version}/hubble-linux-${hubble_arch}.tar.gz" \
    "https://github.com/cilium/hubble/releases/download/${hubble_version}/hubble-linux-${hubble_arch}.tar.gz.sha256sum"

  # Check checksum (Optional)
  sha256sum --check "hubble-linux-${hubble_arch}.tar.gz.sha256sum" || warn "Checksum validation skipped"

  # Extract to /usr/local/bin ensuring it's executable
  tar -C /usr/local/bin -xzvf "hubble-linux-${hubble_arch}.tar.gz"
  rm -f "hubble-linux-${hubble_arch}.tar.gz" "hubble-linux-${hubble_arch}.tar.gz.sha256sum"

  # Ensure the binary is in PATH
  export PATH="/usr/local/bin:$PATH"

  # Verify installation
  if ! command -v hubble >/dev/null 2>&1; then
    error_exit "Hubble CLI was not installed correctly."
  fi

  log "Hubble CLI installed successfully"
}

bootstrap_master() {
  local private_ip

  log "Setting hostname for control-plane node..."
  hostnamectl set-hostname "${CONTROL_PLANE_HOSTNAME}"

  if [[ -n "${API_ADVERTISE_ADDRESS}" ]]; then
    private_ip="${API_ADVERTISE_ADDRESS}"
    log "Using API advertise address from environment: ${private_ip}"
  else
    private_ip="$(detect_private_ip)"
    log "Detected private IP for API advertise address: ${private_ip}"
  fi

  ensure_hostname_mapping "${private_ip}"
  configure_firewalld

  if [[ -f /etc/kubernetes/admin.conf ]]; then
    warn "Kubernetes control-plane appears to be already initialized. Skipping kubeadm init."
  else
    log "Initializing Kubernetes control-plane..."
    kubeadm init \
      --apiserver-advertise-address="${private_ip}" \
      --cri-socket="${CONTAINERD_SOCK}"
  fi

  configure_kubectl_access
  install_cilium_cli

  log "Installing Cilium ${CILIUM_VERSION}..."
  cilium install --version "${CILIUM_VERSION}"

  log "Waiting for Cilium to become ready..."
  cilium status --wait

  log "Enabling Hubble Relay and UI..."
  cilium hubble enable --ui

  install_hubble_cli

  echo
  echo "============================================================================"
  log "Use the following command on worker nodes to join the cluster:"
  kubeadm token create --print-join-command
  echo "============================================================================"
  echo

  log "Current node status:"
  kubectl get nodes -o wide

  echo
  log "To use Hubble CLI locally later:"
  echo "cilium hubble port-forward &"
  echo "hubble status"
}

prepare_worker() {
  log "Setting hostname for worker node..."
  hostnamectl set-hostname "${WORKER_HOSTNAME}"

  local private_ip
  private_ip="$(detect_private_ip)"
  ensure_hostname_mapping "${private_ip}"
  configure_firewalld

  echo
  echo "============================================================================"
  log "Worker node is ready for cluster join. Run the join command generated on the master."
  echo "Example:"
  echo "kubeadm join <CONTROL-PLANE-IP>:6443 --token <TOKEN> --discovery-token-ca-cert-hash sha256:<HASH> --cri-socket ${CONTAINERD_SOCK}"
  echo "============================================================================"
  echo ""
  echo ""
  echo "============================================================================"
  warn "
  Execute below commands to deploy hubble pods on control-plane if you have one Master node cluster only for testing purpose only 

  kubectl patch deployment hubble-relay -n kube-system -p \
  '{"spec": {"template": {"spec": {"tolerations": [{"key": "node-role.kubernetes.io/control-plane", "operator": "Exists", "effect": "NoSchedule"}]}}}}'

  kubectl patch deployment hubble-ui -n kube-system -p \
  '{"spec": {"template": {"spec": {"tolerations": [{"key": "node-role.kubernetes.io/control-plane", "operator": "Exists", "effect": "NoSchedule"}]}}}}'
  "
  echo "============================================================================"

}

main() {
  require_root
  verify_os
  choose_role
  update_system
  install_prereqs
  configure_selinux
  configure_modules_and_sysctl
  configure_swap
  enable_cgroup_v2_boot
  install_containerd
  install_kubernetes_packages
  verify_installation

  case "${NODE_ROLE}" in
    master) bootstrap_master ;;
    worker) prepare_worker ;;
  esac

  log "RHEL 8 Kubernetes setup completed successfully for role: ${NODE_ROLE}"
}

main "$@"



