# Rancher & RKE2 Airgap Hardened Install
This repository will assist in the installation of SUSE Rancher on a 3-Node RKE2 Cluster in and AirGapped environment, and will additionally apply CIS Hardening steps with a view to passing the CIS 1.23 Benchmark


## Installation Steps

1. Create the 3 VMs to host the RKE2 Nodes. Refer the to the Pre-Requisites: https://ranchermanager.docs.rancher.com/how-to-guides/new-user-guides/infrastructure-setup/ha-rke2-kubernetes-cluster

2. Setup the Load Balancer, an nginx config file is provided for testing purposes that can be used with docker: https://ranchermanager.docs.rancher.com/how-to-guides/new-user-guides/infrastructure-setup/nginx-load-balancer#option---run-nginx-as-docker-container

3. Ensure that the DNS entries have been created for the environment (nodes, Load Balancer etc).

4. Populate your private registry with the required images

5. Edit the variables.env file to reflect the environment to be installed. Items include:

        - Host Names
        - Cluster Name
        - RKE2 Version
        - CNI & CIDR Settings
        - CIS Profile
        - Private Registry Settings
        - Cert Manager Version
        - Rancher Version
        - Rancher Password

6. On a host with network access to to the 3 VMs:

        mkdir -p suse/rancher
        cd suse/rancher
        git clone https://github.com/harrisonbc/rke2-airgap-hardened
        cd rke2-airgap-hardened

7. Run **createconfig.sh** to create required config files on a host with network access to the RKE2 Machines
run createconfig.sh to apply variables and create the required config files

8. run **rke2-rmc-install.sh**
