# Prerequisites playbook

The `prerequisites.yml` playbook validates system resources, storage mounts, endpoint reachability, and network ports before deploying Kubernetes.

Run it directly or enable it automatically in `create_k8s.yml` by setting `run_prerequisites: true` in `vars/cluster_config.yml`.

## Validations

### 1. Resource limits

Checks RAM, CPU cores, and root disk capacity against thresholds configured under `prereq_min_requirements` in `vars/cluster_config.yml`. Requirements can target specific hostnames or node groups.

### 2. External mounts

Checks whether required mount points exist and satisfy minimum free space thresholds under `prereq_external_mounts`.

### 3. URL reachability

Tests HTTP/HTTPS connectivity against URLs in `prereq_whitelisted_urls` (HTTP status 200, 401, or 403 are treated as reachable).

### 4. Local port availability

Runs `ss -tulnp` on all nodes to check that required Kubernetes ports (6443, 10250, etc.) are free.

### 5. Node-to-node connectivity

Validates inter-node network and firewall rules:
1. Deploys `scripts/port_listener.py` to listen on target Kubernetes ports.
2. Runs `ansible.builtin.wait_for` from every node to every other node to verify TCP communication.
3. Fails with source and destination details if a port is unreachable.

### 6. Pod CIDR and host subnet collision

Verifies that `pod_network_cidr` does not overlap with the physical network IP of any cluster node. If a collision is detected (for example, using `192.168.0.0/16` on a `192.168.50.0/24` LAN), the check fails with recommendations to change `pod_network_cidr` to prevent asymmetric routing and API server timeouts.

## Running the checks

Run pre-flight checks independently:

```bash
ansible-playbook -i hosts playbooks/prerequisites.yml
```
