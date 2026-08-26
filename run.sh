#!/bin/sh
# Run a command inside the toolchain container. With no arguments, opens a shell.
#
# The repository is mounted at /foss/designs and PDK_ROOT points at the pinned
# PDK fetched by `make pdk`, not at the PDK bundled in the image.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
IMAGE=${OSIC_IMAGE:-hpretl/iic-osic-tools:2026.07}

if command -v podman >/dev/null 2>&1; then
    ENGINE=podman
elif command -v docker >/dev/null 2>&1; then
    ENGINE=docker
else
    echo "error: neither podman nor docker found on PATH" >&2
    exit 1
fi

# Build artifacts land in the bind-mounted repo, so the container process has to
# write as the host user. Docker takes the uid directly. Rootless podman maps the
# host user to container root by default, which leaves the image's uid 1000 user
# unable to write the mount; keep-id maps the host uid to itself instead.
if [ "$ENGINE" = docker ]; then
    USERFLAG="-u $(id -u):$(id -g)"
else
    USERFLAG="--userns=keep-id"
fi

# Only allocate a TTY when there is one, so this works in CI.
if [ -t 0 ]; then TTY="-it"; else TTY="-i"; fi

if [ "$#" -eq 0 ]; then
    set -- bash
fi

# Cap container memory so an OOM inside a tool gets contained to the
# container's cgroup instead of the host OOM killer picking off arbitrary
# session processes. KLayout DRC has hit this and once took out
# pipewire and systemd --user; see docs/explanation/known-issues.md. Override
# or blank out either variable to disable the cap.
MEMORY_LIMIT="${MEMORY_LIMIT:-12g}"
MEMORY_SWAP_LIMIT="${MEMORY_SWAP_LIMIT:-14g}"
MEMFLAGS=""
[ -n "$MEMORY_LIMIT" ] && MEMFLAGS="$MEMFLAGS --memory=$MEMORY_LIMIT"
[ -n "$MEMORY_SWAP_LIMIT" ] && MEMFLAGS="$MEMFLAGS --memory-swap=$MEMORY_SWAP_LIMIT"

# The image entrypoint starts VNC or X11 unless --skip comes first, in which
# case it just execs the command.
# shellcheck disable=SC2086
exec "$ENGINE" run --rm $TTY $USERFLAG $MEMFLAGS \
    -v "$ROOT:/foss/designs:z" \
    -w /foss/designs \
    -e PDK_ROOT=/foss/designs/pdk \
    -e PDK="${PDK:-gf180mcuD}" \
    -e SLOT="${SLOT:-1x1}" \
    -e SCL="${SCL:-gf180mcu_fd_sc_mcu7t5v0}" \
    -e PAD="${PAD:-gf180mcu_ocd_io}" \
    -e SRAM="${SRAM:-gf180mcu_ocd_ip_sram}" \
    -e TOP="${TOP:-core_v_mcu}" \
    -e MODE="${MODE:-both}" \
    -e LIB_CORNER="${LIB_CORNER:-ss_125C_3v00}" \
    -e CLOCK_PERIOD_NS="${CLOCK_PERIOD_NS:-200}" \
    -e TIMEOUT_NS="${TIMEOUT_NS:-}" \
    "$IMAGE" --skip "$@"
