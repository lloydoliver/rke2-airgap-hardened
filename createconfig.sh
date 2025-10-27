#!/usr/bin/env bash
set -euo pipefail

# Load environment variables
set -a
source variables.env
set +a

WORK_DIR="rke2_configs"
mkdir -p "$WORK_DIR"

HOSTS=()

# Generate management hosts
for i in $(seq -f "%02g" 1 "$MGT_NODE_COUNT"); do
    HOSTS+=("${MGT_HOST_PREFIX}${i}.${DOMAIN_NAME}")
done

# Generate worker hosts
if (( WKR_NODE_COUNT > 0 )); then
    for i in $(seq -f "%02g" 1 "$WKR_NODE_COUNT"); do
        HOSTS+=("${WKR_HOST_PREFIX}${i}.${DOMAIN_NAME}")
    done
fi

# Save hosts list
printf '%s\n' "${HOSTS[@]}" > hosts.list

# Export host variables for templates
export HOST1="${HOSTS[0]}"
export HOST2="${HOSTS[1]}"
export HOST3="${HOSTS[2]}"
export HOST23="${HOSTS[1]} ${HOSTS[2]}"

# SSH options with ControlMaster for reuse
SSH_OPTS="-o StrictHostKeyChecking=no -o ControlMaster=auto -o ControlPersist=10m -o ControlPath=/tmp/ssh-%r@%h:%p"

SSH_BASE="$HOST_USER@"

# Function to run ssh command with error handling
ssh_exec() {
    local host=$1
    local cmd=$2
    echo "[SSH] Executing on $host: $cmd"
    if ! ssh $SSH_OPTS "$SSH_BASE$host" "$cmd"; then
        echo "[ERROR] SSH command failed on $host: $cmd" >&2
        exit 1
    fi
}

# Function to distribute ssh key
ssh_copy_id() {
    local host=$1
    echo "[SSH] Copying public key to $host"
    if ! ssh-copy-id $SSH_OPTS -i "$HOME/.ssh/id_rsa.pub" "$SSH_BASE$host"; then
        echo "[ERROR] Failed to copy SSH key to $host" >&2
        exit 1
    fi
}

# Generate RKE2 configuration files from templates
generate_config() {
    local tmpl=$1
    local out=$2
    echo "[CONFIG] Generating $out from $tmpl"
    if ! envsubst < "$tmpl" > "$WORK_DIR/$out"; then
        echo "[ERROR] Failed to generate $out from $tmpl" >&2
        exit 1
    fi
}

generate_config templates/config.yaml.tmpl config.yaml
generate_config templates/registries.yaml.tmpl registries.yaml
generate_config templates/nginx-load-balancer.conf.tmpl nginx-load-balancer.conf
generate_config templates/rke2-calico-config.yaml.tmpl rke2-calico-config.yaml
generate_config templates/kube-vip.yaml.tmpl kube-vip.yaml

# Ensure SSH key exists
if [ ! -f "$HOME/.ssh/id_rsa" ]; then
    echo "[SSH] Generating SSH key"
    ssh-keygen -q -t rsa -b 4096 -f "$HOME/.ssh/id_rsa" -N ""
fi

# Distribute SSH key to all hosts
for host in "${HOSTS[@]}"; do
    ssh_copy_id "$host"
done

# Download RKE2 install script
INSTALL_SCRIPT="./install.sh"
echo "[DOWNLOAD] RKE2 install script"
curl -sfL https://get.rke2.io -o "$INSTALL_SCRIPT"
chmod +x "$INSTALL_SCRIPT"

# Download kube-vip RBAC manifest
echo "[DOWNLOAD] kube-vip RBAC manifest"
curl -sfL https://kube-vip.io/manifests/rbac.yaml -o "$WORK_DIR/kube-vip-rbac.yaml"

echo
echo "[INFO] Configuration and installation files generated."
echo "[INFO] Run the 'download.sh' script to download required binaries for installation."
echo "[INFO] Run 'rke2-rmc-install.sh' to copy files to hosts and install RKE2."
