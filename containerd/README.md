# Containerd Directory Overview

This directory contains the required tasks to install and configure `containerd` as the primary CRI (Container Runtime Interface) for Kubernetes.

## Table of Contents

- [1. `containerd.yml`](#1-containerdyml)
  - [What it does](#what-it-does)
  - [How it works](#how-it-works)
  - [Where it executes](#where-it-executes)
  - [Line-by-Line Breakdown](#line-by-line-breakdown)

---

## 1. `containerd.yml`

### What it does

This playbook fully installs `containerd`, `runc`, and the base CNI plugins directly from their GitHub release tarballs, bypassing OS package managers to ensure the exact upstream versions are used. It then configures `containerd` to use the `systemd` cgroup driver, which is a strict requirement for modern `kubeadm` deployments.

### How it works

It downloads pre-compiled release tarballs, extracts them to the appropriate system directories (`/usr/local`, `/usr/local/sbin`, `/opt/cni/bin`), generates a default `config.toml`, forcefully patches it to enable the `SystemdCgroup` flag, and enables the `containerd` systemd service.

### Where it executes

This playbook is executed on **all nodes** (control plane and workers) when the `runtime: containerd` variable is set in the `create_k8s.yml` playbook.

---

### Line-by-Line Breakdown

#### Lines 1-8: Download and Install Containerd

```yaml
- name: Download containerd
  ansible.builtin.get_url:
    url: https://github.com/containerd/containerd/releases/download/v2.0.2/containerd-2.0.2-linux-amd64.tar.gz
    dest: /tmp/containerd-2.0.2-linux-amd64.tar.gz

- name: Extract containerd
  ansible.builtin.unarchive:
    src: /tmp/containerd-2.0.2-linux-amd64.tar.gz
    dest: /usr/local
    remote_src: true
```

Downloads the `containerd` v2.0.2 release tarball from GitHub to `/tmp` and extracts the binaries (`containerd`, `ctr`, etc.) directly into `/usr/local/bin` / `/usr/local/sbin`.

#### Lines 10-17: Install the Systemd Service File

```yaml
- name: Download containerd systemd service file
  ansible.builtin.get_url:
    url: https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
    dest: /etc/systemd/system/containerd.service

- name: Reload systemd daemon
  ansible.builtin.systemd:
    daemon_reload: true
```

Fetches the official `containerd.service` definition file from the main GitHub repository, places it in `/etc/systemd/system/`, and tells systemd to reload its daemon to recognize the new service.

#### Lines 19-26: Install runc

```yaml
- name: Download runc
  ansible.builtin.get_url:
    url: https://github.com/opencontainers/runc/releases/download/v1.2.4/runc.amd64
    dest: /usr/local/sbin/runc
    mode: "0755"
```

Downloads `runc` v1.2.4. `runc` is the low-level OCI container runtime that `containerd` uses to actually spawn the Linux namespaces and namespaces for the pods. It is made executable (`0755`) immediately upon download.

#### Lines 28-40: Install base CNI plugins

```yaml
- name: Ensure /opt/cni/bin directory exists
  ansible.builtin.file:
    path: /opt/cni/bin
    state: directory
    mode: "0755"

- name: Download and extract CNI plugins
  ansible.builtin.unarchive:
    url: https://github.com/containernetworking/plugins/releases/download/v1.6.2/cni-plugins-linux-amd64-v1.6.2.tgz
    dest: /opt/cni/bin
    remote_src: true
```

Creates `/opt/cni/bin` and downloads the standard `containernetworking` plugin binaries (like `bridge`, `loopback`, `portmap`). `containerd` requires these before the Kubernetes-specific network plugin (like Calico or Flannel) is applied.

#### Lines 42-53: Generate Default Configuration

```yaml
- name: Create containerd config directory
  ansible.builtin.file:
    path: /etc/containerd
    state: directory

- name: Generate default containerd config
  ansible.builtin.shell: containerd config default > /etc/containerd/config.toml
  args:
    creates: /etc/containerd/config.toml
```

Creates the `/etc/containerd` folder and runs `containerd config default` to generate a boilerplate `config.toml`. The `creates` directive ensures this shell command only ever runs once (idempotency).

#### Lines 55-60: Patch for SystemdCgroup

```yaml
- name: Configure containerd to use systemd cgroup driver
  ansible.builtin.replace:
    path: /etc/containerd/config.toml
    regexp: 'SystemdCgroup = false'
    replace: 'SystemdCgroup = true'
  notify: Restart containerd
```

*Crucial step:* Kubernetes uses `systemd` to manage the cgroups of the OS. If `containerd` uses the default `cgroupfs` driver instead, the system will have two duplicate cgroup managers fighting each other, causing node instability. This regex finds `SystemdCgroup = false` inside the TOML and flips it to `true`. If a change happens, it notifies the `Restart containerd` handler.

#### Lines 62-66: Enable and Start Service

```yaml
- name: Enable and start containerd service
  ansible.builtin.service:
    name: containerd
    enabled: true
    state: started
```

Tells `systemd` to enable `containerd` to start on boot, and starts it right now.
