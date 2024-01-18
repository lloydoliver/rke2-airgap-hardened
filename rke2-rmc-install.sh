#!/usr/bin/env bash

# Set Up variables
set -a
source variables.env
set +a

# Prepare hosts
# Create directories on the target hosts

echo 
echo "Create required directories on the hosts."
for i in $HOSTS; do ssh $HOST_USER@$i sudo mkdir -p ~/suse/rancher/ /etc/rancher/rke2/ /var/lib/rancher/rke2/server/manifests/ /var/lib/rancher/rke2/agent/images/ /opt/rke2/ ; done


# Copy files to the appropriate location on the 3 hosts

# config-1st.yaml & config.yaml
echo 
echo "Copy config.yaml to hosts."
scp config-1st.yaml $HOST_USER@$HOST1:/tmp/config.yaml && ssh $HOST_USER@$HOST1 sudo cp /tmp/config.yaml /etc/rancher/rke2/config.yaml 
for i in $HOST23; do scp config.yaml $HOST_USER@$i:/tmp/config.yaml && ssh $HOST_USER@$i sudo cp /tmp/config.yaml /etc/rancher/rke2/config.yaml ; done

# Registries redirect file, registries.yaml
echo 
echo "Copy registries.yaml to hosts."
for i in $HOSTS; do scp registries.yaml $HOST_USER@$i:/tmp && ssh $HOST_USER@$i sudo cp /tmp/registries.yaml /etc/rancher/rke2/registries.yaml ; done

# Pod Security Admission config file, rancher-psa.yaml
echo 
echo "Copy rancher-psa.yaml to hosts."
for i in $HOSTS; do scp rancher-psa.yaml $HOST_USER@$i:/tmp && ssh $HOST_USER@$i sudo cp /tmp/rancher-psa.yaml /etc/rancher/rke2/rancher-psa.yaml ; done

# Calico config file rke2-calico-config.yaml
# echo 
# echo "Copy rke2-calico-config.yaml to hosts."
# for i in $HOSTS; do scp rke2-calico-config.yaml $HOST_USER@$i:/tmp && ssh $HOST_USER@$i sudo cp /tmp/rke2-calico-config.yaml /var/lib/rancher/rke2/server/manifests/rke2-calico-config.yaml; done

# RKE2 Install script
echo 
echo "Copy RKE2 install script to hosts."
for i in $HOSTS; do scp install.sh $HOST_USER@$i:~/suse/rancher; done

# Reboot Nodes
echo 
echo "Reboot the 3 hosts."
for i in $HOSTS; do ssh $HOST_USER@$i sudo reboot ; done

# Install Required tools on Jump-Host
# In order to interact with the Kubernetes cluster from the command line, we need to install the kubectl command.
echo 
echo "Install kubectl commade on jumphost."
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
alias k=kubectl

# We can now install the kubernetes package manager
echo 
echo "Install helm command in jumphost."
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

# Create First Node
echo 
echo "Install RKE2 on First Node."
ssh $HOST_USER@$HOST1 sudo INSTALL_RKE2_VERSION=$RKE2_VERSION ~/suse/rancher/install.sh

# Perform CIS 1.23 Hardening Actions on 1st Node (Create etcd user & group, copy config file to correct location)
echo 
echo "Perform CIS Hardening steps on First Node."
ssh $HOST_USER@$HOST1 'sudo useradd -r -c "etcd user" -s /sbin/nologin -M etcd -U' 
# Only one copy operation will succeed but depends on how the OS is installed 
ssh $HOST_USER@$HOST1 'sudo cp -f /opt/rke2/share/rke2/rke2-cis-sysctl.conf /etc/sysctl.d/60-rke2-cis.conf' 
ssh $HOST_USER@$HOST1 'sudo cp -f /usr/local/share/rke2/rke2-cis-sysctl.conf /etc/sysctl.d/60-rke2-cis.conf' 
ssh $HOST_USER@$HOST1 'sudo cp -f /usr/share/rke2/rke2-cis-sysctl.conf /etc/sysctl.d/60-rke2-cis.conf' 

ssh $HOST_USER@$HOST1 'sudo systemctl restart systemd-sysctl' 

# Apply Calico Extra config - If Required
# echo 
# echo "Copy calico config file to first node."
# scp rke2-calico-config.yaml $HOST_USER@$HOST1:/tmp && ssh $HOST_USER@$HOST1 sudo cp /tmp/rke2-calico-config.yaml /var/lib/rancher/rke2/server/manifests/rke2-calico-config.yaml; done

# Enable and Start Cluster on 1st Node
echo 
echo "Enable and start RKE2 on First Node."
ssh $HOST_USER@$HOST1 sudo systemctl enable rke2-server.service
ssh $HOST_USER@$HOST1 sudo systemctl start rke2-server.service

# Retrieve kubeconfig file from first host
echo 
echo "Retrieve kubeconfig file."
scp $HOST_USER@$HOST1:/etc/rancher/rke2/rke2.yaml rke2.yaml

# Adjust host in URL to reflect Load Balancer Address
echo 
echo "Update kubeconfig file, with cluster url."
sed s/127.0.0.1/$CLUSTERNAME/ <./rke2.yaml >~/.kube/config

# The Cluster has now been created with the first node, we can join nodes 2 & 3
#
# Install RKE2 on 2nd & 3rd Node to join cluster created on 1st node

echo 
echo "Install RKE2 on Second & Third Node."
for i in $HOST23; do ssh $HOST_USER@$i INSTALL_RKE2_VERSION=$RKE2_VERSION ~/suse/rancher/install.sh; done

# Perform CIS 1.23 Hardening Actions on 2nd & 3rd Node (Create etcd user & group, copy config file to correct location)
echo 
echo "Perform CIS Hardening steps on Second & Third Node."
for i in $HOST23; do ssh $HOST_USER@$i 'useradd -r -c "etcd user" -s /sbin/nologin -M etcd -U | cp -f /opt/rke2/share/rke2/rke2-cis-sysctl.conf /etc/sysctl.d/60-rke2-cis.conf && systemctl restart systemd-sysctl' ; done

# Enable and Start Cluster on 2nd & 3rd Nodes
echo 
echo "Enable and start RKE2 on Second and Third Node."
for i in $HOST23; do ssh $HOST_USER@$i systemctl enable rke2-server.service; done
for i in $HOST23; do ssh $HOST_USER@$i systemctl start rke2-server.service; done

# The Cluster should now be created up and running.
echo 
echo "RKE2 Cluster up and running."
kubectl get nodes

# We now install Cert Manager if using rancher-signed certificates

echo 
echo "Install Cert-Manager onto Cluster."
helm repo add jetstack https://charts.jetstack.io
helm repo update
kubectl create namespace cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/$CERT_MANAGER_VERSION/cert-manager.crds.yaml

helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --version $CERT_MANAGER_VERSION

kubectl rollout status deployment -n cert-manager cert-manager
kubectl rollout status deployment -n cert-manager cert-manager-webhook


# Finally we can install Rancher
echo 
echo "Install Rancher onto Cluster."
helm repo add rancher https://releases.rancher.com/server-charts/latest
helm repo update
kubectl create namespace cattle-system

helm upgrade --install rancher rancher/rancher \
   --namespace cattle-system \
   --set bootstrapPassword="$RANCHER_BOOTSTRAP_PASSWORD" \
   --set hostname=$CLUSTERNAME

kubectl rollout status deployment/rancher -n cattle-system








