#!/bin/bash
# Add the kernel in ./out to the apt repo stored on the "apt" GitHub release.
# Needs: gh (with GH_TOKEN), gpg with the signing key imported, dpkg-dev, apt-utils.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-$ROOT/out}
KEEP=${KEEP:-3}
TAG=apt
REPO=$(mktemp -d)
trap 'rm -rf "$REPO"' EXIT

field() {
	dpkg-deb -f "$1" "$2"
}

make_meta() {
	local kernel_deb=$1 kvname version dir
	kvname=$(field "$kernel_deb" Package | sed 's/^proxmox-kernel-//')
	version=$(field "$kernel_deb" Version)
	dir=$(mktemp -d)
	mkdir -p "$dir/DEBIAN"
	sed -e "s/@KVNAME@/$kvname/g" -e "s/@VERSION@/$version/g" \
		"$ROOT/meta/control" > "$dir/DEBIAN/control"
	sed -e "s/@KVNAME@/$kvname/g" "$ROOT/meta/postinst" > "$dir/DEBIAN/postinst"
	cp "$ROOT/meta/postrm" "$dir/DEBIAN/postrm"
	chmod 755 "$dir/DEBIAN/postinst" "$dir/DEBIAN/postrm"
	dpkg-deb --build --root-owner-group "$dir" "$REPO/proxmox-kernel-t2_${version}_amd64.deb"
	rm -rf "$dir"
}

fetch_repo() {
	gh release view "$TAG" >/dev/null 2>&1 ||
		gh release create "$TAG" --title "apt repository" --latest=false \
			--notes "Apt repository files. See the README for how to add it."
	gh release download "$TAG" -D "$REPO" -p '*.deb' 2>/dev/null || true
}

add_new() {
	local kernel_deb
	kernel_deb=$(ls "$OUT"/proxmox-kernel-*-pve_*.deb)
	cp "$kernel_deb" "$OUT"/proxmox-headers-*-pve_*.deb "$REPO"/
	make_meta "$kernel_deb"
}

prune() {
	cd "$REPO"
	local f
	for f in *.deb; do
		echo "$(field "$f" Package) $(field "$f" Version) $f"
	done | sort -k1,1 -k2,2Vr | awk 'seen[$1]++ {print $3}' | xargs -r rm -v

	ls proxmox-kernel-*-pve_*.deb | sed 's/^proxmox-kernel-//; s/_.*//' | sort -Vr |
		tail -n +"$((KEEP + 1))" | while read -r kv; do
		rm -v "proxmox-kernel-${kv}_"*.deb "proxmox-headers-${kv}_"*.deb
	done
}

index() {
	cd "$REPO"
	dpkg-scanpackages --multiversion . > Packages
	gzip -kf Packages
	apt-ftparchive release . > Release
	gpg --batch --yes --armor --detach-sign -o Release.gpg Release
	gpg --batch --yes --clearsign -o InRelease Release
}

upload() {
	cd "$REPO"
	gh release upload "$TAG" ./* --clobber
	gh release view "$TAG" --json assets --jq '.assets[].name' | while read -r name; do
		[ -e "$name" ] || gh release delete-asset "$TAG" "$name" -y
	done
}

fetch_repo
add_new
prune
index
upload
