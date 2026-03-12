# Usage & Configuration Guide

Once your prerequisites are in place (see `02_prerequisites.md`), you're ready to configure and run the playbook. This doc explains what you can tweak and how each setting affects the cluster.

## Table of Contents

- [Setting Up the Inventory](#setting-up-the-inventory)
  - [What each part means](#what-each-part-means)
  - [Adding more workers](#adding-more-workers)
  - [Multiple control plane nodes (HA)](#multiple-control-plane-nodes-ha)
- [Tweaking the Playbook Variables](#tweaking-the-playbook-variables)
  - [Container Runtime](#container-runtime)
  - [Kubernetes Version](#kubernetes-version)
  - [CRI-O Version](#cri-o-version)
  - [CNI Plugin (Networking)](#cni-plugin-networking)
  - [CNI Plugins Binaries Version](#cni-plugins-binaries-version)
  - [Pod Network CIDR](#pod-network-cidr)
  - [Kube User](#kube-user)
  - [HA Settings](#ha-settings)
  - [OS Upgrade](#os-upgrade)
  - [Firewall Configuration](#firewall-configuration)
- [Running the Playbooks](#running-the-playbooks)
  - [Create a cluster](#create-a-cluster)
  - [Reset a cluster](#reset-a-cluster)
  - [Upgrade a cluster](#upgrade-a-cluster)
  - [Dry run (check mode)](#dry-run-check-mode)
  - [See detailed output](#see-detailed-output)
  - [Run on specific hosts only](#run-on-specific-hosts-only)
- [Common Scenarios](#common-scenarios)
  - [Scenario 1: Fresh cluster with defaults](#scenario-1-fresh-cluster-with-defaults)
  - [Scenario 2: Rebuild from scratch](#scenario-2-rebuild-from-scratch)
  - [Scenario 3: Use Flannel instead of Calico](#scenario-3-use-flannel-instead-of-calico)
  - [Scenario 4: Add a new worker to an existing cluster](#scenario-4-add-a-new-worker-to-an-existing-cluster)
  - [Scenario 5: HA cluster with multiple masters](#scenario-5-ha-cluster-with-multiple-masters)
- [Quick Reference](#quick-reference)

---

## Setting Up the Inventory

The `hosts` file is where you define your cluster — which machines are control plane nodes and which are workers.

```ini
[controlplane]
host3 ansible_host=192.168.1.205 ansible_user=rahul

[worker]
host2 ansible_host=192.168.1.123 ansible_user=rahul

[all:vars]
ansible_python_interpreter=/usr/bin/python3
```

### What each part means

- **`ansible_host`** — the IP address of the machine. Change this to match your actual server IPs.
- **`ansible_user`** — the SSH user Ansible will log in as. This user needs sudo access on the remote machine.
- **`ansible_python_interpreter`** — Path to Python on the remote machines. Run `which python3` on your servers to find the correct path.

### Adding more workers

Just add more lines under `[worker]`:

```ini
[worker]
worker1 ansible_host=192.168.1.123 ansible_user=rahul
worker2 ansible_host=192.168.1.124 ansible_user=rahul
worker3 ansible_host=192.168.1.125 ansible_user=rahul
```

### Multiple control plane nodes (HA)

Add more nodes to `[controlplane]` for a multi-master setup. The first node initializes the cluster, additional nodes join as control plane members:

```ini
[controlplane]
master1 ansible_host=192.168.1.205 ansible_user=rahul
master2 ansible_host=192.168.1.123 ansible_user=rahul

[worker]
worker1 ansible_host=192.168.1.124 ansible_user=rahul
```

> **Note**: For production HA you need at least 3 control plane nodes (etcd quorum requires a majority). 2 masters is fine for testing but won't give you fault tolerance. A load balancer in front of the API servers is also recommended for production.

---

## Tweaking the Playbook Variables

All the main settings live in `vars/cluster_config.yml`. You can either edit them directly in that file, or override them at runtime using `-e` on the command line (overrides the file).

### Container Runtime

```yaml
runtime: containerd  # Options: containerd, crio
```

This controls which container runtime gets installed on all your nodes.

| Value | What gets installed | When to use |
| ----------- | ------------------- | ----------- |
| `containerd` | containerd + runc | Default, recommended. Most widely used with Kubernetes. |
| `crio` | CRI-O | If your team prefers CRI-O, or you're following OpenShift patterns. |

To switch to CRI-O:

```bash
# Option A: Edit the file (recommended)
# Change runtime: containerd → runtime: crio in vars/cluster_config.yml

# Option B: Override at runtime (no file changes)
ansible-playbook -i hosts create_k8s.yml -e runtime=crio
```

### Kubernetes Version

```yaml
kube_version: "1.35"  # e.g., 1.35, 1.34, 1.33
```

This controls which version of `kubeadm`, `kubelet`, and `kubectl` gets installed. The version determines which `pkgs.k8s.io` repository is used.

```bash
# Option A: Edit the file (recommended)
# Change kube_version: "1.32" → kube_version: "1.30" in vars/cluster_config.yml

# Option B: Override at runtime
ansible-playbook -i hosts create_k8s.yml -e kube_version=1.30
```

> **Note**: Use the format `1.32` (no `v` prefix). Check [Kubernetes releases](https://github.com/kubernetes/kubernetes/releases) for available versions.

### CRI-O Version

```yaml
crio_version: "v1.35"  # e.g., v1.35, v1.34
```

Only used when `runtime: crio`. Controls which CRI-O package version gets installed.

```bash
# Option A: Edit the file (recommended)
# Change crio_version: "v1.31" → crio_version: "v1.30" in vars/cluster_config.yml

# Option B: Override at runtime
ansible-playbook -i hosts create_k8s.yml -e runtime=crio -e crio_version=v1.34
```

> **Note**: Use the format `v1.35` (with `v` prefix). Check [CRI-O releases](https://github.com/cri-o/cri-o/releases) for available versions.

### CNI Plugin (Networking)

```yaml
cni_plugin: flannel    # Options: calico, flannel
calico_version: v3.26.0  # Version tag for Calico releases
flannel_version: v0.26.0 # Version tag for Flannel releases
```

The CNI plugin handles networking between your pods. The playbook supports two popular options:

| Plugin | Default CIDR | Best for |
| ------- | ------------ | -------- |
| Calico | `192.168.0.0/16` | Production clusters, network policies, BGP routing |
| Flannel | `10.244.0.0/16` | Simple setups, learning, smaller clusters |

The pod CIDR is auto-set based on your CNI choice. You don't need to touch it unless you have a specific network requirement.

To switch to Flannel:

```bash
# Option A: Edit the file (recommended)
# Change cni_plugin: calico → cni_plugin: flannel in vars/cluster_config.yml
# Make sure flannel_version is set to a valid release (e.g. v0.26.0)

# Option B: Override at runtime (no file changes)
ansible-playbook -i hosts create_k8s.yml \
  -e cni_plugin=flannel \
  -e flannel_version=v0.26.0
```

> **Important**: The `calico_version` or `flannel_version` must be a valid release tag from the respective project. Calico versions look like `v3.26.0` (check [Calico releases](https://github.com/projectcalico/calico/releases)). Flannel versions look like `v0.26.0` (check [Flannel releases](https://github.com/flannel-io/flannel/releases)).

### CNI Plugins Binaries Version

```yaml
cni_plugins_version: "v1.6.2"  # e.g., v1.6.2, v1.5.1
```

This controls the exact version of the standard CNI plugin binaries (like `bridge`, `portmap`, `host-local`, etc.) downloaded straight from [containernetworking/plugins](https://github.com/containernetworking/plugins) into `/opt/cni/bin`. This fixes issues with CRI-O + Flannel where binaries aren't populated properly by the package manager.

```bash
# Option A: Edit the file (recommended)
# Change cni_plugins_version: "v1.6.2" → cni_plugins_version: "v1.9.0" in vars/cluster_config.yml

# Option B: Override at runtime
ansible-playbook -i hosts create_k8s.yml -e cni_plugins_version=v1.9.0
```

### Pod Network CIDR

```yaml
pod_network_cidr: "{{ cni_default_cidrs[cni_plugin] }}"
```

This is the IP range used for pod-to-pod communication. It's auto-set based on the CNI plugin, but you can override it if your network has specific requirements:

```bash
ansible-playbook -i hosts create_k8s.yml -e pod_network_cidr=10.100.0.0/16
```

> **Heads up**: Make sure the pod CIDR doesn't overlap with your actual host network. For example, if your servers are on `192.168.1.x`, the default Calico CIDR `192.168.0.0/16` technically overlaps (both are in the `192.168.x.x` range). In practice, Calico handles this fine with its routing, but if you run into issues, pick a non-overlapping range like `10.244.0.0/16`.

### Kube User

```yaml
kube_user: "{{ ansible_user | default('ubuntu') }}"
```

This is the user who will own the `~/.kube/config` file on the control plane. It automatically uses the same user you're connecting with (`ansible_user` from the inventory). You rarely need to change this.

### HA Settings

```yaml
control_plane_endpoint: "{{ hostvars[groups['controlplane'][0]].ansible_host }}"  # auto-set
kubeconfig_on_all_cp: false
```

- **`control_plane_endpoint`** — The IP or hostname that all nodes use to reach the API server. Auto-set to the first control plane node's IP. Override this if you have a load balancer.
- **`kubeconfig_on_all_cp`** — By default, only the first master gets `~/.kube/config`. Set to `true` to copy it to all control plane nodes:

```bash
# Option A: Edit the file (recommended)
# Change kubeconfig_on_all_cp: false → kubeconfig_on_all_cp: true in vars/cluster_config.yml

# Option B: Override at runtime
ansible-playbook -i hosts create_k8s.yml -e kubeconfig_on_all_cp=true
```

### OS Upgrade

```yaml
os_upgrade: false  # Set to true to run full OS upgrade
```

The playbook always updates the package cache (`apt update`), but skips the full package upgrade (`apt upgrade`) by default. Enable it if you want to upgrade all packages before setting up Kubernetes:

```bash
ansible-playbook -i hosts create_k8s.yml -e os_upgrade=true
```

### Firewall Configuration

```yaml
firewall_enabled: true
```

The playbook includes automated firewall configuration for `ufw` (Ubuntu/Debian) and `firewalld` (RHEL/Fedora/CentOS). By default, it opens all required Kubernetes and CNI ports.

| Setting | Default | Description |
| ------- | ------- | ----------- |
| `firewall_enabled` | `true` | Whether to automatically manage firewall rules |
| `firewall_allowed_ports_common` | (Port list) | Core K8s ports (API, etcd, etc.) |
| `firewall_allowed_ports_cni` | (Port list) | CNI-specific ports (VXLAN, BGP) |

To disable automated firewall management:

```bash
ansible-playbook -i hosts create_k8s.yml -e firewall_enabled=false
```

> [!TIP]
> If you have an external firewall or corporate security policy, you might want to disable this and configure your rules manually based on the ports listed in `02_prerequisites.md`.

### Optional Package Removal (Reset)

```yaml
remove_packages: false  # Set to true to purge Kubernetes and CRI-O packages
```

By default, the `reset-k8s-cluster.yml` playbook resets cluster configuration and files but leaves the base packages (kubeadm, kubelet, kubectl, cri-o) installed. Enable this if you want a completely clean slate including repository removal.

```bash
ansible-playbook -i hosts reset-k8s-cluster.yml -e remove_packages=true
```

---

## Running the Playbooks

### Create a cluster

```bash
# With defaults (containerd + Calico v3.29.3)
ansible-playbook -i hosts create_k8s.yml

# With custom settings
ansible-playbook -i hosts create_k8s.yml \
  -e runtime=containerd \
  -e cni_plugin=flannel \
  -e flannel_version=v0.26.0
```

> **Note**: The creation playbook is **idempotent**. If a node is already part of the cluster or the control plane is already initialized, it will safely skip those steps. This makes it safe to run multiple times or to add new nodes to an existing cluster.

### Reset a cluster

This wipes everything and gives you a fresh start. Run this when you want to tear down and rebuild.

> **Caution**: This deletes all data and wipes containers. You will be prompted to confirm `yes` before it proceeds. To bypass the prompt for automation, append `-e force_reset=yes`.

```bash
# Interactive reset
ansible-playbook -i hosts reset-k8s-cluster.yml

# Automated reset (bypasses prompt)
ansible-playbook -i hosts reset-k8s-cluster.yml -e force_reset=yes
```

### Upgrade a cluster

Use `upgrade_k8s.yml` to perform automated, zero-downtime rolling upgrades of your Kubernetes cluster.

> **CRITICAL RULE**: Kubernetes only supports upgrading **one minor version at a time**. You cannot jump directly from `v1.28` to `v1.32`. You must upgrade sequentially (e.g., `1.28` → `1.29` → `1.30`). The playbook will automatically abort if you try to skip a version.

The playbook works node-by-node (`serial: 1`) and safely evicts pods using `kubectl drain` before upgrading packages, ensuring your applications experience zero downtime.

```bash
# Example: Upgrading from v1.34.x to v1.35.x
ansible-playbook -i hosts upgrade_k8s.yml -e target_version=1.35
```

### Dry run (check mode)

See what the playbook *would* do without actually making any changes:

```bash
ansible-playbook -i hosts create_k8s.yml --check
```

### See detailed output

If something goes wrong, crank up the verbosity to see exactly what's happening:

```bash
# More detail
ansible-playbook -i hosts create_k8s.yml -v

# Even more detail
ansible-playbook -i hosts create_k8s.yml -vv

# Maximum detail (shows SSH commands, full module args, etc.)
ansible-playbook -i hosts create_k8s.yml -vvv
```

### Run on specific hosts only

If you only want to run the playbook on certain hosts (e.g., just the workers):

```bash
ansible-playbook -i hosts create_k8s.yml --limit worker
ansible-playbook -i hosts create_k8s.yml --limit host2
```

---

## Common Scenarios

### Scenario 1: Fresh cluster with defaults

```bash
ansible-playbook -i hosts create_k8s.yml
```

This gives you: containerd + Calico v3.29.3 + pod CIDR `192.168.0.0/16`

### Scenario 2: Rebuild from scratch

```bash
# Tear down
ansible-playbook -i hosts reset-k8s-cluster.yml

# Build again
ansible-playbook -i hosts create_k8s.yml
```

### Scenario 3: Use Flannel instead of Calico

Decide which CNI you want **before** creating the cluster. Edit `cni_plugin` and `cni_version` in `vars/cluster_config.yml`, then run:

```bash
ansible-playbook -i hosts create_k8s.yml
```

> **Note**: Swapping CNI plugins on a running cluster is not supported by this playbook. If you need to change CNI, reset the cluster first and rebuild.

### Scenario 4: Add a new worker to an existing cluster

1. Add the new worker to the `hosts` file:

   ```ini
   [worker]
   host2 ansible_host=192.168.1.123 ansible_user=rahul
   host4 ansible_host=192.168.1.126 ansible_user=rahul  # new worker
   ```

2. Run the playbook targeting only the new host:

   ```bash
   ansible-playbook -i hosts create_k8s.yml --limit host4
   ```

> **Pro Tip**: Because the playbook is idempotent, you can also just run the full `ansible-playbook -i hosts create_k8s.yml`. It will detect that your existing nodes are already configured and only perform the setup on the new `host4`.

### Scenario 5: HA cluster with multiple masters

1. Add multiple nodes to `[controlplane]` in the `hosts` file:

   ```ini
   [controlplane]
   master1 ansible_host=192.168.1.205 ansible_user=rahul
   master2 ansible_host=192.168.1.123 ansible_user=rahul

   [worker]
   # add workers here if needed
   ```

2. Run the playbook:

   ```bash
   ansible-playbook -i hosts create_k8s.yml
   ```

3. Verify both nodes show as `control-plane`:

   ```bash
   ssh rahul@192.168.1.205 "kubectl get nodes"
   ```

---

## Quick Reference

| What you want | Command |
| ------------- | ------- |
| Create cluster (defaults) | `ansible-playbook -i hosts create_k8s.yml` |
| Create with Flannel | `ansible-playbook -i hosts create_k8s.yml -e cni_plugin=flannel -e flannel_version=v0.26.4` |
| Create with CRI-O | `ansible-playbook -i hosts create_k8s.yml -e runtime=crio` |
| Kubeconfig on all masters | `ansible-playbook -i hosts create_k8s.yml -e kubeconfig_on_all_cp=true` |
| With OS upgrade | `ansible-playbook -i hosts create_k8s.yml -e os_upgrade=true` |
| Reset cluster | `ansible-playbook -i hosts reset-k8s-cluster.yml` |
| Dry run | `ansible-playbook -i hosts create_k8s.yml --check` |
| Verbose mode | `ansible-playbook -i hosts create_k8s.yml -vvv` |
| Run on one host | `ansible-playbook -i hosts create_k8s.yml --limit host2` |
| Upgrade cluster | `ansible-playbook -i hosts upgrade_k8s.yml -e target_version=1.31` |

## Offline Installation

The playbook supports installing Kubernetes and CRI-O using pre-downloaded packages (RPM/DEB). This is useful for environments with restricted or no internet access.

### Configuration

All offline settings are in `vars/cluster_config.yml`:

```yaml
offline_install: true
offline_pkg_type: "zip"               # Options: "zip" or "dir"
offline_pkg_source: "controller"      # Options: "controller" (transfer from host) or "remote" (already on server)
offline_pkg_path: "k8s_rpm.zip"       # Path to the zip file or directory
remote_pkg_dir: "/tmp/k8s_packages"  # Where packages will be stored/extracted on remote nodes
```

### Scenarios

#### Scenario 1: Upload and Install (Zip)

If you have a zip file (like `k8s_rpm.zip`) on your local machine:

1. Set `offline_install: true` in `vars/cluster_config.yml`.
2. Set `offline_pkg_source: "controller"`.
3. Set `offline_pkg_type: "zip"`.
4. Run the playbook: `ansible-playbook -i hosts create_k8s.yml`

#### Scenario 2: Install from pre-uploaded Zip on Remote

If the zip file is already located at `/opt/k8s_rpm.zip` on all remote nodes:

1. Set `offline_install: true`.
2. Set `offline_pkg_source: "remote"`.
3. Set `offline_pkg_path: "/opt/k8s_rpm.zip"`.
4. Run the playbook.

#### Scenario 3: Install from pre-extracted Directory on Remote

If packages are already extracted to `/opt/k8s_repo` on all remote nodes:

1. Set `offline_install: true`.
2. Set `offline_pkg_source: "remote"`.
3. Set `offline_pkg_type: "dir"`.
4. Set `remote_pkg_dir: "/opt/k8s_repo"`.
5. Run the playbook.
