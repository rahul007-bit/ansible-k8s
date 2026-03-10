# Kubernetes Cluster Automation — Ansible Playbooks

This project automates the deployment and teardown of a Kubernetes cluster using Ansible. It supports multiple container runtimes and CNI plugins, and is designed for bare-metal or VM-based environments.

## Table of Contents

- [What This Playbook Does](#what-this-playbook-does)
  - [`create_k8s.yml` — Full Cluster Bootstrap](#create_k8syml--full-cluster-bootstrap)
  - [`reset-k8s-cluster.yml` — Full Cluster Teardown](#reset-k8s-clusteryml--full-cluster-teardown)
- [Configurable Variables](#configurable-variables)
  - [Default Pod CIDRs (Auto-Selected)](#default-pod-cidrs-auto-selected)
- [Usage Examples](#usage-examples)
- [Project Structure](#project-structure)
- [Inventory Format](#inventory-format)
- [Supported Platforms](#supported-platforms)

---

## What This Playbook Does

### `create_k8s.yml` — Full Cluster Bootstrap

Automates the entire Kubernetes cluster setup end-to-end:

```markdown
System Prep → K8s Packages → Container Runtime → kubeadm init → CNI → Join Masters → Join Workers
```

#### Stage-by-Stage Breakdown

| # | Stage | What Happens | Runs On |
| --- | ------- | ------------- | --------- |
| 1 | **System Preparation** | Loads kernel modules (`overlay`, `br_netfilter`), sets sysctl params, disables swap | All nodes |
| 2 | **Kubernetes Packages** | Installs `kubeadm`, `kubelet`, `kubectl` from `pkgs.k8s.io` | All nodes |
| 3 | **Container Runtime** | Installs & configures the selected runtime (containerd or CRI-O) | All nodes |
| 4 | **Cluster Init** | Runs `kubeadm init` with `--control-plane-endpoint` and `--upload-certs` | First control plane only |
| 5 | **Kubeconfig Setup** | Copies `admin.conf` to `~/.kube/config` | First control plane (optionally all) |
| 6 | **CNI Plugin** | Applies the selected CNI manifest (Calico or Flannel) | First control plane only |
| 7 | **Join Control Plane** | Uploads certs, generates join command, joins additional masters with `--control-plane` | Additional control plane nodes |
| 8 | **Worker Join** | Runs join command on workers | Workers only |

### `reset-k8s-cluster.yml` — Full Cluster Teardown

Cleanly tears down the cluster for a fresh start:

| Stage | What Happens |
| ------- | ------------- |
| 1 | Disables swap |
| 2 | Runs `kubeadm reset -f` |
| 3 | Removes kubelet config and kubeconfig |
| 4 | Cleans up CNI config files (flannel, calico) |
| 5 | Removes leftover containers and images via `crictl` |
| 6 | Deletes Kubernetes directories (`/etc/kubernetes`, `/var/lib/kubelet`, etc.) |
| 7 | **Flushes iptables rules** |
| 8 | **Stops and disables kubelet service** |
| 9 | **Optional Package Purge**: If `remove_packages=true`, uninstalls K8s/CRI-O packages and wipes repos/keys |

---

## Configurable Variables

All variables are defined in `vars/cluster_config.yml` and can be overridden at runtime with `-e`:

| `runtime` | `crio` | `containerd`, `crio` | Container runtime to install |
| `kube_version` | `1.29` | Any version | Kubernetes packages version |
| `crio_version` | `v1.29` | Any version | CRI-O version (only used when `runtime: crio`) |
| `cni_plugin` | `flannel` | `calico`, `flannel` | CNI networking plugin |
| `calico_version` | `v3.26.0` | Any version | Version of the Calico CNI plugin |
| `flannel_version` | `v0.26.0` | Any version | Version of the Flannel CNI plugin |
| `cni_plugins_version` | `v1.6.2` | Any version | Version of the CNI binaries for `/opt/cni/bin` |
| `pod_network_cidr` | Auto-set | Any CIDR | Pod network range (auto-set based on CNI) |
| `kube_user` | `ansible_user` | Any username | User who owns kubeconfig |
| `control_plane_endpoint` | First master's IP | Any IP/hostname | API server endpoint for HA |
| `kubeconfig_on_all_cp` | `false` | `true`, `false` | Copy kubeconfig to all control plane nodes |
| `os_upgrade` | `false` | `true`, `false` | Run full OS package upgrade (apt upgrade / dnf update) |
| `remove_packages` | `false` | `true`, `false` | Purge K8s/CRI-O packages and repos during reset |

### Default Pod CIDRs (Auto-Selected)

| CNI Plugin | Default CIDR |
| ------------ | -------------- |
| Calico | `192.168.0.0/16` |
| Flannel | `10.244.0.0/16` |

---

## Usage Examples

### Create a cluster (defaults: containerd + Calico)

```bash
ansible-playbook -i hosts create_k8s.yml
```

### Create with Flannel instead of Calico

```bash
ansible-playbook -i hosts create_k8s.yml \
  -e cni_plugin=flannel \
  -e cni_version=v0.26.4
```

### Create with CRI-O runtime

```bash
ansible-playbook -i hosts create_k8s.yml -e runtime=crio
```

### Override pod CIDR

```bash
ansible-playbook -i hosts create_k8s.yml -e pod_network_cidr=10.100.0.0/16
```

### Reset the cluster

```bash
ansible-playbook -i hosts reset-k8s-cluster.yml
```

### Dry run (check mode)

```bash
ansible-playbook -i hosts create_k8s.yml --check
```

### Verbose output (debugging)

```bash
ansible-playbook -i hosts create_k8s.yml -vvv
```

---

## Project Structure

```markdown
ansible/
├── basic_setup/
│   └── system_settings.yml         # Kernel modules, sysctl, swap disable
├── containerd/
│   └── containerd.yml              # Containerd install, config, SystemdCgroup
├── crio/
│   ├── cri-o.yml                   # CRI-O dependencies and install
│   ├── group_vars/all              # CRI-O group variables
│   └── install/
│       └── os_updates.yml          # OS package updates
├── tasks/
│   └── install_kubernetes.yml      # Shared: kubeadm, kubelet, kubectl install
├── vars/
│   └── cluster_config.yml          # Unified configuration file
├── create_k8s.yml                  # Main playbook: cluster creation
├── reset-k8s-cluster.yml           # Teardown playbook: cluster reset
├── upgrade_k8s.yml                 # Rolling upgrade playbook
└── hosts                           # Inventory file
```

---

## Inventory Format

The `hosts` file defines your cluster topology:

```ini
[controlplane]
master1 ansible_host=192.168.1.205 ansible_user=rahul
master2 ansible_host=192.168.1.123 ansible_user=rahul

[worker]
worker1 ansible_host=192.168.1.124 ansible_user=rahul

[all:vars]
ansible_python_interpreter=/usr/bin/python3
```

- **`[controlplane]`** — First node runs `kubeadm init`, additional nodes join as control plane members
- **`[worker]`** — Nodes that join the cluster as workers
- **`[all:vars]`** — Variables applied to all hosts

---

## Supported Platforms

| OS | Container Runtime | Tested |
| ---- | ------------------ | -------- |
| Ubuntu 20.04 / 22.04 / 24.04 | containerd, CRI-O | ✅ |
| Fedora 38+ | containerd, CRI-O | ❌ |
| RHEL 8 / 9 | containerd, CRI-O | ❌ |
| CentOS Stream 8 / 9 | containerd, CRI-O | ❌ |
