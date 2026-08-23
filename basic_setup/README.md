# Base system configuration

Foundational OS tasks executed across all nodes before container runtime and Kubernetes packages are installed.

## Tasks overview (`system_settings.yml`)

1. **Kernel modules:**
   - Loads `overlay` and `br_netfilter` modules immediately via `modprobe` and persists them in `/etc/modules-load.d/containerd.conf` or `/etc/modules-load.d/crio.conf`.

2. **Sysctl network routing:**
   - Configures `/etc/sysctl.d/kubernetes.conf` with:
     ```ini
     net.bridge.bridge-nf-call-ip6tables = 1
     net.bridge.bridge-nf-call-iptables = 1
     net.ipv4.ip_forward = 1
     ```
   - Reloads settings via `sysctl --system`.

3. **Swap deactivation:**
   - Runs `swapoff -a`.
   - Comments out swap entries in `/etc/fstab` to persist across reboots.
   - On Fedora/RHEL/CentOS/Rocky distributions, uninstalls `zram-generator-defaults` if present.

4. **Firewall service and ports:**
   - Ensures `firewalld` (RHEL/Rocky/Fedora) or `ufw` (Debian/Ubuntu) is enabled and running when `firewall_enabled: true`.
   - Opens Kubernetes API, etcd, kubelet, and CNI ports (Flannel VXLAN `8472/udp`, Calico BGP `179/tcp`, Calico VXLAN `4789/udp`).
   - For Calico on RHEL: opens IP protocol `ipip`, adds `cali+`, `tunl0`, and `vxlan.calico` interfaces along with `pod_network_cidr` to the `trusted` zone, and enables masquerading.
