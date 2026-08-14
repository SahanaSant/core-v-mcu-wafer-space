#!/bin/sh
# Copyright 2026 Yusef Karim
# Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Correct two mechanical Liberty defects in gf180mcu_ocd_ip_sram found by
# ticket 20, scoped to sram1024x8m8wm1, the only OCD SRAM size this design
# instantiates (ticket 19). Both are reproduced identically across all ten
# corners and both trace to the same cause: the OCD library derives this
# file from gf180mcu_fd_ip_sram__sram512x8m8wm1 and two fields were carried
# over unedited.
#
#   - Liberty `area` is the foundry 512x8 macro's area (209400.2768 um2),
#     not this macro's. The OCD layout is denser; LEF SIZE gives the real
#     number, computed here rather than hardcoded so a PDK rebuild that
#     changes the layout is reflected automatically instead of silently
#     patched with a stale constant.
#   - `memory() { address_width }` reads 9 against a 10-bit `bus(A)`
#     (1024 = 2^10), also a 512-deep leftover.
#
# What this deliberately leaves alone: the Verilog gate-level model's
# specify-block CLK->Q delay (`ta`), which ticket 20 also found to be
# optimistic. Its own header comment already documents why a better number
# isn't available locally: the CSV row it would need
# (specs/5_AC_Characteristics2.csv, Tah/Tal at the ss_n40C corner) is
# corrupted, reporting the same value as the ff_n40C corner, which is
# monotonically impossible. STA does not read this file: it signs off
# against the Liberty timing arcs, which are the foundry 512x8 part's own
# characterised numbers used as a pessimistic proxy (ticket 11, ticket 19).
# Patching the simulation-only delay would mean fabricating a number from
# data already known to be bad; ticket 20 leaves it as shipped and defers
# to real characterisation (ORConf, September 2026) rather than inventing
# a substitute. See ticket 20's Answer for the full decision.
#
# Usage: patch_ocd_sram.sh <PDK-stage-dir>, e.g. $BUILD/$PDK. Called from
# flow/pdk/build.sh after staging and before the PDK is copied to
# versions/, so `make pdk` reproduces the fix on every rebuild rather than
# a one-time hand edit that a rebuild would silently discard.

set -eu

STAGE=${1:?usage: patch_ocd_sram.sh <PDK-stage-dir>}

LIBDIR="$STAGE/libs.ref/gf180mcu_ocd_ip_sram/lib"
LEF="$STAGE/libs.ref/gf180mcu_ocd_ip_sram/lef/gf180mcu_ocd_ip_sram__sram1024x8m8wm1.lef"

[ -f "$LEF" ] || { echo "error: $LEF not found, cannot compute macro area" >&2; exit 1; }

# LEF SIZE is authoritative for macro area (this map's standing rule: take
# macro area from LEF, never Liberty).
SIZE_LINE=$(grep -m1 '^[[:space:]]*SIZE ' "$LEF")
X=$(printf '%s' "$SIZE_LINE" | awk '{print $2}')
Y=$(printf '%s' "$SIZE_LINE" | awk '{print $4}')
AREA=$(awk -v x="$X" -v y="$Y" 'BEGIN{printf "%.3f", x*y}')

echo "==> patching gf180mcu_ocd_ip_sram__sram1024x8m8wm1 Liberty (ticket 20): area -> ${AREA} um2, address_width -> 10"

count=0
for lib in "$LIBDIR"/gf180mcu_ocd_ip_sram__sram1024x8m8wm1__*.lib; do
    [ -f "$lib" ] || continue
    sed -i \
      -e "s/^\(\s*area\s*:\s*\)209400\.2768;/\1${AREA};/" \
      -e "s/^\(\s*address_width\s*:\s*\)9;/\110;/" \
      "$lib"
    count=$((count + 1))
done

[ "$count" -eq 10 ] || { echo "error: expected 10 sram1024x8m8wm1 .lib files, patched $count" >&2; exit 1; }
