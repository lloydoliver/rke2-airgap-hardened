#!/usr/bin/env bash


# Set Up variables
set -a
source variables.env
set +a

# Prepare hosts
# Create directories on the target hosts
for i in $HOSTS; do ssh root@$i mkdir -p ~/suse/rancher/ /etc/rancher/rke2/ /var/lib/rancher/rke2/server/manifests/ /var/lib/rancher/rke2/agent/images/ /opt/rke2/ ; done


# Copy files to the appropriate location on the 3 hosts

# config-1st.yaml & config.yaml
scp config-1st.yaml root@$HOST1:/etc/rancher/rke2/config.yaml 
for i in $HOST23; do scp config.yaml root@$i:/etc/rancher/rke2/config.yaml ; done

# Registries redirect file registries.yaml
for i in $HOSTS; do scp registries.yaml root@$i:/etc/rancher/rke2/registries.yaml ; done

# Pod Security Admission config file, rancher-psa.yaml
for i in $HOSTS; do scp rancher-psa.yaml root@$i:/etc/rancher/rke2/rancher-psa.yaml ; done

# Calico config file rke2-calico-config.yaml
for i in $HOSTS; do scp rke2-calico-config.yaml root@$i:/var/lib/rancher/rke2/server/manifests/rke2-calico-config.yaml; done

# RKE2 Install script
for i in $HOSTS; do scp install.sh root@$i:~/suse/rancher; done

# Reboot Nodes
# for i in $HOSTS; do ssh root@$i reboot ; done

# Install Required tools
# In order to interact with the Kubernetes cluster from the command line, we need to install the kubectl command.
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/
alias k=kubectl

# We can now install the kubernetes package manager
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

# Create First Node
ssh root@$HOST1 INSTALL_RKE2_VERSION=$RKE2_VERSION ~/suse/rancher/install.sh

# Perform CIS 1.23 Hardening Actions on 1st Node (Create etcd user & group, copy config file to correct location)
ssh root@$HOST1 'useradd -r -c "etcd user" -s /sbin/nologin -M etcd -U | cp -f /opt/rke2/share/rke2/rke2-cis-sysctl.conf /etc/sysctl.d/60-rke2-cis.conf | systemctl restart systemd-sysctl' 

# Apply Calico Extra config - If Required
# scp rke2-calico-config.yaml root@$HOST1:/var/lib/rancher/rke2/server/manifests/rke2-calico-config.yaml

# Enable and Start Cluster on 1st Node
ssh root@$HOST1 systemctl enable rke2-server.service
ssh root@$HOST1 systemctl start rke2-server.service

# Retrieve kubeconfig file from first host
scp root@$HOST1:/etc/rancher/rke2/rke2.yaml rke2.yaml

# Adjust host in URL to reflect Load Balancer Address
sed s/127.0.0.1/$CLUSTERNAME/ <./rke2.yaml >~/.kube/config

# The Cluster has now been created with the first node, we can join nodes 2 & 3
#
# Install RKE2 on 2nd & 3rd Node to join cluster created on 1st node

for i in $HOST23; do ssh root@$i INSTALL_RKE2_VERSION=$RKE2_VERSION ~/suse/rancher/install.sh; done

# Perform CIS 1.23 Hardening Actions on 2nd & 3rd Node (Create etcd user & group, copy config file to correct location)
for i in $HOST23; do ssh root@$i 'useradd -r -c "etcd user" -s /sbin/nologin -M etcd -U | cp -f /opt/rke2/share/rke2/rke2-cis-sysctl.conf /etc/sysctl.d/60-rke2-cis.conf && systemctl restart systemd-sysctl' ; done

# Enable and Start Cluster on 2nd & 3rd Nodes
for i in $HOST23; do ssh root@$i systemctl enable rke2-server.service; done
for i in $HOST23; do ssh root@$i systemctl start rke2-server.service; done

# The Cluster should now be created up and running.

# We now install Cert Manager if using rancher-signed certificates

helm repo add jetstack https://charts.jetstack.io
helm repo update
kubectl create namespace cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/$CERT_MANAGER_VERSION/cert-manager.crds.yaml

helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --version $CERT_MANAGER_VERSION

kubectl rollout status deployment -n cert-manager cert-manager
kubectl rollout status deployment -n cert-manager cert-manager-webhook


# Finally we can install Rancher
helm repo add rancher https://releases.rancher.com/server-charts/latest
helm repo update
kubectl create namespace cattle-system

helm upgrade --install rancher rancher/rancher \
   --namespace cattle-system \
   --set bootstrapPassword="$RANCHER_BOOTSTRAP_PASSWORD" \
   --set hostname=$CLUSTERNAME

kubectl rollout status deployment/rancher -n cattle-system








