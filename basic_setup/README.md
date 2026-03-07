# Basic Setup Directory Overview

This directory contains foundational OS-level configuration tasks that must be applied to a Linux server before any Kubernetes or container runtime components can function properly.

## Table of Contents

- [1. `system_settings.yml`](#1-system_settingsyml)
  - [What it does](#what-it-does)
  - [How it works](#how-it-works)
  - [Where it executes](#where-it-executes)
  - [Line-by-Line Breakdown](#line-by-line-breakdown)

---

## 1. `system_settings.yml`

### What it does

Configures required Linux kernel modules, sets up IPv4/IPv6 IP forwarding rules in `sysctl`, and permanently disables memory swap partitions/ZRAM.

### How it works

It inserts specific configuration blocks into `/etc/modules-load.d/` and `/etc/sysctl.d/`, dynamically loads the kernel modules into the running operating system, and uses regex replacements on `/etc/fstab` to ensure swap stays off across reboots.

### Where it executes

This task runs on **all nodes** (control plane and workers) at the very beginning of the `create_k8s.yml` playbook.

---

### Line-by-Line Breakdown

#### 1. Kernel Modules Configuration

#### Lines 3-12: Load containerd modules on boot

```yaml
- name: Setup networking of kubernetes
  ansible.builtin.blockinfile:
    path: /etc/modules-load.d/containerd.conf
    block: |
      overlay
      br_netfilter
    backup: true
    create: true
    mode: "0644"
  when: runtime == "containerd"
```

If the container runtime is `containerd`, this task creates `/etc/modules-load.d/containerd.conf`. This tells the Linux kernel to automatically load the `overlay` (for the overlayfs storage driver) and `br_netfilter` (for bridged network traffic) modules every time the system boots.

#### Lines 23-30: Dynamically load modules now

```yaml
- name: Add the overlay module
  community.general.modprobe:
    name: overlay
    state: present
- name: Add the br_netfilter module
  community.general.modprobe:
    name: br_netfilter
    state: present
```

Instead of waiting for a reboot, this uses the `modprobe` command to load `overlay` and `br_netfilter` into the live kernel immediately so the rest of the playbook can proceed.

#### 2. Sysctl Network Routing

#### Lines 13-22: Configure sysctl routing parameters

```yaml
- name: Setup kernel parameters of kubernetes
  ansible.builtin.blockinfile:
    path: /etc/sysctl.d/kubernetes.conf
    block: |
      net.bridge.bridge-nf-call-ip6tables = 1
      net.bridge.bridge-nf-call-iptables = 1
      net.ipv4.ip_forward = 1
    backup: true
    create: true
    mode: "0644"
```

Creates `/etc/sysctl.d/kubernetes.conf`.

- `ip_forward = 1` enables the Linux node to act as a router, which is required for pods to talk to each other across different nodes.
- Setting `bridge-nf-call-iptables = 1` ensures that traffic crossing the Linux bridge interface is passed to iptables for processing, which is required for Kubernetes Services and NetworkPolicies to function.

#### Lines 31-34: Apply sysctl changes

```yaml
- name: Reloading Sysctl
  become: true
  ansible.builtin.command: sysctl --system
  changed_when: false
```

Forces the OS to re-read all `/etc/sysctl.d/` files and apply the routing rules immediately to the active kernel.

#### 3. Disabling Swap Memory

Kubernetes (specifically the `kubelet`) strictly requires swap to be disabled to ensure that its resource limits (CPU/Memory QoS) apply accurately to pods.

#### Lines 35-45: Disabling swap on Ubuntu/Debian

```yaml
- name: Disable swap for Ubuntu
  ansible.builtin.command: swapoff -a
  changed_when: false

- name: Disable swap permanently for Ubuntu
  ansible.builtin.replace:
    path: /etc/fstab
    regexp: ^([^#].*?\sswap\s+sw\s+.*)$
    replace: "# \\1"
```

Turns off active swap via `swapoff -a`. Then uses a regular expression to find any line in `/etc/fstab` containing "swap" and prepends a `#` to comment it out, preventing swap from turning back on after a reboot.

#### Lines 47-64: Disabling ZRAM on Fedora/CentOS/RHEL

```yaml
- name: Disable swap for Fedora and other systems with ZRAM
  ansible.builtin.command: swapoff -a
  changed_when: false
  when: ansible_distribution in ["Fedora", "CentOS", "RHEL"]

- name: Uninstall zram-generator package (Fedora, CentOS, RHEL)
  ansible.builtin.package:
    name: zram-generator-defaults
    state: absent
```

RedHat-derived systems often use ZRAM (compressed RAM swap) instead of traditional disk swap. This halts ZRAM entirely by removing the generator package, ensuring the Kubelet does not crash on startup due to memory compression.
