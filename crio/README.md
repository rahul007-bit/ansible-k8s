# CRI-O Directory Overview

This directory contains tasks responsible for installing and configuring CRI-O, an alternate Container Runtime Interface optimized purely for Kubernetes.

## Table of Contents

- [1. `cri-o.yml`](#1-cri-oyml)
  - [Line-by-Line Breakdown](#line-by-line-breakdown)
- [2. `install/os_updates.yml`](#2-installos_updatesyml)
  - [What `os_updates.yml` does](#what-os_updatesyml-does)
  - [`os_updates.yml` Line-by-Line Breakdown](#os_updatesyml-line-by-line-breakdown)

---

## 1. `cri-o.yml`

### What it does

Provides a complete installation and configuration of the `cri-o` daemon on both Ubuntu/Debian and RHEL/CentOS systems via package managers.

### How it works

It first runs OS-specific prerequisite updates from `os_updates.yml`, ensures conflicting container runtimes like `containerd` are disabled, configures the `cri-o` package repositories matching the `crio_version`, installs the binary, and manages its systemd service.

### Where it executes

It runs on **all nodes** in the cluster when the `runtime: crio` variable is defined in the main `create_k8s.yml` playbook.

---

### Line-by-Line Breakdown

#### Lines 1-3: Import OS updates

#### Lines 5-9: Disable containerd (if present)

```yaml
- name: Disable containerd (if present)
  ansible.builtin.service:
    name: containerd
    state: stopped
    enabled: false
  ignore_errors: true
```

Because the `create_k8s.yml` logic defaults to trying containerd or might be run on a node that previously had Docker/containerd installed, we force-stop and disable `containerd` here so the two runtimes do not fight for control over the container ports, namespaces, or cgroups.

#### Ubuntu/Debian Execution Path

#### Lines 12-22: Download CRI-O GPG keys (Ubuntu)

```yaml
- name: Download CRI-O RPM GPG key (Ubuntu)
  ansible.builtin.get_url:
    url: "https://pkgs.k8s.io/addons:/cri-o:/prerelease:/main/deb/Release.key"
    dest: /tmp/crio-Release.key
    mode: "0644"

- name: De-armor CRI-O GPG key (Ubuntu)
  ansible.builtin.shell: >
    cat /tmp/crio-Release.key | gpg --dearmor -o /etc/apt/keyrings/cri-o-apt-keyring.gpg
```

Similar to Kubernetes, `cri-o` publishes its repository keys. We fetch the official GPG key for the pre-release/stable branches and de-armor it into `/etc/apt/keyrings/cri-o-apt-keyring.gpg` so `apt` implicitly trusts the downloaded packages.

#### Lines 25-32: Add CRI-O repository (Ubuntu)

```yaml
- name: Remove legacy openSUSE kubic CRI-O repositories (Ubuntu)
  ansible.builtin.shell: rm -f /etc/apt/sources.list.d/devel:kubic*

- name: Add CRI-O repository (Ubuntu)
  ansible.builtin.apt_repository:
    repo: >-
      deb [trusted=yes signed-by=/etc/apt/keyrings/cri-o-apt-keyring.gpg]
      https://pkgs.k8s.io/addons:/cri-o:/stable:/{{ crio_version }}/deb/ /
    state: present
    filename: cri-o
```

This step first purges any legacy `devel:kubic` repositories that conflict with modern CRI-O packages. It then creates `/etc/apt/sources.list.d/cri-o.list`, pointing it at the trusted keyring. The `trusted=yes` flag is intentionally injected to bypass `EXPKEYSIG` errors for older, EOL CRI-O versions (like `v1.28`) whose release signatures have officially expired.

Creates `/etc/apt/sources.list.d/cri-o.list`, pointing it at the trusted keyring.

#### Lines 35-43: Install CRI-O packages (Ubuntu)

```yaml
- name: Install CRI-O (Ubuntu)
  ansible.builtin.apt:
    name: cri-o
    state: latest
    update_cache: yes
    dpkg_options: 'force-overwrite'
```

Instructs `apt` to fetch the new definitions and install the `cri-o` primary package natively onto the Ubuntu host. We forcefully use `state: latest` with `force-overwrite` to guarantee that older conflicting packages (like `cri-o-runc`) are completely stomped over without causing `dpkg` to crash during upgrades.

#### RedHat/CentOS/Fedora Execution Path

#### Lines 55-63: Add CRI-O repository (Fedora/RHEL/CentOS)

```yaml
- name: Add CRI-O package repo (RHEL/CentOS/Fedora)
  ansible.builtin.yum_repository:
    name: crio
    description: CRI-O
    baseurl: "https://pkgs.k8s.io/addons:/cri-o:/stable:/{{ crio_version }}/rpm/"
    gpgcheck: true
    gpgkey: "https://pkgs.k8s.io/addons:/cri-o:/stable:/{{ crio_version }}/rpm/repodata/repomd.xml.key"
    enabled: true
```

The OpenSUSE Build Service (`pkgs.k8s.io`) does not natively provide a downloadable `.repo` template file for the `stable` branches. We use Ansible's native `yum_repository` module to dynamically build the RHEL/CentOS equivalent of `/etc/yum.repos.d/crio.repo`.

#### Lines 55-60: Install CRI-O package (RHEL/CentOS/Fedora)

```yaml
- name: Install CRI-O package (RHEL/CentOS/Fedora)
  ansible.builtin.dnf:
    name: cri-o
    state: present
```

Uses `dnf` to install the `cri-o` runtime natively on RedHat/CentOS distributions.

#### Shared Service Logic

#### Lines 63-68: Ensure Systemd Service is Active

```yaml
- name: Enable and restart CRI-O
  ansible.builtin.service:
    name: crio
    state: restarted
    enabled: true
```

Forces `systemd` to enable `crio` to start at boot-up and directly restarts the daemon immediately so its sockets (`/var/run/crio/crio.sock`) are available for `kubeadm init` shortly after this task finishes.

---

## 2. `install/os_updates.yml`

### What `os_updates.yml` does

Runs pre-installation OS maintenance (like a full package upgrade and installing `jq` / `curl` dependencies).

### `os_updates.yml` Line-by-Line Breakdown

```yaml
- name: Update apt cache and upgrade packages (Ubuntu)
  ansible.builtin.apt:
    update_cache: true
    upgrade: "yes"
  when:
    - ansible_distribution == 'Ubuntu'
    - os_upgrade | default(false)
```

Only runs if the user passed `-e os_upgrade=true`. It tells `apt` to run equivalent to `apt-get update && apt-get upgrade -y`.

```yaml
- name: Install prerequisite packages (Ubuntu)
  ansible.builtin.apt:
    name: ["curl", "jq", "software-properties-common", "apt-transport-https", "ca-certificates"]
    state: present
```

Installs basic tools required for keyrings and downloading binaries.

---

## CRI-O Version Upgrades

One of the major benefits of this playbook design is that you can upgrade the CRI-O runtime on a live cluster safely and easily.

Because the installation tasks use `state: latest` and `force-overwrite`, you can push a CRI-O version upgrade across your entire node pool just by changing the variable and re-running the main create playback.

To upgrade CRI-O (e.g. from `v1.28` to `v1.29`):

1. Update `crio_version: "v1.29"` in `create_k8s.yml` (or pass it via `-e crio_version=v1.29`)
2. Run standard cluster creation again:

   ```bash
   ansible-playbook -i hosts create_k8s.yml
   ```

3. The playbook will intelligently:
   - Purge the old `v1.28` repo and load the new `v1.29` keys.
   - Forcefully overwrite the binaries to the `v1.29` branch.
   - Restart the `crio` daemon.

*(Since CRI-O restarts so quickly, running pods will remain largely unaffected except for minor sandbox recreation, resulting in a zero-downtime runtime upgrade).*
