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

This playbook installs `containerd` using official package repositories (Docker) for Ubuntu, Fedora, RHEL, and CentOS. It ensures that `containerd` is configured with the `systemd` cgroup driver, which is a strict requirement for modern Kubernetes deployments.

### How it works

It adds the official Docker GPG keys and repository definitions for the target OS, installs the `containerd` package natively, generates a default configuration file, and patches it to enable `SystemdCgroup`.

### Where it executes

This playbook is executed on **all nodes** (control plane and workers) when the `runtime: containerd` variable is set in the `create_k8s.yml` playbook.

---

### Line-by-Line Breakdown

#### Lines 4-19: Add GPG Key and Repo (Ubuntu)

```yaml
- name: Add GPG key for Docker
  ansible.builtin.apt_key:
    url: https://download.docker.com/linux/ubuntu/gpg
    state: present
    keyring: /etc/apt/keyrings/docker.asc

- name: Add repo for containerd on Ubuntu
  ansible.builtin.apt_repository:
    repo: "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu {{ ansible_distribution_release }} stable"
```

Adds the secure Docker repository to Ubuntu so we can fetch the latest stable `containerd` package directly from the source.

#### Lines 21-49: Add Repositories (RHEL/CentOS/Fedora)

Configures the official Docker-CE repository files for RedHat-based distributions using the `yum_repository` module.

#### Lines 54-66: Install Packages

Installs the native `containerd` (and `runc` on Ubuntu) packages using the OS-specific package manager (`apt` or `dnf`).

#### Lines 75-91: Generate Configuration

```yaml
- name: Generate default containerd configuration
  ansible.builtin.command: containerd config default
  register: containerd_default_config

- name: Write default configuration to /etc/containerd/config.toml
  ansible.builtin.copy:
    content: "{{ containerd_default_config.stdout }}"
    dest: /etc/containerd/config.toml
```

Uses the `containerd` binary itself to generate a standard boilerplate configuration, which is then saved to `/etc/containerd/config.toml`.

#### Lines 93-98: Enable SystemdCgroup

```yaml
- name: Enable SystemdCgroup in containerd config
  ansible.builtin.replace:
    path: /etc/containerd/config.toml
    regexp: '(\[plugins\."io\.containerd\.grpc\.v1\.cri"\.containerd\.runtimes\.runc\.options\][\s\S]*?)SystemdCgroup\s*=\s*false'
    replace: '\1SystemdCgroup = true'
```

*Crucial step:* Instructs `containerd` to use the `systemd` cgroup driver. If this isn't set to `true`, the `kubelet` will fail to start or will be unstable because it expects `systemd` to manage cgroups.

#### Lines 100-105: Start and Enable Service

Ensures the `containerd` service is restarted to apply the new configuration and set to start automatically on boot.
