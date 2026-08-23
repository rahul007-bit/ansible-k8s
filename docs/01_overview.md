# Overview and architecture

This project sets up and tears down Kubernetes clusters with Ansible. It supports CRI-O and containerd runtimes with Calico or Flannel networking on bare-metal and VM nodes.

## Table of contents

- [Playbooks](#playbooks)
  - [`create_k8s.yml`: full cluster bootstrap](#create_k8syml-full-cluster-bootstrap)
  - [`reset-k8s-cluster.yml`: full cluster teardown](#reset-k8s-clusteryml-full-cluster-teardown)
- [Configuration variables](#configuration-variables)
  - [Default pod CIDRs](#default-pod-cidrs)
- [Usage examples](#usage-examples)
- [Project structure](#project-structure)
- [Inventory format](#inventory-format)
- [Supported platforms](#supported-platforms)

---

## Playbooks

### `create_k8s.yml`: full cluster bootstrap

Bootstraps the cluster through these stages:

```text
System prep -> K8s packages -> Container runtime -> kubeadm init -> CNI -> Join masters -> Join workers
```

#### Stage breakdown

| # | Stage | Action | Target nodes |
| - | ----- | ------ | ------------ |
| 1 | System preparation | Loads kernel modules (`overlay`, `br_netfilter`), sets sysctl parameters, disables swap, configures firewall rules | All nodes |
| 2 | Kubernetes packages | Installs `kubeadm`, `kubelet`, `kubectl` | All nodes |
| 3 | Container runtime | Installs and configures containerd or CRI-O | All nodes |
| 4 | Cluster init | Runs `kubeadm init` with `--control-plane-endpoint` and `--upload-certs` | First control plane node |
| 5 | Kubeconfig setup | Copies `admin.conf` to `~/.kube/config` | First control plane node (optionally all) |
| 6 | CNI plugin | Applies Calico or Flannel manifest | First control plane node |
| 7 | Join control plane | Uploads certificates and joins extra control plane nodes | Additional control plane nodes |
| 8 | Join workers | Runs worker join command | Worker nodes |

### `reset-k8s-cluster.yml`: full cluster teardown

Tears down the cluster for a clean restart:

| Step | Action |
| ---- | ------ |
| 1 | Disables swap |
| 2 | Runs `kubeadm reset -f` |
| 3 | Removes kubelet configuration and kubeconfig |
| 4 | Deletes CNI configuration files (`/etc/cni/net.d/`) and removes leftover network interfaces |
| 5 | Stops and removes leftover containers and images via `crictl` |
| 6 | Deletes Kubernetes data directories (`/etc/kubernetes`, `/var/lib/kubelet`, `/var/lib/etcd`) |
| 7 | Flushes iptables rules |
| 8 | Stops and disables kubelet service |
| 9 | If `remove_packages=true`, uninstalls Kubernetes and runtime packages and deletes repository files |

---

## Configuration variables

Variables live in `vars/cluster_config.yml` and can be overridden via `-e`:

| Variable | Default | Options | Description |
| -------- | ------- | ------- | ----------- |
| `offline_install` | `false` | `true`, `false` | Enable offline installation mode |
| `offline_pkg_type` | `zip` | `zip`, `dir` | Package bundle format |
| `offline_pkg_source` | `controller` | `controller`, `remote` | Where package files are stored |
| `offline_pkg_path` | `k8s_rpm.zip` | Path | Source path to directory or archive |
| `remote_pkg_dir` | `/tmp/k8s_packages` | Path | Target package directory on remote nodes |
| `runtime` | `crio` | `containerd`, `crio` | Container runtime |
| `kube_version` | `1.32` | Version string | Kubernetes package version (e.g., `1.32` or `1.32.2`) |
| `crio_version` | `v1.32` | Version string | CRI-O version (used when `runtime: crio`) |
| `cni_plugin` | `calico` | `calico`, `flannel` | CNI network plugin |
| `calico_version` | `v3.26.0` | Version tag | Calico manifest release version |
| `flannel_version` | `v0.28.3` | Version tag | Flannel release version |
| `cni_plugins_version` | `v1.6.2` | Version tag | Standard CNI plugins archive version |
| `pod_network_cidr` | Auto-selected | CIDR string | Pod subnet range |
| `kube_user` | `ansible_user` | Username | User account owning `~/.kube/config` |
| `control_plane_endpoint` | First master IP | IP or DNS | Control plane endpoint address |
| `kubeconfig_on_all_cp` | `false` | `true`, `false` | Copy kubeconfig to all control plane nodes |
| `os_upgrade` | `false` | `true`, `false` | Upgrade OS packages before install |
| `remove_packages` | `false` | `true`, `false` | Remove packages and repo definitions on reset |

### Default pod CIDRs

| CNI plugin | Default CIDR |
| ---------- | ------------ |
| Calico | `192.168.0.0/16` |
| Flannel | `10.244.0.0/16` |

---

## Usage examples

Create a cluster with defaults:

```bash
ansible-playbook -i hosts playbooks/create_k8s.yml
```

Create a cluster with Flannel:

```bash
ansible-playbook -i hosts playbooks/create_k8s.yml \
  -e cni_plugin=flannel \
  -e flannel_version=v0.28.3
```

Create a cluster with CRI-O:

```bash
ansible-playbook -i hosts playbooks/create_k8s.yml -e runtime=crio
```

Override pod CIDR:

```bash
ansible-playbook -i hosts playbooks/create_k8s.yml -e pod_network_cidr=10.100.0.0/16
```

Reset the cluster:

```bash
ansible-playbook -i hosts playbooks/reset-k8s-cluster.yml
```

Run in check mode:

```bash
ansible-playbook -i hosts playbooks/create_k8s.yml --check
```

---

## Project structure

```text
ansible/
├── basic_setup/
│   └── system_settings.yml         # Kernel modules, sysctl, swap, firewalld
├── containerd/
│   └── containerd.yml              # containerd installation and config
├── crio/
│   ├── cri-o.yml                   # CRI-O installation and config
│   └── install/
│       └── os_updates.yml          # OS updates
├── tasks/
│   ├── install_kubernetes.yml      # kubeadm, kubelet, kubectl installation
│   ├── offline_image_load.yml      # Offline container image loader
│   ├── offline_package_prep.yml    # Offline package extraction
│   └── prerequisites.yml           # Automated pre-flight checks
├── vars/
│   └── cluster_config.yml          # Main variable definitions
├── playbooks/
│   ├── create_k8s.yml              # Cluster creation entrypoint
│   ├── prerequisites.yml           # Pre-flight check entrypoint
│   ├── reset-k8s-cluster.yml       # Cluster teardown entrypoint
│   ├── upgrade_k8s.yml             # Kubernetes version upgrade
│   └── upgrade_crio.yml            # CRI-O runtime upgrade
└── hosts                           # Inventory file
```

---

## Inventory format

Define nodes in `hosts`:

```ini
[controlplane]
master1 ansible_host=192.168.1.205 ansible_user=root
master2 ansible_host=192.168.1.123 ansible_user=root

[worker]
worker1 ansible_host=192.168.1.124 ansible_user=root

[all:vars]
ansible_python_interpreter=/usr/bin/python3
```

- `[controlplane]`: First host initializes the cluster, additional hosts join as control plane nodes.
- `[worker]`: Hosts that join as worker nodes.
- `[all:vars]`: Variables shared across all inventory hosts.

---

## Supported platforms

| Operating system | Container runtime | Status |
| ---------------- | ----------------- | ------ |
| Ubuntu 22.04 / 24.04 | containerd, CRI-O | Supported |
| Fedora 38+ | containerd, CRI-O | Supported |
| RHEL 8 / 9 | containerd, CRI-O | Supported |
| Rocky Linux / AlmaLinux 8 / 9 | containerd, CRI-O | Supported |
