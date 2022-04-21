#!/bin/bash
# Copyright (c) 2022 The Flatcar Maintainers.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

set -euo pipefail

# Test execution script for the AWS vendor image.
# This script is supposed to run in the mantle container.

work_dir="$1"; shift
arch="$1"; shift
vernum="$1"; shift
tapfile="$1"; shift

# $@ now contains tests / test patterns to run

source ci-automation/ci_automation_common.sh
source sdk_lib/sdk_container_common.sh

mkdir -p "${work_dir}"
cd "${work_dir}"

AWS_BOARD="${arch}-usr"
AWS_CHANNEL="$(get_git_channel)"
if [[ "${AWS_CHANNEL}" = 'developer' ]]; then
    AWS_CHANNEL='alpha'
fi
AWS_IMAGE_NAME="ci-${vernum}"
AWS_INSTANCE_TYPE_VAR="AWS_${arch}_INSTANCE_TYPE"
AWS_INSTANCE_TYPE="${!AWS_INSTANCE_TYPE_VAR}"
MORE_INSTANCE_TYPES_VAR="AWS_${arch}_MORE_INSTANCE_TYPES"
MORE_INSTANCE_TYPES=( ${!MORE_INSTANCE_TYPES_VAR} )

if [[ -z "${AWS_OFFER}" ]]; then
    AWS_OFFER='basic'
fi

case "${AWS_OFFER}" in
    basic)
        AWS_OEM_SUFFIX=''
        ;;
    pro)
        AWS_OEM_SUFFIX='_pro'
        ;;
    *)
        echo "1..1" > "${tapfile}"
        echo "not ok - all AWS tests" >> "${tapfile}"
        echo "  ---" >> "${tapfile}"
        echo "  ERROR: Invalid offer '${AWS_OFFER}', should be 'basic' or 'pro'." | tee -a "${tapfile}"
        echo "  ..." >> "${tapfile}"
        exit 1
        ;;
esac

testscript="$(basename "$0")"

if [[ "${AWS_AMI_ID}" == "" ]]; then
    echo "++++ ${testscript}: downloading flatcar_production_ami_vmdk${AWS_OEM_SUFFIX}_image.vmdk.bz2 for ${vernum} (${arch}) ++++"
    copy_from_buildcache "images/${arch}/${vernum}/flatcar_production_ami_vmdk${AWS_OEM_SUFFIX}_image.vmdk.bz2" .

    lbunzip2 "${work_dir}/flatcar_production_ami_vmdk${AWS_OEM_SUFFIX}_image.vmdk.bz2"

    AWS_BUCKET="flatcar-kola-ami-import-${AWS_REGION}"
    trap 'ore -d aws delete --region="${AWS_REGION}" --name="${AWS_IMAGE_NAME}" --ami-name="${AWS_IMAGE_NAME}" --file="${work_dir}/flatcar_production_ami_vmdk${AWS_OEM_SUFFIX}_image.vmdk" --bucket "s3://${AWS_BUCKET}/${AWS_BOARD}/"' EXIT
    ore aws initialize --region="${AWS_REGION}" --bucket "${AWS_BUCKET}"
    AWS_AMI_ID=$(ore aws upload --force --region="${AWS_REGION}" --name="${AWS_IMAGE_NAME}" --ami-name="${AWS_IMAGE_NAME}" --ami-description="Flatcar Test ${AWS_IMAGE_NAME}" --file="${work_dir}/flatcar_production_ami_vmdk${AWS_OEM_SUFFIX}_image.vmdk" --bucket  "s3://${AWS_BUCKET}/${AWS_BOARD}/" | jq -r .HVM)
    echo "Created new AMI ${AWS_AMI_ID} (will be removed after testing)"
fi

run_aws_kola_test() {
    local instance_type="${1}"
    local instance_tapfile="${2}"

    timeout --signal=SIGQUIT 6h \
        kola run \
         --board="${AWS_BOARD}" \
         --basename="${AWS_IMAGE_NAME}" \
         --channel="${AWS_CHANNEL}" \
         --offering="${AWS_OFFER}" \
         --parallel="${AWS_PARALLEL}" \
         --platform=aws \
         --aws-ami="${AWS_AMI_ID}" \
         --aws-region="${AWS_REGION}" \
         --aws-type="${instance_type}" \
         --aws-iam-profile="${AWS_IAM_PROFILE}" \
         --tapfile="${instance_tapfile}" \
         --torcx-manifest=../torcx_manifest.json \
         "${@}"
}

cl_internet_included="$(kola list --platform=aws --filter "${@}" | { grep cl.internet || : ; } )"
run_more_tests=0
if [[ -n "${cl_internet_included}" ]] && [[ "${#MORE_INSTANCE_TYPES[@]}" -gt 0 ]]; then
    run_more_tests=1
fi
if [[ "${run_more_tests}" -eq 1 ]]; then
    for instance_type in "${MORE_INSTANCE_TYPES[@]}"; do
        (
            OUTPUT=$(run_aws_kola_test "${instance_type}" "validate_${instance_type}.tap" 'cl.internet' 2>&1 || :)
            printf "=== START $INSTANCE ===\n%s\n=== END $INSTANCE ===\n" "$(sed -e 's/^/prefix: /g' <<<"${foo}")"
        ) &
    done
fi

# these are set in ci-config.env
export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY

set -x

run_aws_kola_test "${AWS_INSTANCE_TYPE}" "${tapfile}" "${@}"

set +x

if [[ "${run_more_tests}" -eq 1 ]]; then
    wait
    cat validate_*.tap >>"${tapfile}"
fi
