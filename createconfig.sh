#!/usr/bin/env bash

# Create Working Directories
# mkdir -p suse/rancher
# cd suse/rancher

# Set Up variables for config file
set -a
source variables.env
set +a

# Create and distribute ssh keys
# ssh-keygen -t rsa -b 4096
# for i in $HOSTS; do ssh-copy-id -i -y $HOME/.ssh/id_rsa.pub root@$i; done

# Create directories on the target hosts
# for i in $HOSTS; do ssh root@$i mkdir -p ~/suse/rancher/ /etc/rancher/rke2/ /var/lib/rancher/rke2/server/manifests/ /var/lib/rancher/rke2/agent/images/ /opt/rke2/ ; done

# Create RKE2 Cluster config file from template (config.yaml)
# The parameter reference is available here: https://docs.rke2.io/reference/server_config & https://docs.rke2.io/reference/linux_agent_config
envsubst < templates/config.yaml.tmpl > config.yaml

# Create RKE2 AirGap private registries config file from template (registries.yaml)
envsubst < templates/registries.yaml.tmpl > registries.yaml

# Create temporary DOCKER/NGINX Load Balancer config file from template (nginx-load-balancer.conf)
envsubst < templates/nginx-load-balancer.conf.tmpl > nginx-load-balancer.conf


