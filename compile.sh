#!/bin/bash

set -euo pipefail

# Variable
KERNEL_DIR="$(pwd)"
OUT_DIR="${KERNEL_DIR}/out"
JOBS="$(nproc --all)"

# Toolchain
CLANG_DIR="${KERNEL_DIR}/llvm-23.1.1-x86_64"
CLANG_BIN="${CLANG_DIR}/bin"

# Path
DEFCONFIG="miru_defconfig"
KERNEL_IMAGE="Image.gz-dtb"

# String
STRING_NAME="Zelinth"

# Arsitektur
ARCH="arm64"

# Export Environment
export PATH="${CLANG_BIN}:${PATH}"
export ARCH="${ARCH}"
export SUBARCH="${ARCH}"
export KBUILD_BUILD_USER=miru
export KBUILD_BUILD_HOST=meuira

# Make Argument
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
	LOCALVERSION="-${STRING_NAME}"
)

# Step One: Cleannig Out
clean_out() {
	echo "removing folder out"
	rm -rf "${OUT_DIR}"

	mkdir -p "${OUT_DIR}"
	echo "generate out"
}

# Make Cleaning Out
clean_out
echo "Cleaning Success"

# Step Two: Defconfig Generate
make -C "${KERNEL_DIR}" "${MAKE_ARGS[@]}" "${DEFCONFIG}"
echo "Defconfig generated successfully"

# Step Three: Build Kernel
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

# Make Build Kernel
build_kernel
