
#!/usr/bin/env bash
#===============================================================================
# This script sets up Kubernetes prerequisites on a Debian/Ubuntu-based system.
#
# It:
#   1. Updates and upgrades system packages
#   2. Disables swap and removes swap entries from /etc/fstab
#   3. Installs and configures containerd
#   4. Adds Kubernetes apt repository and installs kubeadm, kubelet, and kubectl
#   5. Configures sysctl for Kubernetes networking
#   6. Ensures all critical services are enabled and checks versions
#
# Usage:
#   sudo ./setup-k8s.sh
#
# IMPORTANT: Make sure you run this script as root or via sudo.
#===============================================================================
set -Eeuo pipefail

#--- HELPER FUNCTIONS ----------------------------------------------------------
log() {
  echo -e "\\033[1;34m[INFO] $*\\033[0m"
}

error_exit() {
  echo -e "\\033[1;31m[ERROR] $*\\033[0m" >&2
  exit 1
}

#--- PRE-CHECKS ----------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
  error_exit "Please run this script as root (e.g. sudo ./setup-k8s.sh)."
fi


log "Setting Hostname according to your Nodes, Is this your MASTER NODE?"
read -p "Press 1 for master, or press Enter for worker: " NODE_CHOICE

if [ "$NODE_CHOICE" = "1" ]; then
  log "Master Node Selected, Changing Hostname of this Machine..."
  hostnamectl set-hostname master
  
else 
  log "Worker Node Selected, Changing Hostname of this Machine..."
  hostnamectl set-hostname worker

fi



#--- 1. UPDATE & UPGRADE PACKAGES ---------------------------------------------
log "Updating and upgrading system packages..."
apt-get update -y || error_exit "Failed to update package lists."
apt-get upgrade -y || error_exit "Failed to upgrade packages."

#--- 2. INSTALL PREREQUISITES --------------------------------------------------
log "Installing general dependencies..."
apt-get install -y apt-transport-https ca-certificates curl gpg || \
  error_exit "Failed to install apt-transport-https, ca-certificates, curl, gpg."

#--- 3. LOAD KERNEL MODULES ----------------------------------------------------
log "Loading kernel modules (overlay, br_netfilter)..."
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

# Immediately load the modules
modprobe overlay || error_exit "Failed to load module: overlay."
modprobe br_netfilter || error_exit "Failed to load module: br_netfilter."

#--- 4. DISABLE SWAP -----------------------------------------------------------
log "Disabling swap..."
swapoff -a || error_exit "Failed to swap off."
# Optional: remove any swap entries from /etc/fstab to avoid re-enabling after reboot
sed -i '/swap/d' /etc/fstab

#--- 5. DIST UPGRADE -----------------------------------------------------------
log "Performing dist-upgrade..."
apt-get update -y || error_exit "Failed to update package lists (second time)."
apt-get dist-upgrade -y || error_exit "Failed to dist-upgrade."

#--- 6. INSTALL & CONFIGURE CONTAINERD -----------------------------------------
log "Installing containerd..."
apt-get install -y containerd || error_exit "Failed to install containerd."
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml

# Configure systemd cgroup driver
log "Configuring containerd to use systemd as cgroup driver..."
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

log "Restarting and enabling containerd..."
systemctl restart containerd || error_exit "Failed to restart containerd."
systemctl enable containerd || error_exit "Failed to enable containerd."

#--- 7. ADD KUBERNETES REPOSITORY & INSTALL KUBELET, KUBEADM, KUBECTL ---------
log "Configuring Kubernetes apt repository..."
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | \
  gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg || \
  error_exit "Failed to import Kubernetes GPG key."

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' \
  | tee /etc/apt/sources.list.d/kubernetes.list

log "Updating package lists and installing kubelet, kubeadm, kubectl..."
apt-get update -y || error_exit "Failed to update package lists for Kubernetes."
apt-get install -y kubelet kubeadm kubectl || error_exit "Failed to install Kubernetes components."

# Prevent them from being upgraded accidentally
apt-mark hold kubelet kubeadm kubectl

log "Enabling kubelet service..."
systemctl enable --now kubelet || error_exit "Failed to enable kubelet."

#--- 8. KERNEL SYSCTL SETTINGS FOR K8S -----------------------------------------
log "Configuring sysctl for Kubernetes networking..."
# net.ipv4.ip_forward
cat <<EOF | tee /etc/sysctl.d/99-k8s-ipforward.conf
net.ipv4.ip_forward = 1
EOF

sysctl --system || error_exit "Failed to apply sysctl changes."
sysctl net.ipv4.ip_forward

# br_netfilter
cat <<EOF | tee /etc/sysctl.d/99-k8s-brnetfilter.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables  = 1
EOF

sysctl --system || error_exit "Failed to apply br_netfilter changes."

#--- 9. VERIFY INSTALLATION ----------------------------------------------------
log "Verifying kubeadm, kubelet, and kubectl versions..."
echo " "
echo " "
log "kubeadm version..."
kubeadm version   || error_exit "kubeadm not found or failed to run."
echo " "
log "kubelet version..."
kubelet --version || error_exit "kubelet not found or failed to run."
echo " "
log "kubectl version..."
kubectl version --client || error_exit "kubectl not found or failed to run."
echo " "
echo " "
log "Setup complete. Your system is ready for Kubernetes!"


# ==========================================================================

log "Is this your MASTER NODE?"
read -p "Press 1 for master, or press Enter for worker: " NODE_CHOICEs

if [ "$NODE_CHOICEs" = "1" ]; then

        #--- 10. Cilinium CLI INSTALLATION ----------------------------------------------------
        log "Installing Cilium CLI..."
        CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
        CLI_ARCH=amd64
        if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
        curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
        sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
        sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
        rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}


        #--- 11. Cilinium INSTALLATION ----------------------------------------------------
        log "Installing Cilium..."
        cilium install --version 1.17.2
        sleep 10
        cilium status

else
  echo "Worker node selected. Skipping Cilium installation."
fi
