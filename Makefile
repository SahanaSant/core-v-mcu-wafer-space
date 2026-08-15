# core-v-mcu-wafer-space
#
# Every tool runs inside a container. Nothing is installed on the host.
# Override any variable on the command line, e.g. `make harden SLOT=0p5x1`.

ROOT := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

# --- Pinned versions --------------------------------------------------------
OSIC_TAG   ?= 2026.07
OSIC_IMAGE ?= hpretl/iic-osic-tools:$(OSIC_TAG)

PDK        ?= gf180mcuD
PDK_FAMILY ?= gf180mcu
PDK_COMMIT ?= f6eeac7dad085ffcc829ccfd721f7b4ce39edcf7
# Not overridable: the container always sees the PDK at /foss/designs/pdk,
# which is this path bind-mounted by run.sh.
PDK_ROOT   := $(ROOT)/pdk

# The PDK is built from source, because the prebuilt one `ciel enable` fetches
# carries only the five gf180mcu_fd_* libraries. Which libraries and which
# variant are decided in flow/pdk/build.sh, where the configure flags are.
# One variant takes about ten minutes at -j1. Higher is untested: the only
# build that has been proven here is serial, and open_pdks stages some views
# through shared paths, so raising this needs checking rather than assuming.
PDK_JOBS ?= 1

# open_pdks deliberately `unexport PDK_ROOT` while building, so that a build
# cannot pick up an already-installed PDK. The toolchain image ships a
# /headless/.magicrc that dereferences $env(PDK_ROOT) with no catch around it,
# so every magic call then fails to parse its startup file, loses the
# technology and writes cells named "(UNNAMED)", which kills the build. Point
# HOME at an empty directory so that startup file is not found: the technology
# is supposed to come from the .magicrc open_pdks symlinks next to each library
# as it builds it. Setting PDK_ROOT instead would silence the error by sourcing
# the *previously installed* PDK's tech file, which is the contamination this
# build exists to avoid.
PDK_BUILD_HOME := $(PDK_ROOT)/.build-home

# --- Design configuration ---------------------------------------------------
SLOT ?= 1x1
SCL  ?= gf180mcu_fd_sc_mcu7t5v0
# Ticket 18 split the IO ring: 5.0 V over the 3.3 V core, which the foundry
# gf180mcu_fd_io cannot do at all (it has no core-supply pad cell and shorts the
# two domains on purpose). Changing this back is a design change, not a tuning
# knob. run.sh carries the same default and shadows this one, so change both.
PAD  ?= gf180mcu_ocd_io
# Ticket 11 committed the OCD macro. It lives in the same libs.ref directory as
# the foundry sram512x8, which open_pdks also installs there.
SRAM ?= gf180mcu_ocd_ip_sram

TOP        ?= chip_top
FINAL_GDS  ?= $(ROOT)/flow/final/gds/$(TOP).gds

PRECHECK_IMAGE ?= gf180mcu-precheck:local
PRECHECK_REPO  ?= https://github.com/wafer-space/gf180mcu-precheck

RUN := OSIC_IMAGE=$(OSIC_IMAGE) PDK=$(PDK) $(ROOT)/run.sh

# The precheck image is not the toolchain image, so it cannot go through
# run.sh. Detect the engine the same way run.sh does.
ENGINE ?= $(shell command -v podman >/dev/null 2>&1 && echo podman || echo docker)

export SLOT SCL PAD SRAM PDK PDK_FAMILY PDK_COMMIT

# Abort with a useful message when a prerequisite file is missing.
define require
	@test -e "$(1)" || { \
	  echo "error: missing $(1)"; \
	  echo "       $(2)"; \
	  exit 1; \
	}
endef

.PHONY: help shell pdk elaborate area sta bootrom harden harden-cts sim sim-gl precheck precheck-image clean

help: ## Show this help
	@echo "core-v-mcu-wafer-space"
	@echo
	@grep -hE '^[a-z0-9_-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[1m%-16s\033[0m %s\n", $$1, $$2}'
	@echo
	@echo "  slot=$(SLOT) pdk=$(PDK) scl=$(SCL)"

shell: ## Open a shell in the toolchain container
	@$(RUN)

pdk: ## Build the pinned GF180MCU PDK from source into ./pdk (about 15 min)
	@mkdir -p $(PDK_ROOT) $(PDK_BUILD_HOME)
	@$(RUN) env HOME=/foss/designs/pdk/.build-home \
	  PDK_COMMIT=$(PDK_COMMIT) PDK_JOBS=$(PDK_JOBS) \
	  sh /foss/designs/flow/pdk/build.sh
	@echo "PDK ready at $(PDK_ROOT)"

elaborate: ## Elaborate the SoC RTL and list the modules still missing
	@$(RUN) sh /foss/designs/flow/synth/elaborate.sh

area: ## Synthesise to standard cells and report the logic area
	@$(RUN) sh /foss/designs/flow/synth/area.sh

sta: ## Report the critical path of the synthesised netlist (needs `make area`)
	@$(RUN) sh /foss/designs/flow/synth/sta.sh

bootrom: ## Build sw/bootrom, generate gf180_bootrom.sv, and simulate it against the image
	@$(RUN) sh /foss/designs/flow/synth/bootrom.sh

# Anything after `make harden` on the command line is passed straight to
# LibreLane, so `make harden ARGS="--to OpenROAD.PadRing"` stops early and
# `ARGS="--last-run --flow OpenInKLayout"` opens the previous run. The floorplan
# steps are seconds and detailed routing is hours, so iterating with --to is how
# the configuration gets debugged.
ARGS ?=

# The file list is regenerated from fusesoc on every fresh harden, but not when
# resuming: `--last-run` reuses the netlist a previous run already produced, and
# flow/synth/sources.sh starts by deleting flow/build.
LIBRELANE = $(RUN) librelane \
	  --pdk-root /foss/designs/pdk --pdk $(PDK) --manual-pdk \
	  --scl $(SCL) --pad $(PAD) \
	  --save-views-to /foss/designs/flow/final \
	  /foss/designs/flow/slot_$(SLOT).yaml \
	  /foss/designs/flow/macros.yaml \
	  /foss/designs/flow/build/sources.yaml \
	  /foss/designs/flow/config.yaml

harden: ## Run LibreLane RTL-to-GDS (ARGS= passes flags through)
	$(call require,$(ROOT)/flow/config.yaml,see flow/README.md)
	@$(RUN) sh /foss/designs/flow/synth/sources.sh
	@$(LIBRELANE) $(ARGS)

# OpenROAD's TritonCTS null-dereferences on this design on all but roughly one
# attempt in a hundred: a real crash, intermittent rather than configuration
# dependent, diagnosed in flow/chip_top.sdc's header. Retrying is the workaround,
# the same shape as flow/pdk/build.sh retrying magic. This resumes the previous
# run, so `make harden` has to have reached clock tree synthesis first, and it
# leaves the run stopped at CTS: continue with
# `make harden ARGS="--last-run --from OpenROAD.STAMidPNR-1"`.
harden-cts: ## Retry clock tree synthesis on the last run until it survives
	@i=0; until $(LIBRELANE) --last-run --from OpenROAD.CTS --to OpenROAD.CTS; do \
	  i=$$((i+1)); \
	  echo "clock tree synthesis crashed, retry $$i"; \
	  test $$i -lt 200 || { echo "error: 200 attempts, giving up"; exit 1; }; \
	done

sim: ## Run RTL simulation (cocotb)
	$(call require,$(ROOT)/sim/Makefile,see sim/README.md)
	@$(RUN) make -C /foss/designs/sim

sim-gl: ## Run gate-level simulation against the hardened netlist
	$(call require,$(ROOT)/sim/Makefile,see sim/README.md)
	@$(RUN) make -C /foss/designs/sim GL=1

precheck-image: ## Build the wafer.space precheck container
	@tmp=$$(mktemp -d) && git clone --depth 1 $(PRECHECK_REPO) $$tmp/precheck \
	  && $(ENGINE) build -t $(PRECHECK_IMAGE) $$tmp/precheck \
	  && rm -rf $$tmp

precheck: ## Check the final GDS against wafer.space submission rules
	$(call require,$(FINAL_GDS),run `make harden` first)
	@$(ENGINE) run --rm -v $(ROOT):/work:z $(PRECHECK_IMAGE) \
	  --top $(TOP) --slot $(SLOT) /work/flow/final/gds/$(TOP).gds

clean: ## Remove flow outputs (keeps the PDK)
	@rm -rf $(ROOT)/flow/runs $(ROOT)/flow/final $(ROOT)/flow/build $(ROOT)/sim/sim_build
