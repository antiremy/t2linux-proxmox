#!/bin/bash
# Build Proxmox kernel .debs with t2linux patches.
# Run on Debian trixie (or Proxmox VE 9) amd64 as root, or via ./docker-build.sh.
# Usage: ./build.sh            full build, debs land in ./out
#        ./build.sh prepare    only fetch and apply patches
#        ./build.sh check      apply patches and compile the folders they touch
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-$ROOT/work}
OUT=${OUT:-$ROOT/out}
MODE=${1:-deb}
source "$ROOT/config.env"

install_deps() {
	export DEBIAN_FRONTEND=noninteractive
	apt-get update
	apt-get install -y --no-install-recommends \
		asciidoc-base automake autoconf bc bindgen bison build-essential ca-certificates \
		ccache cpio debhelper dh-python dwarves file flex gawk git kmod libdw-dev libelf-dev \
		libiberty-dev libnuma-dev libslang2-dev libssl-dev libtool lintian lz4 patch \
		python3-dev python3-minimal rsync rustc rust-src rustfmt rust-clippy \
		sphinx-common xmlto zlib1g-dev zstd
}

fetch_sources() {
	mkdir -p "$WORK"
	cd "$WORK"
	[ -d pve-kernel ] || git clone https://git.proxmox.com/git/pve-kernel.git
	[ -d t2-patches ] || git clone https://github.com/t2linux/linux-t2-patches.git t2-patches

	git -C t2-patches fetch -q origin
	git -C t2-patches checkout -q "$T2_PATCHES_REF"

	cd pve-kernel
	git fetch -q origin
	git reset -q --hard "$PVE_KERNEL_REF"
	git clean -qfdx
	git submodule update --init --depth 1 submodules/ubuntu-kernel
	git submodule update --init --recursive submodules/zfsonlinux
}

is_skipped() {
	local name=$1 s
	for s in $T2_SKIP; do
		[ "$s" = "$name" ] && return 0
	done
	return 1
}

add_t2() {
	cd "$WORK/pve-kernel"
	local p name
	for p in "$WORK"/t2-patches/*.patch; do
		name=$(basename "$p")
		is_skipped "$name" && continue
		cp "$p" patches/kernel/
	done
	local extra
	for extra in $T2_EXTRA; do
		git -C "$WORK/t2-patches" show "$extra" > "patches/kernel/${extra#*:}"
	done
	cp "$ROOT"/patches/*.patch patches/kernel/
	cat "$ROOT/config-t2.opts" >> debian/rules.d/config-amd64.opts
	sed -i "s/^\(EXTRAVERSION=.*-pve\)$/\1$KERNEL_SUFFIX/" Makefile
	grep -q "^EXTRAVERSION=.*-pve$KERNEL_SUFFIX$" Makefile
	sed -i "1 s/^\(proxmox-kernel-[^ ]* (\)$PVE_KERNEL_VERSION)/\1$PVE_KERNEL_VERSION+t2.$T2_REL)/" debian/changelog
	grep -q "($PVE_KERNEL_VERSION+t2.$T2_REL)" debian/changelog
	# Proxmox release checks; they compare against stock builds and do not apply here
	rm -f abi-prev-* fwlist-previous-*
}

use_ccache() {
	[ -d /usr/lib/ccache ] || return 0
	export PATH=/usr/lib/ccache:$PATH
	export CCACHE_DIR=${CCACHE_DIR:-$WORK/ccache}
	# The build folder name holds the kernel version, so leave paths out of the hash
	export CCACHE_BASEDIR=$WORK CCACHE_NOHASHDIR=1
	export CCACHE_COMPILERCHECK=content CCACHE_MAXSIZE=${CCACHE_MAXSIZE:-6G}
	ccache -z
}

t2_dirs() {
	cat "$WORK"/pve-kernel/patches/kernel/[1-9]*.patch |
		sed -n 's|^+++ b/\(.*\)/[^/]*\.c$|\1/|p' | sort -u
}

compile_check() {
	local opts=$WORK/pve-kernel/debian/rules.d
	cd "$WORK"/pve-kernel/proxmox-kernel-*/ubuntu-kernel
	cat "$opts/config-common.opts" "$opts/config-amd64.opts" | xargs scripts/config
	make olddefconfig
	make -j"$(nproc)" prepare modules_prepare
	t2_dirs | xargs make -j"$(nproc)"
	echo "T2 code compiles."
}

main() {
	[ "$(id -u)" = 0 ] && install_deps
	use_ccache
	fetch_sources
	add_t2
	cd "$WORK/pve-kernel"
	make PKG_REV_EXTRA="+t2.$T2_REL" ubuntu-kernel.prepared

	case $MODE in
	prepare) echo "All patches applied."; return ;;
	check) compile_check; return ;;
	esac

	compile_check
	cd "$WORK/pve-kernel"
	make PKG_REV_EXTRA="+t2.$T2_REL" deb
	command -v ccache >/dev/null && ccache -s
	mkdir -p "$OUT"
	cp -v ./*.deb "$OUT"/
}

main
