# Kubernetes Cluster Automation Makefile

INVENTORY ?= hosts
HOSTS ?= all
LIMIT ?=
EXTRA_VARS ?=
EXTRA_ARGS ?=
TARGET_VERSION ?=
CRIO_VERSION ?=
FORCE_RESET ?=
RUNTIME ?=
CNI ?=
OFFLINE ?=

# Build arguments dynamically
ARGS :=
ifneq ($(LIMIT),)
	ARGS += --limit $(LIMIT)
endif
ifneq ($(TARGET_VERSION),)
	ARGS += -e target_version=$(TARGET_VERSION)
endif
ifneq ($(CRIO_VERSION),)
	ARGS += -e crio_version=$(CRIO_VERSION)
endif
ifneq ($(FORCE_RESET),)
	ARGS += -e force_reset=$(FORCE_RESET)
endif
ifneq ($(RUNTIME),)
	ARGS += -e runtime=$(RUNTIME)
endif
ifneq ($(CNI),)
	ARGS += -e cni_plugin=$(CNI)
endif
ifneq ($(OFFLINE),)
	ARGS += -e offline_install=$(OFFLINE)
endif
ifneq ($(EXTRA_VARS),)
	ARGS += $(EXTRA_VARS)
endif
ifneq ($(EXTRA_ARGS),)
	ARGS += $(EXTRA_ARGS)
endif

.PHONY: help ping become-check facts syntax-check prereq create upgrade upgrade-crio reset

help:
	@echo "Kubernetes Cluster Management"
	@echo ""
	@echo "Usage: make <target> [OPTIONS]"
	@echo ""
	@echo "Diagnostics and pre-checks:"
	@echo "  make ping           Test Ansible SSH connectivity to hosts"
	@echo "  make become-check   Verify privilege escalation (sudo / root) on hosts"
	@echo "  make facts          Gather distribution and architecture facts"
	@echo "  make syntax-check   Check YAML and Ansible playbook syntax"
	@echo "  make prereq         Run the automated prerequisites playbook"
	@echo ""
	@echo "Playbook operations:"
	@echo "  make create         Bootstrap Kubernetes cluster"
	@echo "  make upgrade        Upgrade Kubernetes (e.g., make upgrade TARGET_VERSION=1.31)"
	@echo "  make upgrade-crio   Upgrade CRI-O (e.g., make upgrade-crio CRIO_VERSION=v1.32)"
	@echo "  make reset          Reset cluster state (e.g., make reset FORCE_RESET=yes)"
	@echo ""
	@echo "Options & Variables:"
	@echo "  INVENTORY=<path>        Inventory file path (default: hosts)"
	@echo "  HOSTS=<group>           Target group for ad-hoc checks (default: all)"
	@echo "  LIMIT=<pattern>         Limit execution to specific hosts"
	@echo "  TARGET_VERSION=<ver>    Target Kubernetes version (e.g., 1.31)"
	@echo "  CRIO_VERSION=<ver>      Target CRI-O version (e.g., v1.32)"
	@echo "  FORCE_RESET=yes         Skip confirmation prompt during cluster reset"
	@echo "  RUNTIME=<crio|containerd> Container runtime override"
	@echo "  CNI=<calico|flannel>    CNI network plugin override"
	@echo "  OFFLINE=<true|false>    Enable or disable offline mode"
	@echo "  EXTRA_VARS=\"-e key=val\" Pass custom Ansible extra variables"
	@echo "  EXTRA_ARGS=\"--check\"    Pass arbitrary Ansible command-line flags"

ping:
	ansible -i $(INVENTORY) $(HOSTS) -m ping $(ARGS)

become-check:
	ansible -i $(INVENTORY) $(HOSTS) -m command -a "whoami" --become $(ARGS)

facts:
	ansible -i $(INVENTORY) $(HOSTS) -m setup -a "filter=ansible_distribution*" --become $(ARGS)

syntax-check:
	ansible-playbook -i $(INVENTORY) --syntax-check \
		playbooks/create_k8s.yml \
		playbooks/upgrade_k8s.yml \
		playbooks/upgrade_crio.yml \
		playbooks/reset-k8s-cluster.yml \
		playbooks/prerequisites.yml

prereq:
	ansible-playbook -i $(INVENTORY) playbooks/prerequisites.yml $(ARGS)

create:
	ansible-playbook -i $(INVENTORY) playbooks/create_k8s.yml $(ARGS)

upgrade:
	ansible-playbook -i $(INVENTORY) playbooks/upgrade_k8s.yml $(ARGS)

upgrade-crio:
	ansible-playbook -i $(INVENTORY) playbooks/upgrade_crio.yml $(ARGS)

reset:
	ansible-playbook -i $(INVENTORY) playbooks/reset-k8s-cluster.yml $(ARGS)
