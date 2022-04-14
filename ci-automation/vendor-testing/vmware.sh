#!/bin/bash
# Copyright (c) 2022 The Flatcar Maintainers.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

set -euo pipefail

# Test execution script for the VMware ESX vendor image.
# This script is supposed to run in the SDK container.

work_dir="$1"; shift
arch="$1"; shift
vernum="$1"; shift
tapfile="$1"; shift

# $@ now contains tests / test patterns to run

source ci-automation/ci_automation_common.sh
source sdk_lib/sdk_container_common.sh

mkdir -p "${work_dir}"
cd "${work_dir}"
channel="$(get_git_channel)"
if [[ "${channel}" = 'developer' ]]; then
    channel='alpha'
fi
testscript="$(basename "$0")"

# We never ran VMware ESX on arm64, so for now fail it as an
# unsupported option.
if [[ "${arch}" == "arm64" ]]; then
    echo "1..1" > "${tapfile}"
    echo "not ok - all qemu tests" >> "${tapfile}"
    echo "  ---" >> "${tapfile}"
    echo "  ERROR: ARM64 tests not supported on VMware ESX." | tee -a "${tapfile}"
    echo "  ..." >> "${tapfile}"
    exit 1
fi

# Fetch image if not present.
if [ -f "${ESX_IMAGE_NAME}" ] ; then
    echo "++++ ${testscript}: Using existing ${work_dir}/${ESX_IMAGE_NAME} for testing ${vernum} (${arch}) ++++"
else
    echo "++++ ${testscript}: downloading ${ESX_IMAGE_NAME} for ${vernum} (${arch}) ++++"
    copy_from_buildcache "images/${arch}/${vernum}/${ESX_IMAGE_NAME}" .
fi

set -x

# krnowak: This is what the old script in jenkins did. I'm not sure we
# should be backporting this - it seems to be very specific for our
# setup.
#
# # Delete every VM that is running because we'll use all available spots
# ore esx --esx-config-file "${ESX_CONFIG_FILE}" remove-vms || :

kola_test_basename="ci-${vernum//+/-}"

trap 'ore esx --esx-config-file "${ESX_CONFIG_FILE}" remove-vms \
    --pattern "${kola_test_basename}*" || :; set +x' EXIT

sudo timeout --signal=SIGQUIT 2h kola run \
    --board="${arch}-usr" \
    --basename="${kola_test_basename}" \
    --channel="${channel}" \
    --platform=esx \
    --tapfile="${tapfile}" \
    --parallel="${ESX_PARALLEL}" \
    --torcx-manifest=../torcx_manifest.json \
    --esx-config-file "${ESX_CONFIG_FILE}" \
    --esx-ova-path "${ESX_IMAGE_NAME}" \
    "${@}"
