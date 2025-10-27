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
HOST2="${HOSTS[1]}"
HOST3="${HOSTS[2]}"
HOST23=("${HOSTS[@]:1}") # Assumes hosts 2 & 3
LOCAL_DIR="./rke2_configs"
REMOTE_TMP="/tmp"
REMOTE_RKE2_DIR="/etc/rancher/rke2"
FILES=( "config.yaml" "registries.yaml" "rancher-psa.yaml" )
DIRS=( "/etc/rancher/rke2" "/var/lib/rancher/rke2/server/manifests" "/var/lib/rancher/rke2/agent/images" "/opt/rke2" )
ARTIFACT_DIR="rke2_artifacts"

SSH_BASE="$HOST_USER@"

# SSH ControlMaster options
SSH_OPTS="-o ControlMaster=auto -o ControlPersist=10m -o ControlPath=/tmp/ssh-%r@%h:%p"
RKE2_INSTALL_ARGS=""

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

    if [[ -d "$src" ]]; then
        # Directory: copy contents, preserve structure
        if ! scp -q -r $SSH_OPTS "$src"/* "$SSH_BASE$host:$dst"; then
            echo "[ERROR] Failed to copy directory $src to $host:$dst" >&2
            exit 1
        fi
    else
        # Single file
        if ! scp -q $SSH_OPTS "$src" "$SSH_BASE$host:$dst"; then
            echo "[ERROR] Failed to copy file $src to $host:$dst" >&2
            exit 1
        fi
    fi
}

# Function to check if host is already configured
is_configured() {
    local host=$1
    echo "[INFO] Checking if $host is already configured"
    ssh $SSH_OPTS "$SSH_BASE$host" "[ -f /etc/rancher/.configured ] && systemctl is-active --quiet rke2-server" >/dev/null 2>&1
    return $?
}

# Add NOPASSWD to suoders file to avoid having to constantly type passwords
add_sudo_nopasswd() {
    local user=$HOST_USER
    local sudoers_line="${user} ALL=(ALL) NOPASSWD:ALL"
    local sudoers_file="/etc/sudoers.d/$user"

    ssh -t $SSH_OPTS "$SSH_BASE$host" "bash -c '
        if sudo grep -q \"^${user} \" /etc/sudoers; then
            echo \"User ${user} already exists in sudoers.\"
        else
            echo \"$sudoers_line\" | sudo tee \"$sudoers_file\" > /dev/null
            sudo chmod 440 \"$sudoers_file\"
            echo \"User ${user} added to sudoers with NOPASSWD.\"
        fi
    '"
}

# Remove NOPASSWD after installation
remove_sudo_nopasswd() {
    local user=$HOST_USER
    local sudoers_file="/etc/sudoers.d/$user"

    ssh $SSH_OPTS "$SSH_BASE$host" "bash -c '
        if [ -f \"$sudoers_file\" ]; then
            sudo rm -f \"$sudoers_file\"
            echo \"User ${user} removed from sudoers NOPASSWD.\"
        else
            echo \"No sudoers entry found for user ${user}.\"
        fi
    '"
}

# Prepare management hosts
prepare_host() {
    local host=$1

    if is_configured "$host"; then
        echo "[INFO] $host already configured. Skipping preparation."
        return
    fi

    add_sudo_nopasswd

    scp_copy "$LOCAL_DIR/" "$host" "$REMOTE_TMP/"
    scp_copy ./rancher-psa.yaml "$host" "$REMOTE_TMP/"

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
    # Disable firewalld
    CMD+="sudo systemctl stop firewalld; sudo systemctl disable firewalld;"
    # Disable swap
    CMD+="sudo swapoff -a; sudo sed -i.bak '/ swap / s/^\(.*\)$/#\1/' /etc/fstab;"
    ssh_exec "$host" "$CMD"
}

# Loop over hosts for preparation
for host in "${HOSTS[@]}"; do
    [[ "$host" == *"-mgt-"* ]] && prepare_host "$host"
done

if [[ "$INSTALL_METHOD" == "TARBALL" ]]; then
    # Upload RKE2 artifacts to all hosts
    for host in "${HOSTS[@]}"; do
        if is_configured "$host"; then
            echo "[INFO] $host already configured. Skipping artifact upload."
            continue
        fi

        for local_file in "$ARTIFACT_DIR"/*; do
            filename=$(basename "$local_file")
            # Check if file exists and has the same size on remote host
            if ssh $SSH_OPTS "$SSH_BASE$host" "[ -f $REMOTE_TMP/$filename ] && [ \$(stat -c%s $REMOTE_TMP/$filename) -eq \$(stat -c%s $local_file) ]"; then
                echo "[INFO] $filename already exists on $host:$REMOTE_TMP with correct size. Skipping."
                continue
            fi
            echo "[SCP] Uploading $filename to $host:$REMOTE_TMP"
            scp_copy "$local_file" "$host" "$REMOTE_TMP/"
        done
    done
    RKE2_INSTALL_ARGS+="INSTALL_RKE2_ARTIFACT_PATH=/$REMOTE_TMP "
fi


# Function to install RKE2 and perform CIS hardening
install_rke2() {
    local host=$1

    if is_configured "$host"; then
        echo "[INFO] $host already configured. Skipping RKE2 installation."
        return
    fi

    # if 
    if [[ " $HOST1 $HOST2 $HOST3 " =~ " $host " ]]; then
      echo ""
      echo "[INFO] Installing master node on $host"
      echo "-- Installation args = $RKE2_INSTALL_ARGS"
      ssh_exec "$host" "sudo $RKE2_INSTALL_ARGS $REMOTE_TMP/install.sh"
    else
      echo ""
      echo "[INFO] Installing worker node on $host"
      echo "-- Installation args = $RKE2_INSTALL_ARGS"
      ssh_exec "$host" "sudo INSTALL_RKE2_TYPE="agent" $RKE2_INSTALL_ARGS $REMOTE_TMP/install.sh"
    fi
    
    echo "[INFO] Setting kernel parameters"
    ssh_exec "$host" 'sudo useradd -r -c "etcd user" -s /sbin/nologin -M etcd -U || true'
    for conf in "/opt/rke2/share/rke2/rke2-cis-sysctl.conf" "/usr/local/share/rke2/rke2-cis-sysctl.conf" "/usr/share/rke2/rke2-cis-sysctl.conf"; do
        ssh_exec "$host" "sudo cp -f $conf /etc/sysctl.d/60-rke2-cis.conf || true"
    done
    ssh_exec "$host" "sudo systemctl restart systemd-sysctl"

    echo "[INFO] Starting RKE2"
    ssh_exec "$host" "sudo systemctl enable rke2-server.service && sudo systemctl start rke2-server.service"

    # Create marker file
    ssh_exec "$host" "sudo touch /etc/rancher/.configured"

    remove_sudo_nopasswd
}

# Install first node
install_rke2 "$HOST1"

# Kubernetes tool installations on jumphost
echo "[INFO] Installing kubectl"
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
alias k=kubectl

# Retrieve kubeconfig
echo ""
echo "[INFO] Copying Kubeconfig from $HOST1 to localhost"
mkdir -p |/.kube/
scp -q -r $SSH_OPTS "$HOST_USER@$HOST1:/etc/rancher/rke2/rke2.yaml" "localhost" "./rke2.yaml"
sed "s/127.0.0.1/$CLUSTERNAME/" < ./rke2.yaml > ~/.kube/config
chmod 600 ~/.kube/config

# Function used to check for nodes to be ready before moving on to the next step
wait_for_nodes_ready() {
    local interval=5  # seconds between checks
    local timeout=300 # maximum wait time in seconds
    local elapsed=0

    while true; do
        not_ready=$(kubectl get nodes --no-headers | awk '$2 != "Ready" {print $1}')
        if [ -z "$not_ready" ]; then
            echo "All nodes are Ready."
            break
        else
            echo "Waiting for nodes to be Ready: $not_ready"
        fi

        sleep $interval
        elapsed=$((elapsed + interval))
        if [ $elapsed -ge $timeout ]; then
            echo "Timeout waiting for nodes to be Ready."
            exit 1
        fi
    done
}

wait_for_nodes_ready

# Install remaining master nodes
for host in "${HOST23[@]}"; do
    install_rke2 "$host"
done

# Iterate over the hosts.list file, and install RKE2 on worker nodes
INSTALLED=("$HOST1" "${HOST23[@]}")
for host in "${HOSTS[@]}"; do
    # Skip if already installed
    if [[ "${INSTALLED[*]}" == "$host" ]]; then
        continue
    fi
    install_rke2 "$host"
done

# Close all persistent SSH ControlMaster connections
echo "[INFO] Closing all persistent SSH connections"
for host in "${HOSTS[@]}"; do
    ssh -O exit $SSH_OPTS "$HOST_USER@$host" 2>/dev/null || true
done

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
