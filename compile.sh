#!/usr/bin/env bash

set -euo pipefail

KERNEL_DIR="$(pwd)"
OUT_DIR="${KERNEL_DIR}/out"
JOBS="$(nproc --all)"

CLANG_DIR="${KERNEL_DIR}/neutron-clang"
CLANG_BIN="${CLANG_DIR}/bin"
ANYKERNEL_DIR="${KERNEL_DIR}/tools/AnyKernel3"

STRING_NAME="Zelinth"
STRING_DEV="Dev"

MAKE_DEV="false"

DEFCONFIG="miru_defconfig"
KERNEL_IMAGE="Image.gz-dtb"
KERNEL_NAME="Miru-${STRING_NAME}"
ARCH="arm64"

GPU_FREQ="710"

VARIANT="dynamic"
DO_CLEAN="true"

export TZ='Asia/Jakarta'

export PATH="${CLANG_BIN}:${PATH}"
export ARCH="${ARCH}"
export SUBARCH="${ARCH}"
export KBUILD_BUILD_USER=miru
export KBUILD_BUILD_HOST=kali

if [ "${MAKE_DEV:-false}" = "true" ]; then
	LOCALVERSION="-${STRING_NAME}-${STRING_DEV}"
else
	LOCALVERSION="-${STRING_NAME}"
fi

MAKE_ARGS=(
	O="${OUT_DIR}"
	ARCH="${ARCH}"
	SUBARCH="${ARCH}"
	LLVM=1
	LLVM_IAS=1
	CC="clang"
	LD="ld.lld"
	AR="llvm-ar"
	NM="llvm-nm"
	HOSTCC="gcc"
	HOSTCXX="g++"
	OBJCOPY="llvm-objcopy"
	OBJDUMP="llvm-objdump"
	STRIP="llvm-strip"
	OBJSIZE="llvm-size"
	READELF="llvm-readelf"
	CROSS_COMPILE="aarch64-linux-gnu-"
	CROSS_COMPILE_ARM32="arm-linux-gnueabi-"
	CLANG_TRIPLE="aarch64-linux-gnu-"
	LOCALVERSION="${LOCALVERSION}"
)

hard_clean() {
	make mrproper
	make clean
}

clean_out() {
	echo "removing folder out"
	rm -rf "${OUT_DIR}"

	mkdir -p "${OUT_DIR}"
	echo "generate out"
}

apply_gpu_freq() {
	restore_gpu_freq
	if [ "${GPU_FREQ}" = "710" ]; then
		echo "Used default GPU clock frequency"
		return
	fi

	local GPU_FREQ_PATCH="${KERNEL_DIR}/patches/overclock/sdm845-gpu-clock-frequency-${GPU_FREQ}.patch"
	if [ -f "${GPU_FREQ_PATCH}" ]; then
		patch -p1 -d "${KERNEL_DIR}" < "${GPU_FREQ_PATCH}"
		echo "Updated GPU clock frequency to ${GPU_FREQ}"
	else
		echo "Failed update GPU clock frequency"
		exit 1
	fi
}

restore_gpu_freq() {
	echo "Restoring stock GPU clock frequency"
	git checkout -- "${KERNEL_DIR}" \
		arch/arm64/boot/dts/qcom/sdm845-v2.dtsi \
		drivers/clk/qcom/gpucc-sdm845.c 2>/dev/null || true
	echo ""
}

apply_fstab_variant() {
	restore_fstab_variant
	if [ "${VARIANT}" = "dynamic" ]; then
		echo "Used default Dynamic partition."
		return
	fi

	local FSTAB_PATCH
	if [ "${VARIANT}" = "se" ]; then
		echo "Applying fstab System Ext"
		FSTAB_PATCH="${KERNEL_DIR}/patches/fstab/sdm845-xiaomi-common_system_ext.patch"
	fi

	if [ "${VARIANT}" = "nse" ]; then
		echo "Applying fstab Non System Ext"
		FSTAB_PATCH="${KERNEL_DIR}/patches/fstab/sdm845-xiaomi-common_non_system_ext.patch"
	fi

	if [ ! -f "${FSTAB_PATCH}" ]; then
		echo "Fstab patch not found: ${FSTAB_PATCH}"
		exit 1
	fi

	patch -p1 -d "${KERNEL_DIR}" < "${FSTAB_PATCH}"

	echo "Fstab ${VARIANT} variant is applied"
}

restore_fstab_variant() {
	if [ "${VARIANT}" = "dynamic" ]; then
		return
	fi
	echo "Restoring default fstab"
	git checkout -- "${KERNEL_DIR}/arch/arm64/boot/dts/qcom/sdm845-xiaomi-common.dtsi" 2>/dev/null || true
}

build_kernel() {
	if [ -f "${OUT_DIR}/.version" ]; then
		rm "${OUT_DIR}/.version"
	fi

	echo "Starting kernel compilation using ${JOBS} cores"

	if make -C "${KERNEL_DIR}" "${MAKE_ARGS[@]}" -j"${JOBS}" 2>&1 | tee "${KERNEL_DIR}/build.log"; then
		echo "Kernel compilation finished successfully."
	else
		echo "Build failed! Check ${OUT_DIR}/build.log for details."
		exit 1
	fi

	if [ ! -f "${OUT_DIR}/arch/${ARCH}/boot/${KERNEL_IMAGE}" ]; then
		echo "Kernel image not found: ${OUT_DIR}/arch/${ARCH}/boot/${KERNEL_IMAGE}"
		echo "Build failed! Check ${OUT_DIR}/build.log for details."
		exit 1
	fi
}

package_anykernel() {
	local variant="${1:-dynamic}"
	local freq="${2:-710}"
	echo "Packaging kernel with AnyKernel3 (${variant}) and GPU freq (${freq})"

	local current_kernel_name="${KERNEL_NAME}"
	if [ "${variant}" = "dynamic" ]; then
		current_kernel_name="${current_kernel_name}-Dynamic-GPU-${freq}"
	elif [ "${variant}" = "nse" ]; then
		current_kernel_name="${current_kernel_name}-NSE-GPU-${freq}"
	elif [ "${variant}" = "se" ]; then
		current_kernel_name="${current_kernel_name}-SE-GPU-${freq}"
	fi

	if [ -d "${ANYKERNEL_DIR}" ]; then
		cd "${ANYKERNEL_DIR}"

		mkdir -p "${OUT_DIR}/zip"

		rm -rf *.zip Image.gz-dtb
		if [ -f "${OUT_DIR}/arch/${ARCH}/boot/${KERNEL_IMAGE}" ]; then
			cp "${OUT_DIR}/arch/${ARCH}/boot/${KERNEL_IMAGE}" "${ANYKERNEL_DIR}/"

			ZIP_NAME="${current_kernel_name}-Beryllium-$(date +%d%m%Y-%H%M).zip"
			zip -r9 "${ZIP_NAME}" * -x "*.git*" "README.md"

			mv "${ZIP_NAME}" "${OUT_DIR}/zip/"
			echo "SUCCESS: File ${ZIP_NAME} is in out/zip/ directory!"
		else
			echo "ERROR: File ${KERNEL_IMAGE} not found!"
			exit 1
		fi
	else
		echo "ERROR: File not found ${ANYKERNEL_DIR}!"
		exit 1
	fi
}

run_release_builds() {
	echo "Starting Variant Release Builds"
	clean_out
	make -C "${KERNEL_DIR}" "${MAKE_ARGS[@]}" "${DEFCONFIG}"

	local -a release_commands=(
		"--dynamic --710"
		"--dynamic --802"
		"--dynamic --820"
		"--dynamic --835"
		"--nse --710"
		"--nse --802"
		"--nse --820"
		"--nse --835"
		"--se --710"
		"--se --802"
		"--se --820"
		"--se --835"
	)

	for release_command in "${release_commands[@]}"; do
		local -a release_args=()
		read -r -a release_args <<< "${release_command}"

		echo "Running build with args: ${release_args[*]}"
		bash "${KERNEL_DIR}/compile.sh" "${release_args[@]}" --dirty
	done
}

main() {
	for arg in "$@"; do
		if [ "${arg}" = "--release" ]; then
			run_release_builds
			exit 0
		fi
	done

	for arg in "$@"; do
		case "${arg}" in
			--710)
			    GPU_FREQ="710"
			    ;;
			--802)
			    GPU_FREQ="802"
			    ;;
			--820)
			    GPU_FREQ="820"
			    ;;
			--835)
			    GPU_FREQ="835"
			    ;;
			--se)
			    VARIANT="se"
			    ;;
			--nse)
			    VARIANT="nse"
			    ;;
			--dynamic)
			    VARIANT="dynamic"
			    ;;
			--clean)
			    DO_CLEAN="true"
			    ;;
			--dirty)
			    DO_CLEAN="false"
			    ;;
		   *)
			echo "Unknown option: ${arg}"
			exit 1
			;;
		esac
	done

	trap 'restore_fstab_variant; restore_gpu_freq' EXIT

	if [ "${DO_CLEAN}" = "true" ]; then
		hard_clean
		clean_out
	fi

	make -C "${KERNEL_DIR}" "${MAKE_ARGS[@]}" "${DEFCONFIG}"
	apply_gpu_freq
	apply_fstab_variant
	build_kernel
	package_anykernel "${VARIANT}" "${GPU_FREQ}"
}

main "$@"
