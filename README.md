# Kubernetes cluster automation with Ansible

Ansible playbooks to bootstrap, upgrade, and tear down bare-metal and VM Kubernetes clusters.

## Documentation

Detailed guides live in `docs/`:

- [01. Overview and architecture](docs/01_overview.md): playbooks, variables, runtime choices (CRI-O or containerd), and supported OS distributions.
- [02. Prerequisites and setup](docs/02_prerequisites.md): SSH keys, sudoers permissions, network requirements, and initial connectivity checks.
- [03. Usage guide](docs/03_usage_guide.md): running `create_k8s.yml`, `upgrade_k8s.yml`, and `reset-k8s-cluster.yml` with common flags and overrides.
- [04. Playbook internals](docs/04_top_level_playbooks.md): step-by-step breakdown of commands executed across each playbook.
- [05. Prerequisites playbook](docs/05_prerequisites_playbook.md): automated pre-flight checks for CPU, RAM, disk, mounts, ports, and mesh connectivity.

## Quick start

Define your nodes in `hosts`:

```ini
[controlplane]
node1 ansible_host=192.168.1.10 ansible_user=root

[worker]
node2 ansible_host=192.168.1.11 ansible_user=root
node3 ansible_host=192.168.1.12 ansible_user=root
```

Run pre-flight checks:

```bash
ansible-playbook -i hosts playbooks/prerequisites.yml
```

Create the cluster:

```bash
ansible-playbook -i hosts playbooks/create_k8s.yml
```

Upgrade the cluster to a new minor version:

```bash
ansible-playbook -i hosts playbooks/upgrade_k8s.yml -e target_version=1.31
```

Tear down the cluster:

```bash
ansible-playbook -i hosts playbooks/reset-k8s-cluster.yml -e force_reset=yes
```

### Makefile shortcuts

You can also run commands via `make`:

```bash
make ping                                     # Test SSH connectivity
make become-check                             # Test root/sudo escalation
make facts                                    # Test OS detection
make syntax-check                             # Validate playbook syntax
make prereq                                   # Run pre-flight checks
make create                                   # Create cluster
make upgrade TARGET_VERSION=1.31              # Upgrade Kubernetes
make upgrade-crio CRIO_VERSION=v1.32          # Upgrade CRI-O
make reset FORCE_RESET=yes                    # Reset cluster
```
