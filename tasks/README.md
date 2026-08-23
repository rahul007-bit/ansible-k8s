# Kubernetes package installation

Tasks to install `kubeadm`, `kubelet`, and `kubectl` on Debian/Ubuntu and RHEL-family systems.

## Tasks overview (`install_kubernetes.yml`)

1. **Repository and signing keys:**
   - Debian/Ubuntu: downloads the official `pkgs.k8s.io` GPG key to `/etc/apt/keyrings/kubernetes-apt-keyring.gpg` and configures the repository via `deb822_repository`.
   - RHEL/Fedora/Rocky/CentOS: cleans any stale repository files and configures `pkgs.k8s.io` via `yum_repository`.

2. **Package installation:**
   - Online mode: installs pinned versions of `kubelet`, `kubeadm`, and `kubectl` using `apt` or `dnf`.
   - Offline mode: installs pre-staged packages directly using `dpkg -i` or `rpm -Uvh`.

3. **Service management:**
   - Enables `kubelet.service` on boot. The service remains in an inactive/standby state until `kubeadm init` or `kubeadm join` provides configuration files.
