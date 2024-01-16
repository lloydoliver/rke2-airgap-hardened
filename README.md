# RKE2 Airgap Hardened Install
Install RKE2 with a CIS Hardened Profile in a Air-Gap Environment

Edit variables.env to reflect the environment to be installed


# Ensure Host DNS entries are created

Run createconfig.sh to create required config files on a host with access to the RKE2 Machines

# Create Working Directories
mkdir -p suse/rancher
cd suse/rancher

git clone https://github.com/harrisonbc/rke2-airgap-hardened

run createconfig.sh to apply variables and create the required config files
