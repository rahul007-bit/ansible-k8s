# CRI-O runtime configuration

Tasks to install, configure, and upgrade the CRI-O container runtime.

## Tasks overview (`crio.yml`)

1. **Stop competing runtimes:**
   - Disables `containerd.service` if present to avoid runtime socket conflicts.

2. **Repository and signing keys:**
   - Debian/Ubuntu: downloads the OpenSUSE CRI-O release key to `/etc/apt/keyrings/` and configures repository sources via `deb822_repository`.
   - RHEL/Fedora/Rocky/CentOS: adds OpenSUSE CRI-O repository definition via `yum_repository`.

3. **Package installation:**
   - Installs `cri-o` (and `cri-tools`) via `apt` or `dnf` in online mode.
   - Installs pre-staged packages via `rpm -Uvh` in offline mode.

4. **Service management:**
   - Enables and restarts `crio.service`.

## Upgrades

To upgrade CRI-O across nodes, run `upgrade_crio.yml`:

```bash
ansible-playbook -i hosts playbooks/upgrade_crio.yml -e crio_version=v1.32
```

This drains each node, stops kubelet, terminates containers to prevent stale state, installs updated packages, and restarts services.
