# 05. Prerequisites Playbook

The `prerequisites.yml` playbook is designed to run automated, comprehensive pre-flight checks on your cluster before installing Kubernetes. While `02_prerequisites.md` covers manual OS preparation steps (like SSH keys and sudoers), this playbook automatically tests the environment for Kubernetes readiness.

This playbook can be run completely standalone, or it can be automatically included at the start of `create_k8s.yml` by setting `run_prerequisites: true` in `vars/cluster_config.yml`.

## What it Checks

### 1. Resource Limits
It verifies that each node has sufficient RAM, CPU cores, and Root Disk space.
- The requirements are defined in `vars/cluster_config.yml` under `prereq_min_requirements`.
- You can map requirements down to the **exact hostname** (highest priority) or to the **node group** (fallback).

### 2. External Mounts
If your cluster requires dedicated external storage (e.g., for Longhorn, NFS, or local persistent volumes), the playbook checks if specific mount paths are present and have the required capacities.
- Configured via `prereq_external_mounts`.
- You can target checks to specific nodes, specific groups, or all nodes.

### 3. URL Whitelisting
For environments with strict outbound firewall policies, the playbook attempts to reach required external endpoints (e.g., `github.com`, `registry.k8s.io`, or your private OCI registries).
- Configured via `prereq_whitelisted_urls`.
- It uses the `uri` module and tests for HTTP connectivity (200, 401, 403 are all considered successfully reachable).

### 4. Port Availability (In Use)
Before attempting to install Kubernetes, the playbook executes `ss -tulnp` on all nodes to ensure that standard Kubernetes ports (like `6443`, `10250`, etc.) are not already bound by existing, conflicting processes.

### 5. Node-to-Node Connectivity (Firewalls)
Kubernetes requires unimpeded communication between nodes. The playbook dynamically tests this via a temporary listener:
1. A small Python script (`scripts/port_listener.py`) is pushed to all nodes and temporarily binds to required Kubernetes TCP ports.
2. Every node in the cluster then attempts an N-to-N connection to every other node using the Ansible `wait_for` module.
3. If a firewall (e.g., AWS Security Group, local firewall, router ACL) blocks the connection, the playbook will fail and alert you exactly which node failed to reach which port.

## Running the Checks

To execute the checks independently without installing Kubernetes:

```bash
ansible-playbook -i hosts prerequisites.yml
```

> **Note:** If `run_prerequisites` is set to `true` in your configuration, running `ansible-playbook -i hosts create_k8s.yml` will automatically perform these exact same checks before proceeding with cluster installation.
