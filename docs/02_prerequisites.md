# Prerequisites and environment setup

Verify that your Ansible control node can connect to target hosts and run commands with root privileges before running the playbooks.

## Table of contents

- [1. Install Ansible](#1-install-ansible)
  - [Ubuntu and Debian](#ubuntu-and-debian)
  - [Fedora, RHEL, CentOS](#fedora-rhel-centos)
  - [Using pip](#using-pip)
- [2. SSH key setup](#2-ssh-key-setup)
  - [Generate an SSH key](#generate-an-ssh-key)
  - [Copy the key to target hosts](#copy-the-key-to-target-hosts)
  - [Verify SSH without password](#verify-ssh-without-password)
  - [Custom or non-default SSH keys](#custom-or-non-default-ssh-keys)
- [3. Test Ansible connectivity](#3-test-ansible-connectivity)
  - [Ping all hosts](#ping-all-hosts)
  - [Ping specific groups](#ping-specific-groups)
- [4. Test privilege escalation](#4-test-privilege-escalation)
  - [Test root command execution](#test-root-command-execution)
  - [Configure passwordless sudo](#configure-passwordless-sudo)
- [5. Test fact gathering](#5-test-fact-gathering)
- [6. Network requirements](#6-network-requirements)
- [7. Pre-flight checklist](#7-pre-flight-checklist)
- [Troubleshooting quick reference](#troubleshooting-quick-reference)

---

## 1. Install Ansible

### Ubuntu and Debian

```bash
sudo apt update
sudo apt install -y ansible
```

### Fedora, RHEL, CentOS

```bash
sudo dnf install -y ansible
```

### Using pip

```bash
pip install ansible
```

Verify the installation:

```bash
ansible --version
```

---

## 2. SSH key setup

Ansible connects to hosts via SSH. Passwordless key-based SSH is recommended.

### Generate an SSH key

```bash
ssh-keygen -t ed25519 -C "ansible-key"
```

### Copy the key to target hosts

```bash
ssh-copy-id root@192.168.1.205
ssh-copy-id root@192.168.1.123
```

### Verify SSH without password

```bash
ssh root@192.168.1.205 "hostname"
ssh root@192.168.1.123 "hostname"
```

Both commands should print the remote hostname without prompting for a password.

### Custom or non-default SSH keys

If using a custom key path (such as a `.pem` file or non-default identity):

1. Set appropriate permissions on your key file:

   ```bash
   chmod 600 ~/.ssh/my-key.pem
   ```

2. Confirm direct SSH connectivity:

   ```bash
   ssh -i ~/.ssh/my-key.pem root@192.168.1.205 "hostname"
   ```

3. Configure Ansible to use this key with one of these methods:

   **In `ansible.cfg`:**
   ```ini
   [defaults]
   private_key_file = ~/.ssh/my-key.pem
   ```

   **In `hosts` inventory (`[all:vars]`):**
   ```ini
   [all:vars]
   ansible_ssh_private_key_file=~/.ssh/my-key.pem
   ```

   **Via command line flag:**
   ```bash
   ansible-playbook -i hosts playbooks/create_k8s.yml --private-key=~/.ssh/my-key.pem
   ```

---

## 3. Test Ansible connectivity

### Ping all hosts

Run the `ping` module across inventory hosts:

```bash
ansible -i hosts all -m ping
```

Expected output:

```json
node1 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
node2 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

If hosts are unreachable, verify:
- SSH key installation on the remote target.
- Host IP addresses and user accounts defined in `hosts`.
- Python interpreter path on remote systems (`ansible_python_interpreter=/usr/bin/python3`).

### Ping specific groups

```bash
ansible -i hosts controlplane -m ping
ansible -i hosts worker -m ping
```

---

## 4. Test privilege escalation (become / sudo)

The playbooks use `become: true` to run administrative tasks. Verify this works across all hosts:

```bash
ansible -i hosts all -m command -a "whoami" --become
```

Expected output:

```text
node1 | CHANGED | rc=0 >>
root
node2 | CHANGED | rc=0 >>
root
```

### Configure passwordless sudo

If using a non-root SSH user, configure passwordless sudo on each node:

```bash
echo "ansible-user ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/ansible-user
```

---

## 5. Test fact gathering

Verify that Ansible collects system facts:

```bash
ansible -i hosts all -m setup -a "filter=ansible_distribution*" --become
```

Test architecture detection:

```bash
ansible -i hosts all -m setup -a "filter=ansible_architecture" --become
```

Expected output returns `x86_64` or `aarch64`.

---

## 6. Network requirements

The following ports must be open between nodes:

| Purpose | Port | Protocol | Scope |
| ------- | ---- | -------- | ----- |
| Kubernetes API server | 6443 | TCP | Control plane |
| etcd server client API | 2379-2380 | TCP | Control plane |
| Kubelet API | 10250 | TCP | All nodes |
| kube-scheduler | 10251 | TCP | Control plane |
| kube-controller-manager | 10252 | TCP | Control plane |
| NodePort services | 30000-32767 | TCP | Worker nodes |
| Calico BGP | 179 | TCP | Calico CNI |
| Calico VXLAN | 4789 | UDP | Calico CNI |
| Flannel VXLAN | 8472 | UDP | Flannel CNI |

---

## 7. Pre-flight checklist

Run this checklist before executing cluster playbooks:

```bash
# 1. Check Ansible version
ansible --version

# 2. Verify connectivity
ansible -i hosts all -m ping

# 3. Verify root privileges
ansible -i hosts all -m command -a "whoami" --become

# 4. Check OS detection
ansible -i hosts all -m setup -a "filter=ansible_distribution" --become

# 5. Dry run cluster creation
ansible-playbook -i hosts playbooks/create_k8s.yml --check
```

---

## Troubleshooting quick reference

| Issue | Diagnostic command | Resolution |
| ----- | ------------------ | ---------- |
| Host unreachable | `ansible -i hosts all -m ping -vvv` | Verify SSH keys, host IPs, and usernames in `hosts` |
| Python not found | `ssh user@host "which python3"` | Set `ansible_python_interpreter` in `hosts` |
| Sudo fails | `ssh user@host "sudo whoami"` | Configure passwordless sudo in `/etc/sudoers.d/` |
| Connection timeouts | `ansible -i hosts all -m ping -T 5` | Verify firewall rules and network routing |
| Host key errors | Set `host_key_checking = False` in `ansible.cfg` | Avoids interactive host key prompts |
