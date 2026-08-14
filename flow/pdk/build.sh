#!/bin/sh
# Copyright 2026 Yusef Karim
# Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Build the pinned GF180MCU PDK from source, with the libraries the prebuilt
# distribution leaves out. Runs inside the toolchain container; invoke it as
# `make pdk`.
#
# Why this exists rather than `ciel enable`: the prebuilt PDK that ciel
# downloads carries only the five gf180mcu_fd_* libraries. The pinned open_pdks
# commit knows about the others (libs.tech/librelane ships configs for them and
# .config/nodeinfo.json pins each to a commit) but this distribution did not
# build them. Ticket 15 wanted three of them:
#
#   gf180mcu_ocd_ip_sram     2.6x denser SRAM than the foundry macro
#   gf180mcu_ocd_io          pad cells with a core supply separate from the IO
#   gf180mcu_as_sc_mcu7t3v3  3.3 V-native thin-oxide standard cells
#
# Why this rather than `ciel build`: ciel hardcodes its configure flags, and the
# one flag that matters here is --with-gf180mcu-variants. open_pdks builds all
# four variants by default, and building gf180mcuB segfaults magic 8.3.678 part
# way through writing gf180mcu_ef_io__bi_t.lef, which kills the whole build.
# Variants A, C and D are unaffected. This design is gf180mcuD only, so the
# three other variants are pure cost, and not building them both dodges the
# crash and halves the time. It also means a mistyped variant name no longer
# resolves to a real populated directory, which the map lists as a hazard.
#
# The layout ciel uses is kept, so `ciel enable` and `ciel ls` still work.

set -eu

PDK=${PDK:-gf180mcuD}
PDK_COMMIT=${PDK_COMMIT:?PDK_COMMIT must be set}
PDK_JOBS=${PDK_JOBS:-1}
PDK_ROOT=${PDK_ROOT:-/foss/designs/pdk}

OPEN_PDKS_REPO=https://github.com/RTimothyEdwards/open_pdks

# C and D differ in top-metal thickness and therefore in DRC rules, so a cell
# verified under one deck is not automatically clean under the other. Assert
# rather than trust, the same way flow/synth/area.sh does.
[ "$PDK" = gf180mcuD ] || { echo "error: PDK is $PDK, this design is gf180mcuD only" >&2; exit 1; }

# open_pdks names variants by their trailing letter.
VARIANT=$(printf '%s' "$PDK" | sed 's/^gf180mcu//')

BUILD=$PDK_ROOT/ciel/gf180mcu/build/$PDK_COMMIT
OPDKS=$BUILD/open_pdks
VERSIONS=$PDK_ROOT/ciel/gf180mcu/versions/$PDK_COMMIT

# Each --enable flag names the library it installs. Anything not enabled is
# disabled explicitly: open_pdks defaults some of these on, and the resulting
# PDK is silently missing a library rather than failing, so the disables are
# load-bearing rather than decoration.
CONFIG_FLAGS="--enable-gf180mcu-pdk \
    --with-reference \
    --with-gf180mcu-variants=$VARIANT \
    --enable-primitive-gf180mcu \
    --enable-io-gf180mcu \
    --enable-sram-gf180mcu \
    --enable-sc-7t5v0-gf180mcu \
    --enable-sc-9t5v0-gf180mcu \
    --enable-ocd-sram-gf180mcu \
    --enable-ocd-io-gf180mcu \
    --enable-avalon-sc-gf180mcu \
    --disable-osu-sc-gf180mcu \
    --disable-re-efuse-gf180mcu \
    --disable-alpha-gf180mcu"

mkdir -p "$BUILD"

if [ ! -d "$OPDKS/.git" ]; then
    echo "==> cloning open_pdks at $PDK_COMMIT"
    git clone -q "$OPEN_PDKS_REPO" "$OPDKS"
    git -C "$OPDKS" checkout -q "$PDK_COMMIT"
else
    echo "==> reusing open_pdks clone at $OPDKS"
    git -C "$OPDKS" checkout -q "$PDK_COMMIT"
fi

echo "==> configuring ($PDK only)"
( cd "$OPDKS" && ./configure $CONFIG_FLAGS >"$BUILD/config.log" 2>&1 ) || {
    echo "error: configure failed, see $BUILD/config.log" >&2; exit 1; }

# open_pdks clones each library's source repo on first use, at the commit
# .config/nodeinfo.json pins, so this step needs network access.
#
# The retry is not defensive padding. The container's magic is 8.3.678 where
# this open_pdks commit expects 8.3.674, and it segfaults intermittently in the
# io stage, while reading the efabless custom pad cell gf180mcu_ef_io and
# writing its LEF back out. It is genuinely nondeterministic: the same variant
# from the same sources crashes on one run and completes on the next, and it
# has been seen on variants B and D. Nothing in the inputs changes between
# attempts, so retrying is the available fix short of building magic 8.3.674.
#
# Each attempt starts from clean staging rather than resuming, because a PDK
# assembled on top of a half-written cell database is the one outcome worse
# than a failed build.
#
# Run make in the gf180mcu subdirectory rather than at the top level. The top
# level reaches it through `tech-%: %`, whose recipe is `${MAKE} -j$(nproc)
# all` with the job count hardcoded, so a -j passed from outside is ignored and
# the build always runs at however many cores the machine has. Going straight
# to the subdirectory is what makes PDK_JOBS mean anything.
PDK_BUILD_ATTEMPTS=${PDK_BUILD_ATTEMPTS:-4}
echo "==> building (about ten minutes per attempt)"
attempt=1
while :; do
    rm -rf "$OPDKS/gf180mcu/$PDK"
    if ( cd "$OPDKS/gf180mcu" && make -j"$PDK_JOBS" all >"$BUILD/make.log" 2>&1 ); then
        break
    fi
    cp "$BUILD/make.log" "$BUILD/make.attempt$attempt.log"
    if ! grep -q 'exit code: -11' "$BUILD/make.log"; then
        echo "error: build failed, and not with the known magic segfault." >&2
        echo "       see $BUILD/make.log" >&2
        exit 1
    fi
    if [ "$attempt" -ge "$PDK_BUILD_ATTEMPTS" ]; then
        echo "error: magic segfaulted on all $PDK_BUILD_ATTEMPTS attempts." >&2
        echo "       see $BUILD/make.attempt*.log" >&2
        exit 1
    fi
    echo "    magic segfaulted on attempt $attempt, retrying from clean staging"
    attempt=$((attempt + 1))
done
[ "$attempt" -eq 1 ] || echo "    (took $attempt attempts)"

# `make install` cannot be used for a single variant: install-B depends on
# install-A, C on B and D on C, so install-D drags in three variants that were
# never built and dies on the first missing directory. The chain is hardcoded
# and ignores VARIANTS. So run the one install this build wants directly.
#
# -link_from none is the difference that matters. The Makefile would pass
# ${SHARED_PDKS_PATH}/gf180mcuA here, because it assumes D's files can be links
# back to variant A's. With A unbuilt those links would all dangle, so ask for
# real files instead. This is also what makes the result self-contained.
echo "==> staging"
( cd "$OPDKS/gf180mcu" && ../common/staging_install.py -std_format \
    -source "$OPDKS/gf180mcu/$PDK" \
    -finalpath "$BUILD/$PDK" \
    -variable PDKPATH \
    -link_from none >"$BUILD/install.log" 2>&1 ) || {
    echo "error: install failed, see $BUILD/install.log" >&2; exit 1; }

[ -d "$BUILD/$PDK/libs.ref" ] || { echo "error: no $PDK/libs.ref under $BUILD" >&2; exit 1; }

# Ticket 20: two Liberty fields on gf180mcu_ocd_ip_sram__sram1024x8m8wm1 are
# leftovers from the foundry macro this OCD library was derived from. Patch
# the staged tree so the fix survives every rebuild rather than being a
# one-time hand edit.
sh "$(dirname "$0")/patch_ocd_sram.sh" "$BUILD/$PDK"

echo "==> installing to $VERSIONS/$PDK"
rm -rf "$VERSIONS/$PDK"
mkdir -p "$VERSIONS"
cp -a "$BUILD/$PDK" "$VERSIONS/$PDK"

# Point pdk/<variant> at the build, the way `ciel enable` would. Only the one
# variant is linked: the others were never built, so a wrong variant name now
# fails instead of resolving to a populated directory.
for v in gf180mcuA gf180mcuB gf180mcuC gf180mcuD; do
    rm -f "$PDK_ROOT/$v"
done
ln -s "ciel/gf180mcu/versions/$PDK_COMMIT/$PDK" "$PDK_ROOT/$PDK"

echo
echo "==> $PDK libraries:"
ls "$PDK_ROOT/$PDK/libs.ref"
