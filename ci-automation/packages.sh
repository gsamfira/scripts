#!/bin/bash
#
# Copyright (c) 2021 The Flatcar Maintainers.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# >>> This file is supposed to be SOURCED from the repository ROOT. <<<
#
# packages_build() should be called w/ the positional INPUT parameters below.

# OS image binary packages build automation stub.
#   This script will use an SDK container to build packages for an OS image.
#   It will update the versionfile with the OS packages version built,
#    and will add a version tag (see INPUT) to the scripts repo. 
#
# PREREQUISITES:
#
#   1. SDK version is recorded in sdk_container/.repo/manifests/version.txt
#   2. SDK container is either
#       - available via ghcr.io/flatcar-linux/flatcar-sdk-[ARCH]:[VERSION] (official SDK release)
#       OR
#       - available via build cache server "/containers/[VERSION]/flatcar-sdk-[ARCH]-[VERSION].tar.gz"
#         (dev SDK)
#
# INPUT:
#
#   1. Version of the TARGET OS image to build (string).
#       The version pattern '(alpha|beta|stable|lts)-MMMM.m.p' (e.g. 'alpha-3051.0.0')
#         denotes a "official" build, i.e. a release build to be published.
#       Use any version diverging from the pattern (e.g. 'alpha-3051.0.0-nightly-4302') for development / CI builds.
#       A tag of this version will be created in the scripts repo and pushed upstream.
#
#   2. Architecture (ARCH) of the TARGET OS image ("arm64", "amd64").
#
#
# OPTIONAL INPUT:
#
#   3. coreos-overlay repository tag to use (commit-ish).
#       Optional - use scripts repo sub-modules as-is if not set.
#       This version will be checked out / pulled from remote in the coreos-overlay git submodule.
#       The submodule config will be updated to point to this version before the TARGET SDK tag is created and pushed.
#
#   4. portage-stable repository tag to use (commit-ish).
#       Optional - use scripts repo sub-modules as-is if not set.
#       This version will be checked out / pulled from remote in the portage-stable git submodule.
#       The submodule config will be updated to point to this version before the TARGET SDK tag is created and pushed.
#
# OUTPUT:
#
#   1. Exported container image "flatcar-packages-[ARCH]-[VERSION].tar.gz" with binary packages
#       pushed to buildcache.
#   2. Updated scripts repository
#        - version tag w/ submodules
#        - sdk_container/.repo/manifests/version.txt denotes new FLATCAR OS version
#   3. "./ci-cleanup.sh" with commands to clean up temporary build resources,
#        to be run after this step finishes / when this step is aborted.


set -eu

function packages_build() {
    local version="$1"
    local arch="$2"
    local coreos_git="${3:-}"
    local portage_git="${4:-}"

    source ci-automation/ci_automation_common.sh
    init_submodules

    check_version_string "${version}"

    source sdk_container/.repo/manifests/version.txt
    local sdk_version="${FLATCAR_SDK_VERSION}"

    if [ -n "${coreos_git}" ] ; then
        update_submodule "coreos-overlay" "${coreos_git}"
    fi
    if [ -n "${portage_git}" ] ; then
        update_submodule "portage-stable" "${portage_git}"
    fi

    # Get SDK from either the registry or import from build cache
    # This is a NOP if the image is present locally.
    local sdk_name="flatcar-sdk-${arch}"
    local docker_sdk_vernum="$(vernum_to_docker_image_version "${sdk_version}")"

    docker_image_from_registry_or_buildcache "${sdk_name}" "${docker_sdk_vernum}"
    local sdk_image="$(docker_image_fullname "${sdk_name}" "${docker_sdk_vernum}")"
    echo "docker image rm -f '${sdk_image}'" >> ./ci-cleanup.sh

    # Set name of the packages container for later rename / export
    local vernum="${version#*-}" # remove alpha-,beta-,stable-,lts- version tag
    local docker_vernum="$(vernum_to_docker_image_version "${vernum}")"
    local packages_container="flatcar-packages-${arch}-${docker_vernum}"

    # Build packages; store packages and torcx output in container
    ./run_sdk_container -x ./ci-cleanup.sh -n "${packages_container}" -v "${version}" \
        -C "${sdk_image}" \
        mkdir -p "${CONTAINER_TORCX_ROOT}"
    ./run_sdk_container -n "${packages_container}" -v "${version}" \
        -C "${sdk_image}" \
        ./build_packages --board="${arch}-usr" \
            --torcx_output_root="${CONTAINER_TORCX_ROOT}"

    # run_sdk_container updates the version file, use that version from here on
    source sdk_container/.repo/manifests/version.txt
    local vernum="${FLATCAR_VERSION}"
    local docker_vernum="$(vernum_to_docker_image_version "${vernum}")"
    local packages_image="flatcar-packages-${arch}"

    # generate image + push to build cache
    docker_commit_to_buildcache "${packages_container}" "${packages_image}" "${docker_vernum}"

    update_and_push_version "${version}"
}
# --
