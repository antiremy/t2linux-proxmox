#!/bin/bash
# Run build.sh in a Debian trixie container. Sources live in a Docker volume
# because the kernel tree needs a case-sensitive filesystem.
# Usage: ./docker-build.sh [prepare]
set -euo pipefail
cd "$(dirname "$0")"
PLATFORM=${PLATFORM:-linux/amd64}
docker run --rm -t --platform "$PLATFORM" \
	-v "$PWD":/repo -v t2pve-work:/work -v t2pve-ccache:/ccache \
	-e WORK=/work -e CCACHE_DIR=/ccache -e OUT=/repo/out \
	debian:trixie /repo/build.sh "$@"
