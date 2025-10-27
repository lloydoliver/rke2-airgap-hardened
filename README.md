# Rancher & RKE2 Airgap Hardened Install
This repository will assist in the deployment of different configurations of RKE2/Rancher clusters in airgapped environments;

  - 3 node cluster with Rancher
  - 3 node cluster without rancher
  - multi node cluster with as many master and worker nodes as desired (with or without Rancher)

Installation options include
  - Private registry
  - Tarball installation

## Environment Requirements

For these scripts to work, one of the following conditions MUST be true;
- Private registry is available with required images
- tarball images have been downloaded and are available within the environment
- jump server has internet connectivity (download script is provided for this scenario)

So far this has only been tested on SLES15 SP7.

## Installation Steps

1. Have 3 (or more) hosts (either physical or virtual) ready with OS installed.

2. Setup the Load Balancer, an nginx config file is provided for testing purposes that can be used with docker: https://ranchermanager.docs.rancher.com/how-to-guides/new-user-guides/infrastructure-setup/nginx-load-balancer#option---run-nginx-as-docker-container

3. Ensure that the DNS entries have been created for the environment (nodes, Load Balancer etc).

4. On a host with network access to to the hosts:

        git clone https://github.com/harrisonbc/rke2-airgap-hardened
        cd rke2-airgap-hardened 

6. Copy and edit the variables.env file from the examples folder. Items to edit include;
    - Management node names
    - Worker node names
    - Node counts
    - Cluster Name
    - RKE2 Version
    - CNI & CIDR Settings
    - Addons (e.g vsphere CPI)
    - CIS Profile
    - Private Registry Settings (if using registry)
    - Cert Manager Version
    - Rancher Version
    - Rancher Password
    - Host user (ssh user to target hosts)


7. Run **createconfig.sh** to create required config files on a host with network access to the RKE2 Machines
run createconfig.sh to apply variables and create the required config files

8. Run **download.sh** if the system is internet connected in order to download the tarball files (only applicable if using the tarball install method)

9. run **rke2-rmc-install.sh**
