#!/bin/bash
# Copyright (c) 2021 The Flatcar Maintainers.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

set -euo pipefail

# Test execution script for the Equinix Metal vendor image.
# This script is supposed to run in the SDK container.
# This script requires "pxe" Jenkins job.

work_dir="$1"; shift
arch="$1"; shift
vernum="$1"; shift
tapfile="$1"; shift

channel="$(get_git_channel)"

# $@ now contains tests / test patterns to run

source ci-automation/ci_automation_common.sh

mkdir -p "${work_dir}"
cd "${work_dir}"

# Equinix Metal ARM server are not yet hourly available in the default `SV` metro
# so we override the `EQUINIXMETAL_METRO` to `Dallas` since it's available in this metro.
# We do not override `EQUINIXMETAL_METRO` for both board on top level because we need to keep proximity
# for PXE booting.
# We override `PARALLEL_TESTS`, because kola run with PARALLEL_TESTS >= 4 causes the
# tests to provision >= 12 ARM servers at the same time. As the DA metro does not
# have that many free ARM servers, the whole tests will fail. With PARALLEL_TESTS=2
# the total number of servers stays < 10.
# In addition, we override `timeout` to 10 hours, because it takes more than 8 hours
# to run all tests only with 2 tests in parallel.
if [[ "${arch}" == "arm64" ]]; then
  EQUINIXMETAL_METRO="DA"
  EQUINIXMETAL_PARALLEL="2"
  timeout=15h
else
  timeout=8h
fi

BASE_URL="https://${BUILDCACHE_SERVER}/images/${arch}/${vernum}"

set -x
set -o noglob

sudo timeout --signal=SIGQUIT "${timeout}" kola run \
    --board="${arch}-usr" \
    --basename="ci-${vernum}" \
    --platform=equinixmetal \
    --tapfile="${tapfile}" \
    --parallel="${EQUINIXMETAL_PARALLEL}" \
    --torcx-manifest=../torcx_manifest.json \
    --equinixmetal-image-url="${BASE_URL}/${EM_IMAGE_NAME}" \
    --equinixmetal-installer-image-kernel-url="${BASE_URL}/${PXE_KERNEL_NAME}" \
    --equinixmetal-installer-image-cpio-url="${BASE_URL}/${PXE_IMAGE_NAME}" \
    --equinixmetal-project="${EQUINIXMETAL_PROJECT}" \
    --equinixmetal-storage-url="${EM_STORAGE_URL}" \
    --equinixmetal-metro="${EQUINIXMETAL_METRO}" \
    --gce-json-key="${GCP_JSON_KEY}" \
    --equinixmetal-api-key="${EQUINIXMETAL_KEY}" \
    $@

set +o noglob
set +x
