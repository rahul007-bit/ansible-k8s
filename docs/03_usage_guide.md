# Usage & Configuration Guide

Once your prerequisites are in place (see `02_prerequisites.md`), you're ready to configure and run the playbook. This doc explains what you can tweak and how each setting affects the cluster.

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

All the main settings live in `create_k8s.yml` under the `vars:` section. You can either edit them directly in the file, or override them at runtime using `-e` on the command line (no file changes needed).

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
# Change runtime: containerd → runtime: crio in create_k8s.yml

# Option B: Override at runtime (no file changes)
ansible-playbook -i hosts create_k8s.yml -e runtime=crio
```

### Kubernetes Version

```yaml
kube_version: "1.32"  # e.g., 1.32, 1.31, 1.30
```

This controls which version of `kubeadm`, `kubelet`, and `kubectl` gets installed. The version determines which `pkgs.k8s.io` repository is used.

```bash
# Option A: Edit the file (recommended)
# Change kube_version: "1.32" → kube_version: "1.30" in create_k8s.yml

# Option B: Override at runtime
ansible-playbook -i hosts create_k8s.yml -e kube_version=1.30
```

> **Note**: Use the format `1.32` (no `v` prefix). Check [Kubernetes releases](https://github.com/kubernetes/kubernetes/releases) for available versions.

### CRI-O Version

```yaml
crio_version: "v1.31"  # e.g., v1.31, v1.30
```

Only used when `runtime: crio`. Controls which CRI-O package version gets installed.

```bash
# Option A: Edit the file (recommended)
# Change crio_version: "v1.31" → crio_version: "v1.30" in create_k8s.yml

# Option B: Override at runtime
ansible-playbook -i hosts create_k8s.yml -e runtime=crio -e crio_version=v1.30
```

> **Note**: Use the format `v1.31` (with `v` prefix). Check [CRI-O releases](https://github.com/cri-o/cri-o/releases) for available versions.

### CNI Plugin (Networking)

```yaml
cni_plugin: calico    # Options: calico, flannel
cni_version: v3.29.3  # Version tag from the CNI project's releases
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
# Change cni_plugin: calico → cni_plugin: flannel in create_k8s.yml
# Change cni_version: v3.29.3 → cni_version: v0.26.4

# Option B: Override at runtime (no file changes)
ansible-playbook -i hosts create_k8s.yml \
  -e cni_plugin=flannel \
  -e cni_version=v0.26.4
```

> **Important**: The `cni_version` must be a valid release tag from the CNI project. Calico versions look like `v3.29.3` (check [Calico releases](https://github.com/projectcalico/calico/releases)). Flannel versions look like `v0.26.4` (check [Flannel releases](https://github.com/flannel-io/flannel/releases)).

### CNI Plugins Binaries Version

```yaml
cni_plugins_version: "v1.6.2"  # e.g., v1.6.2, v1.5.1
```

This controls the exact version of the standard CNI plugin binaries (like `bridge`, `portmap`, `host-local`, etc.) downloaded straight from [containernetworking/plugins](https://github.com/containernetworking/plugins) into `/opt/cni/bin`. This fixes issues with CRI-O + Flannel where binaries aren't populated properly by the package manager.

```bash
# Option A: Edit the file (recommended)
# Change cni_plugins_version: "v1.6.2" → cni_plugins_version: "v1.9.0" in create_k8s.yml

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
# Change kubeconfig_on_all_cp: false → kubeconfig_on_all_cp: true in create_k8s.yml

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
  -e cni_version=v0.26.4
```

### Reset a cluster

This wipes everything and gives you a fresh start. Run this when you want to tear down and rebuild:

```bash
ansible-playbook -i hosts reset-k8s-cluster.yml
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

Decide which CNI you want **before** creating the cluster. Edit `cni_plugin` and `cni_version` in `create_k8s.yml`, then run:

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
| Create with Flannel | `ansible-playbook -i hosts create_k8s.yml -e cni_plugin=flannel -e cni_version=v0.26.4` |
| Create with CRI-O | `ansible-playbook -i hosts create_k8s.yml -e runtime=crio` |
| Kubeconfig on all masters | `ansible-playbook -i hosts create_k8s.yml -e kubeconfig_on_all_cp=true` |
| With OS upgrade | `ansible-playbook -i hosts create_k8s.yml -e os_upgrade=true` |
| Reset cluster | `ansible-playbook -i hosts reset-k8s-cluster.yml` |
| Dry run | `ansible-playbook -i hosts create_k8s.yml --check` |
| Verbose mode | `ansible-playbook -i hosts create_k8s.yml -vvv` |
| Run on one host | `ansible-playbook -i hosts create_k8s.yml --limit host2` |
