# Prerequisites & Environment Setup

Before running the Kubernetes playbooks, verify that your Ansible control node can reach all target hosts and has the correct permissions. This guide walks you through each check.

---

## 1. Install Ansible

### Ubuntu / Debian

```bash
sudo apt update
sudo apt install -y ansible
```

### Fedora / RHEL / CentOS

```bash
sudo dnf install -y ansible
```

### Using pip (any OS)

```bash
pip install ansible
```

Verify the installation:

```bash
ansible --version
```

> You should see the Ansible version, config file path, and Python version. If using a virtual environment, make sure it's activated first (`pyenv activate ansible`).

---

## 2. SSH Key Setup

Ansible connects to hosts via SSH. Password-less SSH is strongly recommended.

### Generate an SSH key (if you don't have one)

```bash
ssh-keygen -t ed25519 -C "ansible-key"
```

### Copy the key to all target hosts

```bash
# Control plane
ssh-copy-id rahul@192.168.1.205

# Workers
ssh-copy-id rahul@192.168.1.123
```

### Verify SSH works without a password

```bash
ssh rahul@192.168.1.205 "hostname"
ssh rahul@192.168.1.123 "hostname"
```

> Both should return the hostname without prompting for a password.

### Using a Non-Default or Custom SSH Key

Ansible tries default key names (`id_rsa`, `id_ed25519`, etc.) by default. If your key has a custom name or comes from an external source, follow the steps below.

#### Step A: Make Sure Your Key Works

If you already have a key in `~/.ssh/` (e.g., `id_rsa_test`) and you can SSH into the hosts with it, skip to Step B.

If someone gave you a private key file (e.g., a `.pem` from a cloud provider or your team), first make sure it actually works:

```bash
# Place the key in your ~/.ssh/ folder and lock down permissions
cp /path/to/my-server-key.pem ~/.ssh/my-server-key.pem
chmod 600 ~/.ssh/my-server-key.pem

# Try connecting — this is the real test
ssh -i ~/.ssh/my-server-key.pem rahul@192.168.1.205 "hostname"
```

If that works and you see the hostname, great — move to Step B.

If you get `Permission denied`, it means the remote server doesn't recognize your key yet. This happens because SSH authentication works like a lock and key — your **private key** (the `.pem` file) is the key, and the matching **public key** needs to be added to the server's `~/.ssh/authorized_keys` file.

To fix this, ask the server admin or your team to:

1. Get your public key (run this on your machine):

   ```bash
   ssh-keygen -y -f ~/.ssh/my-server-key.pem
   ```

   This prints the public key — copy the output.

2. Add it to the remote server's `~/.ssh/authorized_keys` file:

   ```bash
   # The admin runs this on the remote server
   echo "<paste-public-key-here>" >> ~/.ssh/authorized_keys
   ```

Once that's done, retry the SSH connection to confirm it works.

#### Step B: Tell Ansible Which Key to Use

Pick **one** of the following methods (ordered best → simplest):

##### 1. `ansible.cfg` — Best for projects (set once, applies to everything)

Create `ansible.cfg` in your project directory:

```ini
[defaults]
private_key_file = ~/.ssh/id_rsa_test
```

Every `ansible` and `ansible-playbook` command in this directory will use this key automatically.

##### 2. Inventory file — Best when different hosts need different keys

Add `ansible_ssh_private_key_file` in `[all:vars]` (same key for all hosts):

```ini
[all:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_private_key_file=~/.ssh/id_rsa_test
```

Or per-host (different keys per host):

```ini
[controlplane]
host3 ansible_host=192.168.1.205 ansible_user=rahul ansible_ssh_private_key_file=~/.ssh/key_for_master

[worker]
host2 ansible_host=192.168.1.123 ansible_user=rahul ansible_ssh_private_key_file=~/.ssh/key_for_worker
```

##### 3. `~/.ssh/config` — Best for system-wide SSH config (works beyond Ansible)

```ssh-config
Host 192.168.1.205
    User rahul
    IdentityFile ~/.ssh/id_rsa_test

Host 192.168.1.123
    User rahul
    IdentityFile ~/.ssh/id_rsa_test
```

This works for `ssh`, `scp`, `ansible`, and any tool that uses SSH.

##### 4. `ssh-agent` — Best for quick testing

```bash
eval $(ssh-agent -s)
ssh-add ~/.ssh/id_rsa_test
ansible -i hosts all -m ping
```

> Session lasts until terminal is closed. Add `ssh-add ~/.ssh/id_rsa_test` to `~/.bashrc` to make it persistent.

##### 5. Command line — Best for one-off runs

```bash
ansible -i hosts all -m ping --private-key=~/.ssh/id_rsa_test
ansible-playbook -i hosts create_k8s.yml --private-key=~/.ssh/id_rsa_test
```

---

## 3. Test Ansible Connectivity

### Ping all hosts

The most basic test — checks that Ansible can connect and Python is available:

```bash
ansible -i hosts all -m ping
```

#### Expected output

```bash
host3 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
host2 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

**If it fails**, common causes:

| Error | Fix |
| ------- | ----- |
| `UNREACHABLE` | SSH key not copied, or wrong IP/user in `hosts` file |
| `MODULE FAILURE` | Python not found on the remote host. Check `ansible_python_interpreter` in `hosts` |
| `Permission denied` | SSH user doesn't match, or key auth isn't set up |

### Ping specific groups

```bash
# Only control plane
ansible -i hosts controlplane -m ping

# Only workers
ansible -i hosts worker -m ping
```

---

## 4. Test Privilege Escalation (become / sudo)

The playbooks use `become: true` to run tasks as root. You must verify this works before running the playbook.

### Test running a command as root

```bash
ansible -i hosts all -m command -a "whoami" --become
```

#### Expected output

```bash
host3 | CHANGED | rc=0 >>
root
host2 | CHANGED | rc=0 >>
root
```

If the output shows `root`, you're good. If it fails:

### Common privilege issues and fixes

| Error | Cause | Fix |
| ------- | ------- | ----- |
| `Missing sudo password` | User requires password for sudo | Add `--ask-become-pass` or configure passwordless sudo (see below) |
| `not in the sudoers file` | User not in sudoers | Add the user: `sudo usermod -aG sudo rahul` (Ubuntu) or `sudo usermod -aG wheel rahul` (RHEL/Fedora) |
| `sudo: a password is required` | Password-less sudo not configured | Follow the passwordless sudo section below |

### Configure passwordless sudo (recommended)

On **each target host**, run:

```bash
# Ubuntu/Debian
echo "rahul ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/rahul

# RHEL/Fedora/CentOS  
echo "rahul ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/rahul
```

After this, re-test:

```bash
ansible -i hosts all -m command -a "whoami" --become
```

---

## 5. Test Fact Gathering

The playbook uses `gather_facts: true` to detect the OS, architecture, and distribution. Verify facts are collected correctly:

```bash
ansible -i hosts all -m setup -a "filter=ansible_distribution*" --become
```

#### Expected output (example for Ubuntu)

```json
{
    "ansible_distribution": "Ubuntu",
    "ansible_distribution_major_version": "22",
    "ansible_distribution_release": "jammy",
    "ansible_distribution_version": "22.04"
}
```

This confirms Ansible can detect the OS, which is required for the playbook's conditional logic (e.g., `apt` vs `dnf`).

### Test architecture detection

```bash
ansible -i hosts all -m setup -a "filter=ansible_architecture" --become
```

This should return `x86_64` or `aarch64` — used for Docker repo architecture mapping.

---

## 6. Network Requirements

Ensure the following network requirements are met on **all nodes**:

### Ports that must be open

| Component | Port(s) | Protocol | Used By |
| --------- | --------- | --------- | --------- |
| Kubernetes API | 6443 | TCP | `kubeadm`, `kubectl` |
| etcd | 2379-2380 | TCP | Control plane |
| kubelet | 10250 | TCP | All nodes |
| NodePort range | 30000-32767 | TCP | Workers (optional) |
| Calico BGP | 179 | TCP | Calico CNI |
| Calico VXLAN | 4789 | UDP | Calico CNI |
| Flannel VXLAN | 8472 | UDP | Flannel CNI |

### Quick network connectivity test between nodes

```bash
# From control node, test if hosts can reach each other
ansible -i hosts all -m command -a "ping -c 2 192.168.1.205" --become
ansible -i hosts all -m command -a "ping -c 2 192.168.1.123" --become
```

---

## 7. Pre-Flight Checklist

Run through this checklist before executing the playbook:

```bash
# 1. Ansible installed?
ansible --version

# 2. Can reach all hosts?
ansible -i hosts all -m ping

# 3. Can run as root?
ansible -i hosts all -m command -a "whoami" --become

# 4. OS detected correctly?
ansible -i hosts all -m setup -a "filter=ansible_distribution" --become

# 5. Swap status (should show swap disabled after playbook runs)
ansible -i hosts all -m command -a "swapon --show" --become

# 6. Dry run the playbook (no changes made)
ansible-playbook -i hosts create_k8s.yml --check
```

If **all 5 checks pass** (1-5), you're ready to run:

```bash
ansible-playbook -i hosts create_k8s.yml
```

---

## Troubleshooting Quick Reference

| Problem | Debug Command | Likely Fix |
| --------- | ------------ | ---------- |
| Can't connect | `ansible -i hosts all -m ping -vvv` | Check SSH keys, IPs, usernames |
| Python not found | `ssh user@host "which python3"` | Update `ansible_python_interpreter` in `hosts` |
| Sudo fails | `ssh user@host "sudo whoami"` | Configure passwordless sudo |
| Slow connections | `ansible -i hosts all -m ping -T 5` | Check network, firewall rules |
| Host key errors | `export ANSIBLE_HOST_KEY_CHECKING=False` | Or add to `ansible.cfg` |
