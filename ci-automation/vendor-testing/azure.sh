#!/bin/bash
# Copyright (c) 2021 The Flatcar Maintainers.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

set -x
set -o noglob

set -euo pipefail

# Test execution script for the qemu vendor image.
# This script is supposed to run in the SDK container.

work_dir="$1"; shift
arch="$1"; shift
vernum="$1"; shift
tapfile="$1"; shift

# $@ now contains tests / test patterns to run

source ci-automation/ci_automation_common.sh

mkdir -p "${work_dir}"
cd "${work_dir}"

testscript="$(basename "$0")"

# Fetch the Azure image if not present
if [ -f "${AZURE_IMAGE_NAME}" ] ; then
    echo "++++ ${testscript}: Using existing ${work_dir}/${AZURE_IMAGE_NAME} for testing ${vernum} (${arch}) ++++"
else
    echo "++++ ${testscript}: downloading ${AZURE_IMAGE_NAME} for ${vernum} (${arch}) ++++"
    copy_from_buildcache "images/${arch}/${vernum}/${AZURE_IMAGE_NAME}.bz2" .
    lbunzip2 "${work_dir}/${AZURE_IMAGE_NAME}.bz2"
fi

if [[ "${arch}" == "arm64" ]]; then
  if [[ "${AZURE_HYPER_V_GENERATION}" != "V2" ]]; then
    echo "Unsupported combination"
    exit 1
  fi
  AZURE_USE_GALLERY="--azure-use-gallery"
fi

if [[ "${AZURE_MACHINE_SIZE}" != "" ]]; then
  AZURE_MACHINE_SIZE_OPT="--azure-size=${AZURE_MACHINE_SIZE}"
fi

# If the OFFER is empty, it should be treated as the basic offering.
if [[ "${AZURE_OFFER}" == "" ]]; then
  AZURE_OFFER="basic"
fi

set -x
set -o noglob

timeout=15h

basename_vernum=${vernum//+/-}

sudo timeout --signal=SIGQUIT "${timeout}" kola run \
    --board="${arch}-usr" \
    --basename="ci-${basename_vernum}" \
    --parallel="${AZURE_PARALLEL}" \
    --offering="${AZURE_OFFER}" \
    --platform=azure \
    --azure-image-file="${AZURE_IMAGE_NAME}" \
    --azure-location="${AZURE_LOCATION}" \
    --azure-profile="${AZURE_CREDENTIALS}" \
    --azure-auth="${AZURE_AUTH_CREDENTIALS}" \
    --tapfile="${tapfile}" \
    --torcx-manifest=../torcx_manifest.json \
    ${AZURE_USE_GALLERY} \
    ${AZURE_MACHINE_SIZE_OPT} \
    ${AZURE_HYPER_V_GENERATION:+--azure-hyper-v-generation=${AZURE_HYPER_V_GENERATION}} \
    ${AZURE_VNET_SUBNET_NAME:+--azure-vnet-subnet-name=${AZURE_VNET_SUBNET_NAME}} \
    ${AZURE_USE_PRIVATE_IPS:+--azure-use-private-ips=${AZURE_USE_PRIVATE_IPS}} \
    $@

set +o noglob
set +x
