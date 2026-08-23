# Playbook internals: step-by-step technical execution

Technical breakdown of commands and operations executed across each playbook.

## Table of contents

- [1. `prerequisites.yml` (pre-flight checks)](#1-prerequisitesyml-pre-flight-checks)
- [2. `create_k8s.yml` (cluster creation)](#2-create_k8syml-cluster-creation)
- [3. `upgrade_k8s.yml` (cluster upgrade)](#3-upgrade_k8syml-cluster-upgrade)
- [4. `upgrade_crio.yml` (CRI-O upgrade)](#4-upgrade_crioyml-cri-o-upgrade)
- [5. `reset-k8s-cluster.yml` (cluster teardown)](#5-reset-k8s-clusteryml-cluster-teardown)

---

## 1. `prerequisites.yml` (pre-flight checks)

Validates system resources, storage mounts, endpoint reachability, and node-to-node port access before installing Kubernetes.

### Validation phases

1. **Resource and mount assessment:** Asserts that `ansible_facts['processor_vcpus']`, `ansible_facts['memtotal_mb']`, and `ansible_facts['mounts']` satisfy the limits in `vars/cluster_config.yml` by hostname or inventory group.
2. **Endpoint reachability:** Uses `ansible.builtin.uri` to verify network access to external registries and mirrors.
3. **Port availability:** Uses `ss -tulnp` to check that core ports (e.g. 6443, 10250) are not already bound by existing local services.
4. **Mesh connectivity:** Deploys a temporary Python listener script (`scripts/port_listener.py`) and uses `ansible.builtin.wait_for` across nodes to test node-to-node TCP reachability.

---

## 2. `create_k8s.yml` (cluster creation)

Provisions a Kubernetes cluster using `kubeadm`.

### Phase 1: Base system setup (`basic_setup/system_settings.yml`)

Loads kernel modules (`overlay`, `br_netfilter`), applies sysctl routing rules, disables swap, and configures firewall rules.

### Phase 2: Core Kubernetes packages (`tasks/install_kubernetes.yml`)

Configures package repositories and installs `kubeadm`, `kubelet`, and `kubectl` pinned to the specified version.

### Phase 3: Container runtime

Installs and configures containerd (`containerd/containerd.yml`) or CRI-O (`crio/cri-o.yml`), setting the systemd cgroup driver.

### Phase 4: Standard CNI binaries

Checks `/opt/cni/bin/bridge`. If absent, downloads and extracts the `containernetworking/plugins` release bundle to `/opt/cni/bin`.

### Phase 5: Primary control plane bootstrap

1. Checks for `/etc/kubernetes/admin.conf`. If present, initialization is skipped.
2. Runs `kubeadm init` with `--pod-network-cidr`, `--control-plane-endpoint`, and `--upload-certs`.
3. Creates `~/.kube/config` and copies `admin.conf` for `kube_user`.

### Phase 6: Networking (CNI)

1. Applies the chosen CNI manifest (Calico or Flannel) to the cluster.
2. Waits for CoreDNS pods to enter the `Running` state.

### Phase 7: Additional control plane join

*(Only runs when multiple nodes exist in `[controlplane]`)*

1. Uploads certificate keys to the first master and generates a control plane join command.
2. Runs `kubeadm join --control-plane --certificate-key ...` on additional masters.
3. Distributes `admin.conf` if `kubeconfig_on_all_cp: true`.

### Phase 8: Worker nodes join

*(Only runs for nodes in `[worker]`)*

Generates a bootstrap token join string and executes `kubeadm join` on worker nodes.

---

## 3. `upgrade_k8s.yml` (cluster upgrade)

Executes sequential rolling upgrades (`serial: 1`) across control plane nodes first, then worker nodes.

| Task file | Purpose |
| --------- | ------- |
| `tasks/upgrade_version_check.yml` | Validates target version against current version (maximum 1 minor version jump). |
| `tasks/upgrade_etcd_backup.yml` | Takes an etcd snapshot via `etcdctl` before modifying control plane nodes. |
| `tasks/upgrade_offline_preflight.yml` | Verifies offline package bundle contents when `offline_install: true`. |
| `tasks/upgrade_kubeadm.yml` | Upgrades `kubeadm` to the target version. |
| `tasks/offline_image_load.yml` | Pre-loads container images into runtime storage during offline upgrades. |
| `tasks/upgrade_drain.yml` | Drains the target node via `kubectl drain`. |
| `tasks/upgrade_control_plane_apply.yml` | Runs `kubeadm upgrade apply` (first master) or `kubeadm upgrade node` (subsequent masters). |
| `tasks/upgrade_worker_node.yml` | Runs `kubeadm upgrade node` on worker nodes. |
| `tasks/upgrade_kubelet_kubectl.yml` | Upgrades `kubelet` and `kubectl`, reloads systemd, and restarts the service. |
| `tasks/upgrade_uncordon_healthcheck.yml` | Uncordons the node and waits for `Ready` status before moving to the next node. |

### Rollback handling

If `kubeadm upgrade apply` fails on the first control plane node, the playbook halts and outputs the path to the etcd snapshot for recovery.

---

## 4. `upgrade_crio.yml` (CRI-O upgrade)

Upgrades the CRI-O runtime on an existing cluster independently from Kubernetes version upgrades.

### Execution steps

For each node sequentially (`serial: 1`):

1. Stages offline packages and images if `offline_install: true`.
2. Drains workload pods (`tasks/upgrade_drain.yml`).
3. Stops the `kubelet` service, then terminates running containers with `crictl stop` to prevent stale sandbox references.
4. Upgrades CRI-O packages and refreshes the pause image configuration.
5. Starts the `kubelet` service.
6. Uncordons the node and verifies node health (`tasks/upgrade_uncordon_healthcheck.yml`).

---

## 5. `reset-k8s-cluster.yml` (cluster teardown)

Removes cluster state across nodes:

1. Prompts for confirmation unless `-e force_reset=yes` is passed.
2. Runs `kubeadm reset -f`.
3. Deletes `/etc/kubernetes/`, `/var/lib/kubelet/`, and `~/.kube/config`.
4. Deletes `/etc/cni/net.d/` configurations and removes virtual network interfaces (`cni0`, `flannel.1`, `cali*`, `vxlan.calico`, `tunl0`).
5. Cleans container and pod state using `crictl`.
6. If `remove_packages: true`, uninstalls Kubernetes and CRI-O packages and deletes repository configurations.
