# Copyright 2026 Yusef Karim
# Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Ticket 31's gate-level (and RTL) sim harness. Invoked from the repo root as
# `make sim` / `make sim-gl`, which run this inside the toolchain container
# (root Makefile's RUN wrapper) with GL unset / GL=1.
#
# app: always rebuilt, since it's cheap (a few hundred bytes of RV32IMC) and
# the flash image has to match whatever sw/app/ currently contains.
# sources.yaml: only needed for RTL runs (GL reads the already-hardened
# netlist instead), but regenerating it is cheap and keeps `make sim` correct
# even if flow/build/ is stale or missing, the same way `make harden` always
# regenerates it rather than trusting a previous run's copy.

ROOT := $(shell cd .. && pwd)

.PHONY: all app sources gl-netlist

ifeq ($(GL),1)
all: app gl-netlist
	python3 cocotb/tb_top_tb.py
else
# sources before app, and not the other way round: flow/synth/filelist.sh does
# `rm -rf $BUILD` on flow/build, so running it after app deletes the very
# flash_image.hex app just built and the flash model comes up empty. GL never
# hit this because its target has no sources step.
all: sources app
	python3 cocotb/tb_top_tb.py
endif

app:
	sh $(ROOT)/flow/synth/app.sh

sources:
	sh $(ROOT)/flow/synth/sources.sh

gl-netlist:
	@test -e $(ROOT)/flow/final/pnl/chip_top.pnl.v || { \
	  echo "error: missing $(ROOT)/flow/final/pnl/chip_top.pnl.v"; \
	  echo "       run \`make harden\` first (ticket 29's DoD)"; \
	  exit 1; \
	}
