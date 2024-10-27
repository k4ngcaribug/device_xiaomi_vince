#!/bin/bash
#
# Copyright (C) 2016 The CyanogenMod Project
# Copyright (C) 2017-2020 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#

set -e

DEVICE=vince
VENDOR=xiaomi

# Load extract_utils and do some sanity checks
MY_DIR="${BASH_SOURCE%/*}"
if [[ ! -d "${MY_DIR}" ]]; then MY_DIR="${PWD}"; fi

ANDROID_ROOT="${MY_DIR}/../../.."

HELPER="${ANDROID_ROOT}/tools/extract-utils/extract_utils.sh"
if [ ! -f "${HELPER}" ]; then
    echo "Unable to find helper script at ${HELPER}"
    exit 1
fi
source "${HELPER}"

# Default to sanitizing the vendor folder before extraction
CLEAN_VENDOR=true

KANG=
SECTION=

while [ "${#}" -gt 0 ]; do
    case "${1}" in
        -n | --no-cleanup )
                CLEAN_VENDOR=false
                ;;
        -k | --kang )
                KANG="--kang"
                ;;
        -s | --section )
                SECTION="${2}"; shift
                CLEAN_VENDOR=false
                ;;
        * )
                SRC="${1}"
                ;;
    esac
    shift
done

if [ -z "${SRC}" ]; then
    SRC="adb"
fi

function blob_fixup() {
    case "${1}" in
        system_ext/etc/init/dpmd.rc)
            sed -i "s|/system/product/bin/|/system/system_ext/bin/|g" "${2}"
            ;;
        system_ext/etc/permissions/com.qti.dpmframework.xml \
        | system_ext/etc/permissions/dpmapi.xml \
        | system_ext/etc/permissions/telephonyservice.xml )
            sed -i "s|/system/product/framework/|/system/system_ext/framework/|g" "${2}"
            ;;
        system_ext/etc/permissions/embms.xml)
            sed -i "s|/product/framework/|/system_ext/framework/|g" "${2}"
            ;;
        system_ext/etc/permissions/qcrilhook.xml)
            sed -i 's|/product/framework/qcrilhook.jar|/system_ext/framework/qcrilhook.jar|g' "${2}"
            ;;
        system_ext/lib64/libdpmframework.so)
            grep -q "libcutils_shim.so" "${2}" || "${PATCHELF}" --add-needed "libcutils_shim.so" "${2}"
            ;;
        system_ext/lib64/lib-imsvideocodec.so)
            grep -q "libgui_shim.so" "${2}" || "${PATCHELF}" --add-needed "libgui_shim.so" "${2}"
            ;;
        vendor/bin/pm-service)
            grep -q "libutils-v33.so" "${2}" || "${PATCHELF}" --add-needed "libutils-v33.so" "${2}"
            ;;
        vendor/etc/init/qcrild.rc)
            sed -i '4d;11d' "${2}"
            ;;
        vendor/etc/init/dataqti.rc)
            sed -i '19d' "${2}"
            ;;
        vendor/usr/keylayout/uinput-fpc.kl|vendor/usr/keylayout/uinput-goodix.kl)
            sed -i '11d' "${2}"
            ;;
        vendor/lib64/libvendor.goodix.hardware.fingerprint@1.0-service.so)
            "${PATCHELF_0_17_2}" --remove-needed "libprotobuf-cpp-lite.so" "${2}"
            ;;
	vendor/lib64/libvendor.goodix.hardware.fingerprint@1.0.so)
            "${PATCHELF_0_17_2}" --replace-needed "libhidlbase.so" "libhidlbase-v32.so" "${2}"
	        ;;
    esac

    # For all ELF files
    if [[ "${1}" =~ ^.*(\.so|\/bin\/.*)$ ]]; then
        "${PATCHELF_0_17_2}" --replace-needed "libstdc++.so" "libstdc++_vendor.so" "${2}"
    fi
}

# Initialize the helper
setup_vendor "${DEVICE}" "${VENDOR}" "${ANDROID_ROOT}" false "${CLEAN_VENDOR}"

extract "${MY_DIR}/proprietary-files.txt" "${SRC}" "${KANG}" --section "${SECTION}"


# RIL
for v in 1.{0..2}; do
    sed -i "s|android.hardware.radio.config@${v}.so|android.hardware.radio.c_shim@${v}.so|g" "${DEVICE_BLOB_ROOT}"/vendor/lib64/libril-qc-hal-qmi.so"
done

"${MY_DIR}/setup-makefiles.sh"
