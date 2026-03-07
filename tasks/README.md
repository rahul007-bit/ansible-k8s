# Tasks Directory Overview

This directory contains standalone Ansible task files that are imported by the main playbooks to keep the code modular and organized.

## Table of Contents

- [1. `install_kubernetes.yml`](#1-install_kubernetesyml)
  - [What it does](#what-it-does)
  - [How it works](#how-it-works)
  - [Where it executes](#where-it-executes)
  - [Line-by-Line Breakdown](#line-by-line-breakdown)

---

## 1. `install_kubernetes.yml`

### What it does

This file is responsible for installing the core Kubernetes binaries (`kubelet`, `kubeadm`, and `kubectl`) directly from the official Kubernetes package repositories onto the operating system.

### How it works

It determines the Linux distribution (Ubuntu vs RHEL-derivatives) and dynamically applies the correct package manager (`apt` or `dnf/yum`). It uses strict version pinning to ensure exactly the requested Kubernetes version is installed.

### Where it executes

This task file is executed on **all nodes** in the cluster (both control plane masters and worker nodes) because every node requires these base binaries to join the cluster.

---

### Line-by-Line Breakdown

#### Ubuntu/Debian Execution Path

#### Lines 1-5: Ensure keyrings directory exists (Ubuntu)

```yaml
- name: Ensure keyrings directory exists (Ubuntu)
  ansible.builtin.file:
    path: /etc/apt/keyrings
    state: directory
    mode: "0755"
```

Creates the `/etc/apt/keyrings` folder. Modern `apt` security requires third-party GPG keys to be stored here rather than the legacy `apt-key` keychain.

#### Lines 9-14: Download Kubernetes GPG key (Ubuntu)

```yaml
- name: Download Kubernetes GPG key (Ubuntu)
  ansible.builtin.get_url:
    url: "https://pkgs.k8s.io/core:/stable:/v{{ kube_version }}/deb/Release.key"
    dest: /tmp/kubernetes-release-key.gpg
    mode: "0644"
```

Fetches the official signing key for the specific Kubernetes minor version (e.g., `v1.32`) requested in the playbook variables.

#### Lines 18-24: De-armor and install Kubernetes GPG key (Ubuntu)

```yaml
- name: De-armor and install Kubernetes GPG key (Ubuntu)
  ansible.builtin.shell: >
    cat /tmp/kubernetes-release-key.gpg | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
```

Converts the downloaded ASCII GPG key into a binary format required by `apt` and places it in the secure keyrings directory.

#### Lines 27-32: Install Kubernetes repository (Ubuntu)

```yaml
- name: Install Kubernetes repository (Ubuntu)
  ansible.builtin.apt_repository:
    repo: "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v{{ kube_version }}/deb/ /"
    state: present
    filename: kubernetes
```

Adds the specific version's package repository to `/etc/apt/sources.list.d/kubernetes.list`, linking it to the newly trusted GPG key.

#### Lines 35-38: Update apt cache (Ubuntu)

```yaml
- name: Update apt cache (Ubuntu)
  ansible.builtin.apt:
    update_cache: true
```

Forces `apt` to refresh its package index so it can see the new `kubelet`, `kubeadm`, and `kubectl` packages.

#### RedHat/CentOS/Fedora Execution Path

#### Lines 41-48: Install Kubernetes repository (Fedora/RHEL/CentOS)

```yaml
- name: Install Kubernetes repository (Fedora/RHEL/CentOS)
  ansible.builtin.yum_repository:
    name: kubernetes
    description: Kubernetes
    baseurl: "https://pkgs.k8s.io/core:/stable:/v{{ kube_version }}/rpm/"
    gpgcheck: true
    gpgkey: "https://pkgs.k8s.io/core:/stable:/v{{ kube_version }}/rpm/repodata/repomd.xml.key"
    enabled: true
```

The Fedora/RHEL equivalent. It creates `/etc/yum.repos.d/kubernetes.repo`, pointing to the specific `{{ kube_version }}` URL, and enables GPG signature checking.

#### Cross-Platform Installation & Enablement

#### Lines 51-59: Installing binaries (Ubuntu)

```yaml
- name: Installing kubelet, kubeadm, and kubectl (Ubuntu)
  ansible.builtin.apt:
    name:
      - "kubelet={{ kube_version }}.*"
      - "kubeadm={{ kube_version }}.*"
      - "kubectl={{ kube_version }}.*"
    state: present
    allow_downgrade: true
    allow_change_held_packages: true
```

Installs the packages via `apt`. The version lock (`{{ kube_version }}.*`) instructs Ubuntu to grab the latest patch for that minor version. `allow_downgrade` and `allow_change_held_packages` act as a safeguard to bypass `dpkg-hold` locks from prior upgrades, forcing the exact requested version to be installed.

#### Lines 61-69: Installing binaries (RHEL/CentOS/Fedora)

```yaml
- name: Installing kubelet, kubeadm, and kubectl (RHEL/CentOS/Fedora)
  ansible.builtin.dnf:
    name:
      - "kubelet-{{ kube_version }}.*"
      - "kubeadm-{{ kube_version }}.*"
      - "kubectl-{{ kube_version }}.*"
    state: present
    allow_downgrade: true
```

The Fedora/RHEL equivalent using `dnf`.

#### Lines 71-74: Enabling kubelet service

```yaml
- name: Enabling kubelet service
  ansible.builtin.service:
    name: kubelet
    enabled: true
```

Tells `systemd` to automatically start the `kubelet` agent on server boot up. Note that we do not `start` the service here — `kubelet` stays in a crash-loop state until `kubeadm init` or `kubeadm join` provides it with configuration files.
