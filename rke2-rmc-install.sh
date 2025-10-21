#!/usr/bin/env bash
set -euo pipefail

# Enable exporting variables
set -a
source variables.env
set +a

# Load hosts
HOSTS=()
while IFS= read -r line; do
    HOSTS+=("$line")
done < hosts.list

HOST1="${HOSTS[0]}"
HOST23=("${HOSTS[@]:1}") # Assumes hosts 2 & 3
LOCAL_DIR="rke2_configs"
REMOTE_TMP="/tmp"
REMOTE_RKE2_DIR="/etc/rancher/rke2"
FILES=( "config.yaml" "registries.yaml" "rancher-psa.yaml" )
DIRS=( "/etc/rancher/rke2" "/var/lib/rancher/rke2/server/manifests" "/var/lib/rancher/rke2/agent/images" "/opt/rke2" )

SSH_BASE="$HOST_USER@"

# SSH ControlMaster options
SSH_OPTS="-o StrictHostKeyChecking=no -o ControlMaster=auto -o ControlPersist=10m -o ControlPath=/tmp/ssh-%r@%h:%p"

# Function to run SSH command with error handling
ssh_exec() {
    local host=$1
    local cmd=$2
    echo "[SSH] Executing on $host: $cmd"
    if ! ssh $SSH_OPTS "$SSH_BASE$host" "$cmd"; then
        echo "[ERROR] Command failed on $host: $cmd" >&2
        exit 1
    fi
}

# Function to SCP files with error handling
scp_copy() {
    local src=$1
    local host=$2
    local dst=$3
    echo "[SCP] Copying $src -> $host:$dst"
    if ! scp -r $SSH_OPTS "$src" "$SSH_BASE$host:$dst"; then
        echo "[ERROR] Failed to copy $src to $host:$dst" >&2
        exit 1
    fi
}

# Prepare management hosts
prepare_host() {
    local host=$1
    scp_copy "$LOCAL_DIR/" "$host" "$REMOTE_TMP/"

    CMD=""
    for dir in "${DIRS[@]}"; do
        CMD+="sudo mkdir -p $dir;"
    done
    for file in "${FILES[@]}"; do
        CMD+="sudo mv $REMOTE_TMP/$file $REMOTE_RKE2_DIR/$file;"
    done
    if [[ "$host" == "$HOST1" ]]; then
        CMD+="sudo sed -i '/^server/ s/^/# /' $REMOTE_RKE2_DIR/config.yaml;"
    fi
    ssh_exec "$host" "$CMD"
}

# Loop over hosts for preparation
for host in "${HOSTS[@]}"; do
    [[ "$host" == *"-mgt-"* ]] && prepare_host "$host"
done

# Copy install script to all hosts
for host in "${HOSTS[@]}"; do
    scp_copy "install.sh" "$host" "~/suse/rancher"
done

# Reboot hosts
for host in "${HOSTS[@]}"; do
    ssh_exec "$host" "sudo reboot"
done

# Wait for reboots
echo "[INFO] Waiting 60s for hosts to reboot..."
sleep 60

# Function to install RKE2 and perform CIS hardening
install_rke2() {
    local host=$1
    ssh_exec "$host" "sudo INSTALL_RKE2_VERSION=$RKE2_VERSION ~/suse/rancher/install.sh"
    ssh_exec "$host" 'sudo useradd -r -c "etcd user" -s /sbin/nologin -M etcd -U || true'
    for conf in "/opt/rke2/share/rke2/rke2-cis-sysctl.conf" "/usr/local/share/rke2/rke2-cis-sysctl.conf" "/usr/share/rke2/rke2-cis-sysctl.conf"; do
        ssh_exec "$host" "sudo cp -f $conf /etc/sysctl.d/60-rke2-cis.conf || true"
    done
    ssh_exec "$host" "sudo systemctl restart systemd-sysctl"
    ssh_exec "$host" "sudo systemctl enable rke2-server.service && sudo systemctl start rke2-server.service"
}

# Install first node
install_rke2 "$HOST1"

# Retrieve kubeconfig
scp_copy "$HOST1:/etc/rancher/rke2/rke2.yaml" "localhost" "./rke2.yaml"
sed "s/127.0.0.1/$CLUSTERNAME/" < ./rke2.yaml > ~/.kube/config
chmod 600 ~/.kube/config

# Install remaining nodes
for host in "${HOST23[@]}"; do
    install_rke2 "$host"
done

# Kubernetes tool installations on jumphost
echo "[INFO] Installing kubectl"
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
alias k=kubectl

echo "[INFO] Installing Helm"
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

# Install Cert-Manager
echo "[INFO] Installing Cert-Manager"
helm repo add jetstack https://charts.jetstack.io
helm repo update
kubectl create namespace cert-manager
kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/$CERT_MANAGER_VERSION/cert-manager.crds.yaml"
helm upgrade --install cert-manager jetstack/cert-manager --namespace cert-manager --version $CERT_MANAGER_VERSION
kubectl rollout status deployment -n cert-manager cert-manager
kubectl rollout status deployment -n cert-manager cert-manager-webhook

# Install Rancher
echo "[INFO] Installing Rancher"
helm repo add rancher https://releases.rancher.com/server-charts/latest
helm repo update
kubectl create namespace cattle-system
helm upgrade --install rancher rancher/rancher \
  --namespace cattle-system \
  --set bootstrapPassword="$RANCHER_BOOTSTRAP_PASSWORD" \
  --set hostname=$CLUSTERNAME
kubectl rollout status deployment/rancher -n cattle-system

echo "[INFO] RKE2 Cluster deployment complete."
kubectl get nodes
