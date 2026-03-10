# System Automation Rules & Knowledge Base (Antigravity Agent Context)

This document provides system-level context, crucial project caveats, and instructions for developers and AI agents (like Antigravity) when working on this Ansible-based Kubernetes automation repository.

Whenever you are asked to update or troubleshoot this project, **read these rules and caveats first.**

---

## 🏗️ Repository Context and Purpose

This repository manages the complete lifecycle (bootstrap, destruction, and zero-downtime rolling upgrades) of a Kubernetes cluster using Ansible.

- It supports two runtimes: `containerd` and `cri-o`
- It supports two CNIs: `calico` and `flannel`
- It targets bare-metal or VM-based environments (Ubuntu/Debian and RHEL/CentOS/Fedora)

## 📖 Key Top-Level Playbooks

1. **`create_k8s.yml`**: Provisions a cluster. Responsible for system prep, container runtime installation, Control Plane 1 `kubeadm init`, CNI networking, HA master joins, and worker joins.
2. **`upgrade_k8s.yml`**: Conducts a rolling node-by-node upgrade. Pre-checks minor version compatibility, updates kubeadm/repos, executes drain, upgrades kubelet, and uncordons.
3. **`reset-k8s-cluster.yml`**: Tears everything down completely. Contains an explicit interactive prompt that must be bypassed with `-e force_reset=yes` for headless execution.

---

## 🚨 Critical Hard-Earned Learnings (Avoid Re-learning These)

Over the course of developing this repo, we ran into several severe implementation errors. Future agents and developers **must adhere** to these fixes:

### 1. Networking Version Configurations

In `create_k8s.yml`, **DO NOT** use a single `cni_version` variable for both plugins.

- Calico uses a `v3.x.x` version format (e.g. `v3.26.0`).
- Flannel relies on the `v0.x.x` format (e.g. `v0.26.0`).
Trying to attach a Calico version to a Flannel GitHub release URL will result in `404 Not Found` errors. These must remain completely broken out into `calico_version` and `flannel_version`.

### 2. Node Discrepancies (`ansible_hostname` vs `inventory_hostname`)

- In `hosts`, aliases like `host1` and `host2` are mapped to the generic `inventory_hostname`.
- However, when Kubernetes initializes, it natively discovers and names nodes by their OS Hostname (`rahul`, `worker`, etc.), represented in Ansible as `ansible_hostname`.
- Whenever writing tasks executing `kubectl drain` or `kubectl uncordon` inside Ansible playbooks, **always use `{{ ansible_hostname }}`**. Using `inventory_hostname` causes `NotFound` errors because Kubernetes does not know the Ansible inventory alias.

### 3. CRI-O Package Expirations and Repository Migrations

When installing older (now EOL) Kubernetes versions (like `v1.28`), `pkgs.k8s.io` will permanently throw `EXPKEYSIG` errors because the release signing keys have officially expired (as of Nov 2, 2024).

- To bypass this on `apt`, the CRI-O source definition in `Ubuntu` must explicitly use `[trusted=yes signed-by=...]`.
- You must actively clean up and remove legacy `devel:kubic` repositories before managing the modern `pkgs.k8s.io` CRI-O repo or `apt update` will fail.
- Always install CRI-O using `state: latest` with `dpkg_options: 'force-overwrite'`. This guarantees that legacy conflicts (like lingering `cri-o-runc` libraries on machines with history) are stomped over cleanly instead of failing the playbook.

### 4. CNI Binaries issue (CRI-O + Flannel)

Unlike Containerd, `cri-o` installed natively via packages will not always drop the networking `cni_plugins` dependencies (like `bridge` or `portmap`) into `/opt/cni/bin`. This results in pod sandbox errors. The `create_k8s.yml` playbook explicitly includes a safety check that curls the `containernetworking/plugins` release bundle if the CNI binaries are missing.

### 5. RedHat Subscription Manager Fallbacks 

When installing packages like `kubelet` or `cri-o` on RedHat 9 nodes without an active paid subscription, DNF will instantly crash with `Cannot download repomd.xml` due to 403 Forbidden errors hitting `appstream` and `codeready` nodes. 
- You must always explicitly append `disablerepo: "rhel-*,codeready-*"` and `enablerepo: "kubernetes,crio"` to DNF tasks.
- The Kubernetes package tasks currently inject a fallback generic `CentOS Stream 9` repository configuration into `hostvars` when this is detected to allow the OS to successfully resolve underlying AppStream C dependencies (like `socat` and `conntrack`).

---

## 🛠️ Developer & AI Agent Guidelines

1. **Keep documentation in sync.**
   Any time you add a variable, change a task workflow, or modify a runtime configuration, you **must natively update** the corresponding markdown files located in `/docs/` and `/crio/README.md`.
2. **Do test destructive tasks carefully.**
   When testing teardowns via `reset-k8s-cluster.yml`, always use the extra argument `-e force_reset=yes` if running via command line orchestration, or you will freeze the console waiting for user input.
3. **Restart OS Services:** `systemctl daemon-reload` and `systemctl restart kubelet`.
4. **Uncordon Node:** Executes `kubectl uncordon <ansible_hostname>` to mark the node as schedulable, returning it seamlessly to the cluster pool.

---

## 🚧 Missing Features & Future Work

If you are asked to expand the playbook, these are the core pieces currently missing that would make this a true production-grade deployment:

1. **Load Balancer Integration:**
   - Currently, `create_k8s.yml` points the `--control-plane-endpoint` directly at the IP of the *first* master node (`hostvars[groups['controlplane'][0]].ansible_host`).
   - If that single master goes down, the API server becomes entirely unreachable for workers, defeating the purpose of HA.
   - **Needed:** A task to configure HAProxy/Keepalived or an integration with an external cloud load balancer, and dynamically injecting that VIP into `control_plane_endpoint`.

2. **Ingress Controller Deployment:**
   - The cluster bootstraps successfully but has no way to route external layer 7 HTTP/HTTPS traffic to services.
   - **Needed:** An Ansible role to deploy NGINX Ingress, Traefik, or HAProxy Ingress post-CNI.

3. **Persistent Volume Provisioner:**
   - There is no default storage class. Pods cannot claim `PersistentVolumes` natively unless using `hostPath`.
   - **Needed:** Deployment tasks for OpenEBS, Longhorn, or an NFS client provisioner to handle dynamic PVCs.

4. **Metrics Server:**
   - Commands like `kubectl top nodes` or `kubectl top pods` will currently fail.
   - **Needed:** A task to apply `metrics-server` manifests after the CNI is healthy.

5. **Automated Certificate Rotation:**
   - `kubeadm` certificates expire after 1 year.
   - **Needed:** A cronjob or Ansible playbook specifically tailored to run `kubeadm certs renew all` across the control plane nodes safely.

---

## 🛑 What Doesn't Work (Known Limitations)

1. **Changing CNI Plugins Mid-Flight:**
   - You cannot run `create_k8s.yml` with `cni_plugin: calico` and then run it again tomorrow with `cni_plugin: flannel`.
   - They leave conflicting iptables rules and interface routes (`cni0`, `flannel.1`, `cali*`) that will completely break pod networking.
   - **Workaround:** You must exclusively run `reset-k8s-cluster.yml` entirely before switching CNIs.

2. **Skipping Minor Versions During Upgrades:**
   - The `upgrade_k8s.yml` playbook explicitly blocks jumping over minor versions (e.g., `1.28` -> `1.30`).
   - **Workaround:** You must target `1.29` first, let the nodes drain and upgrade, and then run the playbook a second time targeting `1.30`.

3. **Mixing Runtimes in the Same Cluster:**
   - The playbook assumes homogeneity. If you set `runtime: crio` in `create_k8s.yml`, it will forcefully install CRI-O and disable Containerd on *all* nodes in the inventory.
   - **Workaround:** You currently cannot have a cluster where control planes run CRI-O and workers run Containerd.

4. **Using Generic `inventory_hostname` for Kubernetes Commands:**
   - As mentioned above, using Ansible's `inventory_hostname` (e.g. `host1`) for `kubectl` commands (like `drain`, `uncordon`, `top`) will fail if the node's hostname is different. Kubernetes registers nodes by their OS hostname.
   - **Workaround:** Always use `{{ ansible_hostname }}` in Ansible tasks that interact with the Kubernetes API requiring a node name.
