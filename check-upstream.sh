#!/bin/bash
# Point config.env at the newest Proxmox kernel release.
# Exit 0: nothing new. Exit 10: config.env updated. Exit 20: new Linux version, needs a human.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
source "$ROOT/config.env"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

git clone -q --bare --single-branch -b "$PVE_KERNEL_BRANCH" \
	https://git.proxmox.com/git/pve-kernel.git "$TMP/pve"
cd "$TMP/pve"

new=$(git log -1 --format=%H --grep='^bump version to ' "$PVE_KERNEL_BRANCH")
version=$(git log -1 --format=%s "$new" | sed 's/^bump version to //')

if git merge-base --is-ancestor "$new" "$PVE_KERNEL_REF"; then
	echo "Up to date with $version."
	exit 0
fi

majmin() {
	git show "$1:Makefile" | awk -F= '/^KERNEL_MAJ=/{a=$2} /^KERNEL_MIN=/{b=$2} END{print a"."b}'
}

old_mm=$(majmin "$PVE_KERNEL_REF")
new_mm=$(majmin "$new")
if [ "$old_mm" != "$new_mm" ]; then
	echo "Proxmox moved from Linux $old_mm to $new_mm ($version)."
	echo "Pick a new T2_PATCHES_REF and update config.env by hand."
	exit 20
fi

sed -i.bak \
	-e "s|^PVE_KERNEL_VERSION=.*|PVE_KERNEL_VERSION=$version|" \
	-e "s|^PVE_KERNEL_REF=.*|PVE_KERNEL_REF=$new|" \
	-e "s|^T2_REL=.*|T2_REL=1|" \
	"$ROOT/config.env"
rm -f "$ROOT/config.env.bak"
echo "Updated to $version ($new)."
echo "version=$version" >> "${GITHUB_OUTPUT:-/dev/null}"
exit 10
