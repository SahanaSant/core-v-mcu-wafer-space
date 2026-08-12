#!/bin/sh
# Run a command inside the toolchain container. With no arguments, opens a shell.
#
# The repository is mounted at /foss/designs and PDK_ROOT points at the pinned
# PDK fetched by `make pdk`, not at the PDK bundled in the image.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
IMAGE=${OSIC_IMAGE:-hpretl/iic-osic-tools:2026.07}

if command -v podman >/dev/null 2>&1; then
    ENGINE=podman
elif command -v docker >/dev/null 2>&1; then
    ENGINE=docker
else
    echo "error: neither podman nor docker found on PATH" >&2
    exit 1
fi

# Docker needs the host uid mapped in so build artifacts are not root-owned.
# Podman already maps the invoking user into the container namespace.
if [ "$ENGINE" = docker ]; then
    USERFLAG="-u $(id -u):$(id -g)"
else
    USERFLAG=""
fi

# Only allocate a TTY when there is one, so this works in CI.
if [ -t 0 ]; then TTY="-it"; else TTY="-i"; fi

if [ "$#" -eq 0 ]; then
    set -- bash
fi

# shellcheck disable=SC2086
exec "$ENGINE" run --rm $TTY $USERFLAG \
    -v "$ROOT:/foss/designs:z" \
    -w /foss/designs \
    -e PDK_ROOT=/foss/designs/pdk \
    -e PDK="${PDK:-gf180mcuD}" \
    -e SLOT="${SLOT:-1x1}" \
    -e SCL="${SCL:-gf180mcu_fd_sc_mcu7t5v0}" \
    -e PAD="${PAD:-gf180mcu_fd_io}" \
    -e SRAM="${SRAM:-gf180mcu_fd_ip_sram}" \
    "$IMAGE" "$@"
