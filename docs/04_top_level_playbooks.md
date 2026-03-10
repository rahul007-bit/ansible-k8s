# Playbook Internals: Step-by-Step Technical Execution

This document provides a technical breakdown of exactly what each major playbook does under the hood. It is intended for administrators, operators, and developers who need to understand the underlying OS and Kubernetes commands executed by Ansible.

## Table of Contents

- [1. `create_k8s.yml` (Cluster Creation)](#1-create_k8syml-cluster-creation)
- [2. `upgrade_k8s.yml` (Cluster Upgrade)](#2-upgrade_k8syml-cluster-upgrade)
- [3. `reset-k8s-cluster.yml` (Cluster Destruction)](#3-reset-k8s-clusteryml-cluster-destruction)

---

## 1. `create_k8s.yml` (Cluster Creation)

This playbook provisions a complete Kubernetes cluster from scratch using `kubeadm`.

### Phase 1: Basic Node Setup (`basic_setup/system_settings.yml`)
>
> **See [basic_setup/README.md](../basic_setup/README.md) for a complete line-by-line breakdown.**
This phase installs required kernel modules (`overlay`, `br_netfilter`), routing `sysctl` rules, and completely disables OS swap.

### Phase 2: Installing Core Components (`tasks/install_kubernetes.yml`)
>
> **See [tasks/README.md](../tasks/README.md) for a complete line-by-line breakdown.**
This phase configures OS package repositories and natively installs `kubeadm`, `kubelet`, and `kubectl` using strict version pinning to prevent upgrade drift.

### Phase 3: Setting Up Container Runtime

Based on the `runtime` chosen (containerd or crio), the respective role is included:
> **For containerd: See [containerd/README.md](../containerd/README.md)**
> **For CRI-O: See [crio/README.md](../crio/README.md)**
This phase downloads the runtime binaries, applies system configurations, and enforces the `systemd` cgroup driver requirement.

### Phase 4: Setting Up Native CNI Plugins

Because some runtimes (like pristine CRI-O + Flannel) do not automatically populate standard CNI binaries:

1. The playbook checks if `/opt/cni/bin/bridge` exists.
2. If absent, it directly downloads and extracts the `containernetworking/plugins` release bundle (using `cni_plugins_version`) into `/opt/cni/bin`.

### Phase 5: Cluster Bootstrapping (Control Plane 1)

1. **Idempotency Check:** Checks if `/etc/kubernetes/admin.conf` already exists. If it does, the initialization is skipped.
2. **Kubeadm Init:** Executes `kubeadm init` with the calculated `--pod-network-cidr`, `--control-plane-endpoint` (first master IP), and `--upload-certs`.
3. **Kubeconfig Access:** Creates `~/.kube/config` and copies `admin.conf` so the specified `kube_user` has `kubectl` administrative access.

### Phase 6: Networking (CNI)

1. **Apply Manifests:** Executes `kubectl apply -f` for your chosen CNI (Calico or Flannel) directly against the newly initialized API server.
2. Waits until the `kube-dns`/`coredns` deployment transitions to `Running`, proving the cluster control plane is healthy and network routing is established.

### Phase 7: High Availability (Joining Masters)

*(Only executes if there are multiple nodes under `[controlplane]` in the inventory)*

1. **Idempotency Check:** Checks if `/etc/kubernetes/kubelet.conf` already exists. If it does, the join specialized for this node is skipped.
2. **Upload Certs:** Uploads certificate keys to the first master and generates a fresh join command.
3. **Node Join:** Additional control plane nodes execute `kubeadm join --control-plane --certificate-key ...`.
4. Distributes `admin.conf` to additional control plane nodes (if `kubeconfig_on_all_cp` is true).

### Phase 8: Joining Workers

*(Only executes for nodes under `[worker]` in the inventory)*

1. **Idempotency Check:** Checks if `/etc/kubernetes/kubelet.conf` already exists. If it does, the join specialized for this node is skipped.
2. **Join Tokens:** Generates a standard `--discovery-token-ca-cert-hash` join string.
3. **Node Join:** Workers and additional control planes execute `kubeadm join` to securely attach themselves to the cluster.

---

## 2. `upgrade_k8s.yml` (Cluster Upgrade)

This playbook automates zero-downtime rolling upgrades following official `kubeadm` recommendations. Operates sequentially on each node (`serial: 1`).

### Pre-Flight Safety Checks

1. Investigates existing locally installed `kubelet` versions.
2. Cross-references the provided `-e target_version`.
3. **Safety Guarantee:** If the requested upgrade jumps more than **one minor version** (e.g., from 1.28 to 1.30), the playbook immediately fails to enforce Kubernetes upgrade policies.

### Node-by-Node Rolling Upgrade Execution

For each node in the cluster, one at a time:

1. **Repo Upgrade:** Replaces the package manager repositories with the ones for the target version.
2. **Upgrade Kubeadm Tool:** Upgrades the `kubeadm` package (also allowing downgrades or held-package changes to bypass system drift).
3. **Kubeadm Upgrade Phase:**
   - On the *first* master: Executes `kubeadm upgrade apply <target-version>`. This upgrades the cluster configuration, etcd, API Server, Scheduler, and Controller Manager via static manifests.
   - On subsequent masters and workers: Executes `kubeadm upgrade node`.
4. **Zero-Downtime Node Draining:** Uses `kubectl drain <ansible_hostname> --ignore-daemonsets --delete-emptydir-data --force` to smoothly evict running pods over to other healthy nodes natively mapping the OS hostname to the Kubernetes node name.
5. **Upgrade Kubelet & Kubectl:** OS package update for `kubelet` and `kubectl` to exactly match the target.
6. **Restart OS Services:** `systemctl daemon-reload` and `systemctl restart kubelet`.
7. **Uncordon Node:** Executes `kubectl uncordon <ansible_hostname>` to mark the node as schedulable, returning it seamlessly to the cluster pool.

---

## 3. `reset-k8s-cluster.yml` (Cluster Destruction)

This playbook tears down the environment safely. It is highly destructive.

1. **Confirmation Check:** Halts execution with an interactive pause module, forcing the user to explicitly type `yes` to authorize destruction *(can be bypassed automatically by appending `-e force_reset=yes`)*.
2. **Kubeadm Reset:** Executes `kubeadm reset -f` to systematically unconfigure static pods, delete local etcd member data, and reset iptables rules.
3. **Clean Configurations:** Hard deletes the master's `/etc/kubernetes/` directories, `/var/lib/kubelet/config.yaml`, and the user's `~/.kube/config`.
4. **Wipe CNI State:** Removes interface configuration files located in `/etc/cni/net.d/` (`10-calico.conflist`, `10-flannel.conflist`).
5. **Flush Container Runtimes:** Executes `crictl rm --all`, `crictl rmp --all`, and `crictl rmi --all` to permanently delete all stopped containers, active pods, and cached images left over by Kubernetes components.
6. **Optional Package Purge:** If `remove_packages` is set to `true`, the playbook also:
   - Uninstalls `kubelet`, `kubeadm`, `kubectl`, and `cri-o` (including configuration purging on Ubuntu).
   - Deletes all package manager repository files and GPG keyrings.
   - Wipes all leftover runtime data directories (`/var/lib/containers`, `/var/lib/cni`, etc.).
