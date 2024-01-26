# Rancher & RKE2 Airgap Hardened Install
This repository will assist in the installation of SUSE Rancher on a 3-Node RKE2 Cluster in and AirGapped environment, and will additionally apply CIS Hardening steps with a view to passing the CIS 1.23 Benchmark


## Installation Steps

1. Create the 3 VMs to host the RKE2 Nodes. Refer the to the Pre-Requisites: https://ranchermanager.docs.rancher.com/how-to-guides/new-user-guides/infrastructure-setup/ha-rke2-kubernetes-cluster
Edit the variables.env file to reflect the environment to be installed
2. Ensure that the DNS entries have been created Run the 


## Ensure Host DNS entries are created
Run createconfig.sh to create required config files on a host with access to the RKE2 Machines

## Create Working Directories
mkdir -p suse/rancher
cd suse/rancher

git clone https://github.com/harrisonbc/rke2-airgap-hardened

run createconfig.sh to apply variables and create the required config files
