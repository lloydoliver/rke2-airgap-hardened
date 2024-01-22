#!/usr/bin/env bash

# Create Working Directories
# mkdir -p suse/rancher
# cd suse/rancher

# Set Up variables for config file
set -a
source variables.env
set +a

# Create RKE2 Cluster config file from template (config.yaml)
# The parameter reference is available here: https://docs.rke2.io/reference/server_config & https://docs.rke2.io/reference/linux_agent_config
envsubst < templates/config.yaml.tmpl > config.yaml

# Create RKE2 AirGap private registries config file from template (registries.yaml)
envsubst < templates/registries.yaml.tmpl > registries.yaml

# Create temporary DOCKER/NGINX Load Balancer config file from template (nginx-load-balancer.conf)
envsubst < templates/nginx-load-balancer.conf.tmpl > nginx-load-balancer.conf

# Create Calico config file from template (rke2-calico-config.yaml)
envsubst < templates/rke2-calico-config.yaml.tmpl > rke2-calico-config.yaml

# Create kube-vip config file from template (kube-vip.yaml)
envsubst < templates/kube-vip.yaml.tmpl > kube-vip.yaml

# Create and distribute ssh keys
# ssh-keygen -t rsa -b 4096
ssh-keygen -q -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
for i in $HOSTS; do ssh-copy-id -i $HOME/.ssh/id_rsa.pub $HOST_USER@$i; done

# Download RKE2 Installation Script & make executable
curl -sfL https://get.rke2.io > ./install.sh
chmod +x ./install.sh

# Download rbac.yaml file for kube-vip
curl -sfL https://kube-vip.io/manifests/rbac.yaml > ./kube-vip-rbac.yaml

# Modify cluster config file for 1st Node
sed s/server:/#\ server:/ <config.yaml >config-1st.yaml

# Now run rke2-rmc-install.sh to copy files to hosts and install RKE2 
