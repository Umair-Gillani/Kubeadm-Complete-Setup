# Kubeadm-Complete-Setup

# Kubernetes + Cilium Setup Script

This project provides a Bash script to automate the installation and configuration of Kubernetes prerequisites and the Cilium CNI plugin. It is intended for **Debian/Ubuntu-based** systems.

---

## Run this Script Directly into your VM

> **Note:** Switch to root user.


```bash
curl -s https://raw.githubusercontent.com/Umair-Gillani/Kubeadm-Complete-Setup/main/Kubeadm-Complete-Setup.sh | bash
```

or

```bash
wget -qO- https://raw.githubusercontent.com/Umair-Gillani/Kubeadm-Complete-Setup/main/Kubeadm-Complete-Setup.sh | bash
```


---

## Overview

1. **Updates and upgrades packages** to ensure your system is up to date.
2. **Installs prerequisites** needed for Kubernetes and Cilium (e.g., `apt-transport-https`, `ca-certificates`, `curl`, `gpg`).
3. **Disables swap** and removes swap entries from `/etc/fstab`.
4. **Installs and configures containerd** to use the systemd cgroup driver.
5. **Adds the Kubernetes apt repository** and installs `kubeadm`, `kubelet`, and `kubectl`.
6. **Enables required kernel modules** (`overlay`, `br_netfilter`) and configures sysctl for Kubernetes networking.
7. **Prompts whether the node is a master node** or a worker node.
   - If **master** (enter `1`), the script installs **Cilium** as the CNI.
   - If **worker** (press **Enter**), the script **skips** the Cilium installation.
8. **Checks versions** of all critical components.

---

## Usage

1. **Clone or download** this repository so you have the setup script (`setup-k8s.sh`) and this `README.md`.
2. **Make the script executable**:
   ```bash
   chmod +x setup-k8s.sh
   ```
3. **Run the script** as root (or via sudo):
   ```bash
   sudo ./setup-k8s.sh
   ```
4. When prompted:
   - Press **1** to indicate this is a **master node** (Cilium will be installed).
   - Press **Enter** (or anything other than 1) if it is a **worker node** (Cilium will be skipped).

---

## Requirements

- **Operating System**: Debian or Ubuntu-based distribution.
- **Privileges**: Must be run as root or via `sudo`.
- **Internet connection**: Required to fetch packages from apt repositories and GitHub.

---

## What it does

### Kubernetes Prerequisites
- **Updates apt repositories** and upgrades the system.
- **Installs** `apt-transport-https`, `ca-certificates`, `curl`, and `gpg`.
- **Disables swap** to meet Kubernetes requirements.
- **Installs containerd** and configures it to use the systemd cgroup driver.
- **Sets up Kubernetes apt repository**, installs `kubeadm`, `kubelet`, and `kubectl`, then pins them so they are not upgraded inadvertently.
- **Enables the `kubelet`** service.
- **Ensures kernel modules** and sysctl settings are properly configured for Kubernetes networking.

### Cilium Installation
- Downloads the **Cilium CLI** from the official GitHub releases.
- Installs **Cilium** (version 1.17.2) and waits a few seconds to confirm it’s active.
- Validates by checking **`cilium status`**.

---

## Notes

- For multi-node clusters, run this script on each node. On **master** (or control-plane) nodes, answer **1** to install the Cilium CNI. On **worker** nodes, press **Enter** to skip Cilium.
- If you need a different Cilium version, you can edit the command at the end of the script where `cilium install --version 1.17.2` is specified.
- If your architecture is **arm64**, the script automatically detects and downloads the correct `arm64` version of the Cilium CLI.

---

## Troubleshooting

- **Permission issues**: Ensure the script is run with `sudo` or as root.
- **Port conflicts**: If you have existing services on ports used by Kubernetes or containerd, you may need to reconfigure or disable them.
- **Network connectivity**: If the script fails to fetch files from the internet, verify your DNS and routing.
- **cgroup driver mismatches**: Make sure the container runtime (containerd) and Kubernetes are both using the same driver (systemd is recommended). This script enforces systemd.

---

## Contributing

If you find issues or have improvements, feel free to open a pull request or file an issue in the repository.

---

## License

This script and README are provided under the [MIT License](https://opensource.org/licenses/MIT). Please see the `LICENSE` file for details.

