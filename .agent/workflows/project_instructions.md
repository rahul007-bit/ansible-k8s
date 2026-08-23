# System automation rules and project instructions

Context and operational guidelines for working on this Ansible-based Kubernetes repository.

---

## Repository context and scope

This repository manages cluster bootstrap, teardown, and rolling upgrades using Ansible:
- Container runtimes: `crio` and `containerd`.
- CNI plugins: `calico` and `flannel`.
- Operating systems: Debian/Ubuntu and RHEL-family (RHEL, Fedora, CentOS, Rocky Linux).

## Key playbooks

1. **`create_k8s.yml`**: Provisions a cluster. Configures base OS settings, container runtime, `kubeadm init` on the primary control plane, CNI manifests, and node joins.
2. **`upgrade_k8s.yml`**: Executes rolling upgrades sequentially (control plane group first, then workers). Validates minor version boundaries, snapshots etcd, updates packages, drains pods, upgrades kubelet, and uncordons nodes. If control plane upgrade fails, it halts and reports the etcd snapshot location without automatically rolling back.
3. **`upgrade_crio.yml`**: Upgrades CRI-O independently from Kubernetes binaries. Stops kubelet and terminates running containers with `crictl stop` before updating packages, preventing hung CRI-O restarts from unmanaged static pods.
4. **`reset-k8s-cluster.yml`**: Resets cluster state. Requires `-e force_reset=yes` for non-interactive execution. Cleans network bridges (`cni0`, `flannel.1`, `cali*`, `veth*`) and uses `rpm -e --nodeps` on RHEL-family nodes to prevent subscription-manager hangs.

Offline installs use `rpm` or `dpkg`, not `dnf` or `apt`. Package tasks in offline mode run `rpm -Uvh --replacepkgs --oldpackage` or `dpkg -i` to avoid network lookup timeouts on isolated nodes.

---

## Operational rules and caveats

### 1. CNI versioning variables

Keep `calico_version` (e.g. `v3.26.0`) and `flannel_version` (e.g. `v0.28.3`) in separate variables. Flannel release URLs 404 if given Calico format tags.

### 2. Node naming (`ansible_facts['hostname']` vs `inventory_hostname`)

Kubernetes registers nodes by operating system hostname. Always use `{{ ansible_facts['hostname'] }}` for `kubectl drain` and `kubectl uncordon` commands.

### 3. CRI-O package repositories and keys

Use `state: latest` with `force-overwrite` on Debian/Ubuntu to prevent package replacement conflicts during upgrades.

### 4. CNI binaries for CRI-O

CRI-O packages do not always place standard CNI plugins (`bridge`, `portmap`) into `/opt/cni/bin`. The playbook verifies `/opt/cni/bin/bridge` and downloads the release archive if missing.

### 5. Node facts

Access facts via `ansible_facts[...]` (e.g. `ansible_facts['distribution']`, `ansible_facts['os_family']`) to adhere to modern Ansible core specifications.

---

## Known limitations

1. **Changing CNI on existing clusters:** Switching CNI plugins requires running `reset-k8s-cluster.yml` before deploying the alternative CNI.
2. **Skipping minor versions:** Upgrades must proceed sequentially by minor version (e.g. 1.30 to 1.31, then 1.31 to 1.32).
3. **Single runtime per cluster:** All nodes in a cluster use the same configured runtime (`crio` or `containerd`).
4. **CRI-O version updates:** `upgrade_k8s.yml` manages Kubernetes binaries. Run `upgrade_crio.yml` to update the CRI-O runtime and refresh the pause image.
5. **Restarting CRI-O:** Stop kubelet and terminate existing workload containers before restarting CRI-O on running nodes to avoid sandbox reconciliation deadlocks.
