#!/bin/bash
#
# Script Name: download.sh
# Description: This script downloads the RKE2 tarballs required for airgap installation.
# Author: Lloyd Oliver 
# Date: 21/10/2025
# Version: 1.0
#
# Usage:
#   ./download.sh
#
# Parameters:
#   None

# load variables file
set -a
source variables.env
set +a

# Stop script on any error
set -e

# Create required directories
mkdir -p rke2_artifacts
cd rke2_artifacts

# If a CNI is specified, download the relevant files.
if [[ -n "$CNI" ]]; then
  FILES=("rke2-images-$CNI.linux-amd64.tar.zst" "rke2.linux-amd64.tar.gz" "sha256sum-amd64.txt")
else
# if no CNI is specified, download the standard files.
  FILES=("rke2-images.linux-amd64.tar.zst" "rke2.linux-amd64.tar.gz" "sha256sum-amd64.txt")
fi

# If addons are specified, include these files in the downloads.
if [[ -n "$ADDONS" ]]; then
  for ADDON in $ADDONS;
  do 
    FILES=(${FILES[@]} "rke2-images-$ADDON.linux-amd64.tar.zst")
  done
fi

# the version needs to be converted to URL friendly format
VERSION="${RKE2_VERSION/+/%2B}"
# Download the files.
for F in "${FILES[@]}"; 
do
  echo "Downloading $RKE2_VERSION/$F"
  curl -OLs https://github.com/rancher/rke2/releases/download/$VERSION/$F
done
