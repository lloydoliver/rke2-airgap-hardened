#!/usr/bin/env bash
#
# Script Name: download.sh
# Description: Downloads RKE2 tarballs for airgap installation with optional CNI and addons.
# Author: Lloyd Oliver
# Date: 21/10/2025
# Version: 1.1
#

set -euo pipefail

# Load environment variables
set -a
source variables.env
set +a

ARTIFACT_DIR="rke2_artifacts"
mkdir -p "$ARTIFACT_DIR"
cd "$ARTIFACT_DIR"

# Determine files to download based on CNI and addons
FILES=()
if [[ -n "${CNI:-}" ]]; then
    FILES+=("rke2-images-$CNI.linux-amd64.tar.zst" "rke2.linux-amd64.tar.gz" "sha256sum-amd64.txt")
else
    FILES+=("rke2-images.linux-amd64.tar.zst" "rke2.linux-amd64.tar.gz" "sha256sum-amd64.txt")
fi

if [[ -n "${ADDONS:-}" ]]; then
    for addon in $ADDONS; do
        FILES+=("rke2-images-$addon.linux-amd64.tar.zst")
    done
fi

# Encode version for URL
VERSION="${RKE2_VERSION/+/%2B}"

# Function to download a single file with error handling
download_file() {
    local file=$1
    local url="https://github.com/rancher/rke2/releases/download/$VERSION/$file"
    echo "[DOWNLOAD] $file from $url"
    if ! curl -fSL --retry 3 --retry-delay 5 -O "$url"; then
        echo "[ERROR] Failed to download $file" >&2
        exit 1
    fi
}

# Download all files
for f in "${FILES[@]}"; do
    download_file "$f"
done

echo "[INFO] All RKE2 artifacts downloaded successfully to $ARTIFACT_DIR."
