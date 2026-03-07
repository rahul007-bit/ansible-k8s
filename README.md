# Kubernetes Cluster Automation — Ansible Playbooks

This repository provides an automated, end-to-end bootstrap and teardown process for bare-metal and VM-based Kubernetes clusters using Ansible.

## 📚 Documentation

The detailed guide for this project is split into several documents under the `docs/` folder:

1. [**01. Overview & Architecture**](docs/01_overview.md)
   - A high-level look at the playbooks, configurable variables, container runtimes (CRI-O / containerd), and the supported operating systems.

2. [**02. Prerequisites & Pre-flight Checks**](docs/02_prerequisites.md)
   - Step-by-step instructions for preparing the control-plane and worker nodes before running the playbooks.

3. [**03. Usage Guide**](docs/03_usage_guide.md)
   - Detailed instructions on how to use `create_k8s.yml`, `upgrade_k8s.yml`, and `reset-k8s-cluster.yml`, including examples and expected outputs.

4. [**04. Top-Level Playbooks Breakdown**](docs/04_top_level_playbooks.md)
   - A descriptive, line-by-line explanation of each of the major top-level YAML playbooks.

## 🚀 Quick Start

Ensure your `hosts` inventory file is populated with your `[controlplane]` and `[worker]` nodes.

Then execute the cluster creation playbook:

```bash
ansible-playbook -i hosts create_k8s.yml
```

To upgrade an existing cluster to a new Kubernetes version:

```bash
ansible-playbook -i hosts upgrade_k8s.yml -e target_version=1.31
```

To entirely wipe all nodes (destructive operation):

```bash
ansible-playbook -i hosts reset-k8s-cluster.yml -e force_reset=yes
```

> **Note:** For deep-dives into individual components like CRI-O, Containerd, or Basic Setup, refer to the README files located inside each component's directory.
