# Playbook Internals: Step-by-Step Technical Execution

This document provides a technical breakdown of exactly what each major playbook does under the hood. It is intended for administrators, operators, and developers who need to understand the underlying OS and Kubernetes commands executed by Ansible.

## Table of Contents

- [1. `prerequisites.yml` (Pre-flight Checks)](#1-prerequisitesyml-pre-flight-checks)
- [2. `create_k8s.yml` (Cluster Creation)](#2-create_k8syml-cluster-creation)
- [3. `upgrade_k8s.yml` (Cluster Upgrade)](#3-upgrade_k8syml-cluster-upgrade)
- [4. `upgrade_crio.yml` (CRI-O Upgrade)](#4-upgrade_crioyml-cri-o-upgrade)
- [5. `reset-k8s-cluster.yml` (Cluster Destruction)](#5-reset-k8s-clusteryml-cluster-destruction)

---

## 1. `prerequisites.yml` (Pre-flight Checks)

This playbook runs thorough checks on the system resources, external mounts, URL whitelists, and network connectivity before installing Kubernetes.

### Execution Phases

1. **Resource & Mount Assessment:** Asserts that `ansible_processor_vcpus`, `ansible_memtotal_mb`, and `ansible_mounts` match the strict constraints defined in `vars/cluster_config.yml`, either by exact hostname or by group name.
2. **Whitelisted URLs Reachability:** Uses the `ansible.builtin.uri` module to check if external endpoints like OCI registries can be reached successfully (HTTP 200, 401, or 403 are accepted).
3. **Port Availability (In Use):** Uses `ss -tulnp` to verify that essential ports (like `6443`, `10250`, etc.) aren't already being held by a conflicting daemon.
4. **Network Mesh Connectivity:** Injects a lightweight `port_listener.py` script to temporarily bind to required Kubernetes TCP ports, and leverages the Ansible `wait_for` module delegated dynamically across all nodes to perform an N-to-N connectivity test, validating internal firewall and routing configurations.

---

## 2. `create_k8s.yml` (Cluster Creation)

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

## 3. `upgrade_k8s.yml` (Cluster Upgrade)

This playbook automates zero-downtime rolling upgrades following official `kubeadm` recommendations. It is composed of two ordered plays — **controlplane group first, then worker group** — so upgrade order never depends on how nodes are listed in the `hosts` file. Each play operates sequentially on its nodes (`serial: 1`) and is itself a thin orchestrator that `include_tasks`s the following files under `tasks/`:

| Task file | Purpose |
|---|---|
| `tasks/upgrade_version_check.yml` | Control-plane only: checks current vs. `target_version`, fails if the jump is more than one minor version. |
| `tasks/upgrade_etcd_backup.yml` | Control-plane only: `etcdctl snapshot save` before anything else changes — a manual recovery point, never auto-restored. |
| `tasks/offline_package_prep.yml` / `tasks/upgrade_offline_preflight.yml` | Only when `offline_install: true` (see below). |
| `tasks/upgrade_kubeadm.yml` | Repo/GPG setup (online) or local install (offline), upgrades `kubeadm` to `target_version`, asserts the installed version matches. |
| `tasks/offline_image_load.yml` | Only when `offline_install: true`: pre-loads target-version container images into Podman/CRI-O storage before `kubeadm upgrade apply`/`node` runs. |
| `tasks/upgrade_drain.yml` | `kubectl drain` the current node (delegated to the first control-plane node). |
| `tasks/upgrade_control_plane_apply.yml` (controlplane play) | `kubeadm upgrade apply` on the first control-plane node, `kubeadm upgrade node` on the rest. See **Failure Handling** below. |
| `tasks/upgrade_worker_node.yml` (worker play) | `kubeadm upgrade node` for worker nodes. |
| `tasks/upgrade_kubelet_kubectl.yml` | Upgrades `kubelet`/`kubectl` (online or offline), asserts the installed version matches, reloads systemd, restarts kubelet. |
| `tasks/upgrade_uncordon_healthcheck.yml` | `kubectl uncordon` (retried — the apiserver can briefly return `Forbidden` right after a kubelet/CRI-O restart while RBAC finishes syncing), then waits for the node to report `Ready` before the serial loop advances. |

### Pre-Flight Safety Checks

1. Investigates existing locally installed `kubelet` versions.
2. Cross-references the provided `-e target_version`.
3. **Safety Guarantee:** If the requested upgrade jumps more than **one minor version** (e.g., from 1.28 to 1.30), the playbook immediately fails to enforce Kubernetes upgrade policies.
4. Takes an etcd snapshot before any control-plane change is made.

### Node-by-Node Rolling Upgrade Execution

For each node, one at a time (control-plane nodes first, then workers):

1. **Repo/Package Upgrade:** Online — replaces package manager repos with the target-version ones. Offline (`offline_install: true`) — installs `kubeadm` from the pre-staged bundle instead; see **Offline Upgrades** below.
2. **Kubeadm Upgrade Phase:**
   - On the *first* master: Executes `kubeadm upgrade apply <target-version>`. This upgrades the cluster configuration, etcd, API Server, Scheduler, and Controller Manager via static manifests.
   - On subsequent masters and workers: Executes `kubeadm upgrade node`.
3. **Zero-Downtime Node Draining:** Uses `kubectl drain <ansible_hostname> --ignore-daemonsets --delete-emptydir-data --force` to smoothly evict running pods over to other healthy nodes natively mapping the OS hostname to the Kubernetes node name.
4. **Upgrade Kubelet & Kubectl:** OS package update (or offline install) for `kubelet` and `kubectl` to exactly match the target, with a version-verify assertion.
5. **Restart OS Services:** `systemctl daemon-reload` and `systemctl restart kubelet`.
6. **Uncordon Node & Health Check:** Executes `kubectl uncordon <ansible_hostname>`, then polls until the node reports `Ready` before moving to the next node.

### Offline Upgrades

When `offline_install: true` (see `vars/cluster_config.yml`), the same `offline_pkg_path`/`offline_pkg_type`/`offline_pkg_source`/`remote_pkg_dir`/`remote_images_dir` vars used by `create_k8s.yml` apply here. **Re-stage the target version's `rpms/`+`images/` bundle at `offline_pkg_path` before running the upgrade** — the playbook fails fast in `tasks/upgrade_offline_preflight.yml` if the staged bundle is empty.

### Failure Handling — No Automatic Rollback

If `kubeadm upgrade apply` fails on the first control-plane node, the playbook **never rolls back on its own**. It:
- Warns and stops immediately if there is more than one control-plane node (automatic etcd restore is not supported for multi-member etcd).
- Otherwise, pauses and asks the operator whether to restore the etcd snapshot taken earlier (`tasks/upgrade_rollback.yml`, only reachable via an explicit `yes` answer).
- If the operator declines (or `interactive_rollback_prompt: false` for headless/CI runs), the play just fails with the snapshot path for manual recovery.

---

## 4. `upgrade_crio.yml` (CRI-O Upgrade)

Upgrades CRI-O to a new version on an already-running cluster, decoupled from `upgrade_k8s.yml` on purpose: unlike kubeadm, CRI-O has no one-minor-at-a-time restriction (it only needs to satisfy the CRI API kubelet expects), so this jumps directly to the target `crio_version` in one step per node instead of walking every minor. It's a thin two-play orchestrator (control plane, then workers, `serial: 1`) built around the same `crio/cri-o.yml` install logic `create_k8s.yml` uses.

### Why draining alone isn't enough

Restarting CRI-O recreates every running container's sandbox on that node at once. `kubectl drain` never evicts **static pods** (etcd, kube-apiserver, kube-controller-manager, kube-scheduler — kubelet manages these directly, ignoring cordon/drain) or DaemonSet pods. Container processes also live in `kubepods.slice`, not in `crio.service`'s own cgroup, so systemd's `KillMode=control-group` on a CRI-O restart never touches them. The result: if CRI-O restarts while those containers are still alive, the new CRI-O process can't cleanly reconcile stale references it has no record of, and gets stuck retrying forever — `crio.service` has `TimeoutStartUSec=infinity`, so systemd never force-kills it either. On a control-plane node, this reliably hangs a naive CRI-O restart.

### Node-by-Node Execution

For each node, one at a time (control plane first, then workers):

1. **Stage offline packages/images** (when `offline_install: true`) — same vars as the other playbooks.
2. **Drain** the node (`tasks/upgrade_drain.yml`).
3. **Stop kubelet, then stop every running container** (`tasks/upgrade_crio_stop_containers.yml`) — `crictl stop` against the *still-functional old* CRI-O, with kubelet paused so it doesn't race to recreate anything mid-swap. This is what actually avoids the stuck-restart problem above; draining alone does not.
4. **Install/upgrade CRI-O** (`crio/cri-o.yml`) — same code path `create_k8s.yml` uses. Also re-derives and rewrites the `pause_image` config from the current `kubeadm` binary every run, which fixes `pause_image` staleness as a side effect (it otherwise never gets touched by `upgrade_k8s.yml`, since that playbook doesn't manage CRI-O at all).
5. **Start kubelet** — it reconciles and recreates every pod, including static pods, fresh against the new CRI-O.
6. **Uncordon and health check** (`tasks/upgrade_uncordon_healthcheck.yml`).

### Offline installs use `rpm`, not `dnf`

The offline install tasks across this repo (`crio/cri-o.yml`, `tasks/install_kubernetes.yml`, `tasks/upgrade_kubeadm.yml`, `tasks/upgrade_kubelet_kubectl.yml`) use `rpm -Uvh --replacepkgs --oldpackage` on the pre-staged local files, not `ansible.builtin.dnf` or a `dnf install` shell command. `dnf` still invokes its subscription-manager plugin even with `--disablerepo=*`, which phones home and can hang for a long time (or effectively forever) on an airgapped host. `rpm` skips that entirely — safe here because the bundles are self-contained (`syncit pack` already resolved all dependencies), so there's no repo-aware resolution to lose.

---

## 5. `reset-k8s-cluster.yml` (Cluster Destruction)

This playbook tears down the environment safely. It is highly destructive.

1. **Confirmation Check:** Halts execution with an interactive pause module, forcing the user to explicitly type `yes` to authorize destruction *(can be bypassed automatically by appending `-e force_reset=yes`)*.
2. **Kubeadm Reset:** Executes `kubeadm reset -f` to systematically unconfigure static pods, delete local etcd member data, and reset iptables rules.
3. **Clean Configurations:** Hard deletes the master's `/etc/kubernetes/` directories, `/var/lib/kubelet/config.yaml`, and the user's `~/.kube/config`.
4. **Wipe CNI State:** Removes interface configuration files located in `/etc/cni/net.d/` (`10-calico.conflist`, `10-flannel.conflist`), then finds and deletes any leftover `cni0`/`flannel.1`/`cali*`/`vxlan.calico`/`tunl0`/`veth*` network interfaces — `kubeadm reset` doesn't tear these down on its own, and a stale bridge left with the old subnet's IP breaks the next `create_k8s.yml` run (`"cni0" already has an IP address different from X/24"`).
5. **Flush Container Runtimes:** Executes `crictl rm --all`, `crictl rmp --all`, and `crictl rmi --all` to permanently delete all stopped containers, active pods, and cached images left over by Kubernetes components.
6. **Optional Package Purge:** If `remove_packages` is set to `true`, the playbook also:
   - Uninstalls `kubelet`, `kubeadm`, `kubectl`, `kubernetes-cni`, `cri-o`, and `cri-tools` via `rpm -e --nodeps` (RHEL/CentOS/Fedora) — not `dnf remove`, for the same subscription-manager-hang reason described under `upgrade_crio.yml` above — or via `apt purge` (Ubuntu).
   - Deletes all package manager repository files and GPG keyrings.
   - Wipes all leftover runtime data directories (`/var/lib/containers`, `/var/lib/cni`, etc.).
