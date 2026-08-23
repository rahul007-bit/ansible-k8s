# Usage and configuration guide

This guide explains how to configure cluster settings and execute cluster playbooks.

## Table of contents

- [Setting up the inventory](#setting-up-the-inventory)
- [Playbook configuration variables](#playbook-configuration-variables)
  - [Automated prerequisites](#automated-prerequisites)
  - [Container runtime](#container-runtime)
  - [Kubernetes version](#kubernetes-version)
  - [CRI-O version](#cri-o-version)
  - [CNI plugin](#cni-plugin)
  - [CNI plugin binary version](#cni-plugin-binary-version)
  - [Pod network CIDR](#pod-network-cidr)
  - [Kube user](#kube-user)
  - [High availability settings](#high-availability-settings)
  - [OS upgrade](#os-upgrade)
  - [Firewall configuration](#firewall-configuration)
- [Running the playbooks](#running-the-playbooks)
  - [Check prerequisites](#check-prerequisites)
  - [Create a cluster](#create-a-cluster)
  - [Reset a cluster](#reset-a-cluster)
  - [Upgrade a cluster](#upgrade-a-cluster)
  - [Upgrade CRI-O](#upgrade-crio)
  - [Check mode (dry run)](#check-mode-dry-run)
- [Common scenarios](#common-scenarios)
- [Offline installation](#offline-installation)

---

## Setting up the inventory

Define cluster nodes in `hosts`:

```ini
[controlplane]
master1 ansible_host=192.168.1.205 ansible_user=root
master2 ansible_host=192.168.1.123 ansible_user=root

[worker]
worker1 ansible_host=192.168.1.124 ansible_user=root
worker2 ansible_host=192.168.1.125 ansible_user=root

[all:vars]
ansible_python_interpreter=/usr/bin/python3
```

- `ansible_host`: Target host IP address.
- `ansible_user`: SSH login username with root or sudo permissions.
- `ansible_python_interpreter`: Remote Python 3 interpreter path.

For high-availability control planes, use an odd number of nodes (minimum 3) to maintain etcd quorum.

---

## Playbook configuration variables

Main configuration settings live in `vars/cluster_config.yml`. Values can also be passed at runtime using `-e`.

### Automated prerequisites

```yaml
run_prerequisites: false
```

When set to `true`, `create_k8s.yml` runs pre-flight validation (CPU, RAM, disk, mounts, ports, and network reachability) before initiating installation.

### Container runtime

```yaml
runtime: crio  # Options: crio, containerd
```

Sets the container runtime:
- `containerd`: containerd with runc.
- `crio`: CRI-O container runtime.

To switch runtime on the command line:

```bash
ansible-playbook -i hosts playbooks/create_k8s.yml -e runtime=containerd
```

### Kubernetes version

```yaml
kube_version: "1.32"
```

Sets the Kubernetes package version for `kubeadm`, `kubelet`, and `kubectl`. Use format `1.32` or `1.32.2`.

### CRI-O version

```yaml
crio_version: "v1.32"
```

Used when `runtime: crio`. Sets the CRI-O package version (with `v` prefix).

### CNI plugin

```yaml
cni_plugin: calico    # Options: calico, flannel
calico_version: v3.26.0
flannel_version: v0.28.3
```

Selects the network plugin:
- `calico`: Network policies, BGP and VXLAN routing. Default subnet: `192.168.0.0/16`.
- `flannel`: Lightweight overlay networking. Default subnet: `10.244.0.0/16`.

### CNI plugin binary version

```yaml
cni_plugins_version: "v1.6.2"
```

Version of standard CNI plugins (`bridge`, `portmap`, `host-local`) extracted into `/opt/cni/bin`.

### Pod network CIDR

```yaml
pod_network_cidr: "{{ cni_default_cidrs[cni_plugin] }}"
```

Pod IP subnet. Ensure this subnet does not conflict with existing local networks.

```bash
ansible-playbook -i hosts playbooks/create_k8s.yml -e pod_network_cidr=10.100.0.0/16
```

### Kube user

```yaml
kube_user: "{{ ansible_user | default('ubuntu') }}"
```

User account that owns `~/.kube/config` on the control plane.

### High availability settings

```yaml
control_plane_endpoint: "{{ hostvars[groups['controlplane'][0]].ansible_host }}"
kubeconfig_on_all_cp: false
```

- `control_plane_endpoint`: Virtual IP, load balancer address, or first master IP used for API server traffic.
- `kubeconfig_on_all_cp`: When set to `true`, copies `~/.kube/config` to all control plane nodes.

### OS upgrade

```yaml
os_upgrade: false
```

When set to `true`, runs full distribution package upgrades before cluster configuration.

### Firewall configuration

```yaml
firewall_enabled: true
```

Configures `firewalld` (RHEL, CentOS, Fedora, Rocky) or `ufw` (Ubuntu, Debian) to open required Kubernetes and CNI ports. When Calico is used on RHEL distributions, the playbook also configures the `ipip` encapsulation protocol, adds Calico interfaces (`cali+`, `tunl0`, `vxlan.calico`) and `pod_network_cidr` to the `trusted` zone, and enables firewall masquerading. To manage firewall rules externally, set `firewall_enabled: false`.

### Pod CIDR collision validation

During cluster creation and pre-flight checks, Ansible verifies that `pod_network_cidr` does not overlap with any node's physical IP address. To override the Pod CIDR at runtime:

```bash
ansible-playbook -i hosts playbooks/create_k8s.yml -e pod_network_cidr=10.244.0.0/16
```

To bypass the safety check explicitly: `-e allow_cidr_collision=true`.

### Optional package removal (reset)

```yaml
remove_packages: false
```

When running `reset-k8s-cluster.yml`, setting `remove_packages: true` purges installed binaries and repository definitions.

---

## Running the Playbooks

### Check prerequisites

You can manually run the pre-flight checks without triggering an installation:

```bash
ansible-playbook -i hosts playbooks/prerequisites.yml
```

### Create a cluster

```bash
# With defaults (containerd + Calico v3.29.3)
ansible-playbook -i hosts playbooks/create_k8s.yml

# With custom settings
ansible-playbook -i hosts playbooks/create_k8s.yml \
  -e runtime=containerd \
  -e cni_plugin=flannel \
  -e flannel_version=v0.26.0
```

## Running the playbooks

### Check prerequisites

Run pre-flight checks independently:

```bash
ansible-playbook -i hosts playbooks/prerequisites.yml
```

### Create a cluster

```bash
ansible-playbook -i hosts playbooks/create_k8s.yml
```

Custom runtime and CNI options can be passed directly:

```bash
ansible-playbook -i hosts playbooks/create_k8s.yml \
  -e runtime=containerd \
  -e cni_plugin=flannel \
  -e flannel_version=v0.28.3
```

The playbook skips initialization on nodes that are already members of the cluster.

### Reset a cluster

Tears down Kubernetes services, network bridges, configuration files, and leftover container state:

```bash
# Interactive confirmation prompt
ansible-playbook -i hosts playbooks/reset-k8s-cluster.yml

# Non-interactive confirmation
ansible-playbook -i hosts playbooks/reset-k8s-cluster.yml -e force_reset=yes
```

### Upgrade a cluster

Kubernetes supports upgrading only one minor version at a time (e.g., 1.30 to 1.31, then 1.31 to 1.32). The playbook blocks multi-minor version jumps.

Upgrades run sequentially across control plane nodes first, then workers (`serial: 1`), draining each node before package updates and uncordoning after health checks pass:

```bash
ansible-playbook -i hosts playbooks/upgrade_k8s.yml -e target_version=1.31
```

Safety rules during upgrade:
- Saves an etcd snapshot to `/var/backups/etcd-snapshot-<version>-<timestamp>.db` before changing control plane components.
- Waits for each node to report `Ready` before proceeding to the next node.
- If `kubeadm upgrade apply` fails on the first control plane node, the playbook stops immediately and provides the backup path for manual recovery.

### Upgrade CRI-O

CRI-O is upgraded separately from Kubernetes binaries with `upgrade_crio.yml`:

```bash
ansible-playbook -i hosts playbooks/upgrade_crio.yml -e crio_version=v1.32
```

The playbook stops kubelet and running containers before updating CRI-O packages, avoiding hung reconciliations on control-plane nodes.

### Check mode (dry run)

```bash
ansible-playbook -i hosts playbooks/create_k8s.yml --check
```

### Limit target hosts

```bash
ansible-playbook -i hosts playbooks/create_k8s.yml --limit worker1
```

---

## Common scenarios

### Scenario 1: New cluster with defaults

```bash
ansible-playbook -i hosts playbooks/create_k8s.yml
```

Deploys CRI-O with Calico and pod CIDR `192.168.0.0/16`.

### Scenario 2: Teardown and clean redeploy

```bash
ansible-playbook -i hosts playbooks/reset-k8s-cluster.yml -e force_reset=yes
ansible-playbook -i hosts playbooks/create_k8s.yml
```

### Scenario 3: Add a new worker node

1. Add the worker entry to `hosts`:

   ```ini
   [worker]
   worker1 ansible_host=192.168.1.124 ansible_user=root
   worker2 ansible_host=192.168.1.125 ansible_user=root  # new node
   ```

2. Run cluster creation limited to the new worker:

   ```bash
   ansible-playbook -i hosts playbooks/create_k8s.yml --limit worker2
   ```

---

## Offline installation

The playbooks support air-gapped deployments using pre-downloaded package archives and container images.

### Directory structure

When using `offline_pkg_type: "dir"`, organise files into two subdirectories:
- `rpms/`: RPM or DEB packages to install.
- `images/`: `.tar` archives of container images imported directly into the container runtime.

### Configuration options

In `vars/cluster_config.yml`:

```yaml
offline_install: true
offline_pkg_type: "dir"                                       # "dir" or "zip"
offline_pkg_source: "remote"                                  # "controller" or "remote"
offline_pkg_path: "/root/k8s_packages"                        # Source directory or zip path
remote_pkg_dir: "/root/k8s_packages/rpms"                     # Package directory on target nodes
remote_images_dir: "/root/k8s_packages/images"                # Image archive directory on target nodes
```

Offline package installations execute `rpm -Uvh` or `dpkg -i` directly, avoiding package manager network lookups on isolated systems.

