# containerd runtime configuration

Tasks to install and configure containerd across cluster nodes.

## Tasks overview (`containerd.yml`)

1. **Repository and GPG keys:**
   - Debian/Ubuntu: adds the Docker GPG keyring and defines the repository using `deb822_repository`.
   - RHEL/Fedora/Rocky/CentOS: creates `/etc/yum.repos.d/docker-ce.repo` using `yum_repository`.

2. **Package installation:**
   - Installs `containerd.io` (and `runc` on Debian/Ubuntu) through the native package manager.

3. **Runtime configuration:**
   - Generates the default configuration via `containerd config default` to `/etc/containerd/config.toml`.
   - Sets `SystemdCgroup = true` so the cgroup driver matches kubelet requirements.

4. **Service management:**
   - Enables and restarts `containerd.service`.
