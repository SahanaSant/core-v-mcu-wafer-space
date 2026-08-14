# Copyright 2026 Yusef Karim
# Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Power grid over the sixteen L2 SRAM macros. Seeded from
# librelane/pdn/pdn_3v3_sram.tcl in the gf180mcu project template (Apache-2.0,
# (c) 2025 Project Template Contributors).
#
# The template writes one grid per macro instance, because it has two of them
# in different orientations. This design has sixteen in one orientation, so the
# grid is selected by cell rather than by instance name: `-cells` matches every
# instance of the master, which keeps this file from having to repeat the
# instance paths that flow/macros.yaml already carries.
#
# The stripe geometry is the template's, unchanged, and it transfers exactly:
# gf180mcu_ocd_ip_sram__sram512x8m8wm1 and __sram1024x8m8wm1 are both 301.300 um
# wide (they differ only in height, 321.890 against 515.810), so the perimeter
# pitch of 298.30 um still lands the power strap of each pair on the macro's own
# Metal2 supply ring. The macros here are placed FS rather than N, which mirrors
# in y only and so leaves these vertical stripes where they were.

define_pdn_grid \
    -macro \
    -cells "gf180mcu_ocd_ip_sram__sram1024x8m8wm1" \
    -name sram_macros \
    -starts_with POWER \
    -halo "$::env(PDN_HORIZONTAL_HALO) $::env(PDN_VERTICAL_HALO)"

add_pdn_connect \
    -grid sram_macros \
    -layers "$::env(PDN_VERTICAL_LAYER) $::env(PDN_HORIZONTAL_LAYER)"

add_pdn_connect \
    -grid sram_macros \
    -layers "$::env(PDN_VERTICAL_LAYER) Metal3"

# Stripes down the macro's west and east edges, onto its own supply ring.
add_pdn_stripe \
    -grid sram_macros \
    -layer Metal4 \
    -width 1.36 \
    -offset 0.68 \
    -spacing 0.28 \
    -pitch 298.30 \
    -starts_with GROUND \
    -number_of_straps 2

# Those edge stripes block the top-level grid at Metal4, so put some back across
# the macro to keep the network continuous over the array and give the macro a
# better connection than its two edges alone.
add_pdn_stripe \
    -grid sram_macros \
    -layer Metal4 \
    -width 4.00 \
    -offset 50.80 \
    -spacing 0.28 \
    -pitch 48.86 \
    -starts_with GROUND \
    -number_of_straps 5
