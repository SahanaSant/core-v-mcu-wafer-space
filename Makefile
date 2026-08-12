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
PDK_ROOT   ?= $(ROOT)/pdk

# --- Design configuration ---------------------------------------------------
SLOT ?= 1x1
SCL  ?= gf180mcu_fd_sc_mcu7t5v0
PAD  ?= gf180mcu_fd_io
SRAM ?= gf180mcu_fd_ip_sram

TOP        ?= chip_top
FINAL_GDS  ?= $(ROOT)/flow/final/gds/$(TOP).gds

PRECHECK_IMAGE ?= gf180mcu-precheck:local
PRECHECK_REPO  ?= https://github.com/wafer-space/gf180mcu-precheck

RUN := OSIC_IMAGE=$(OSIC_IMAGE) PDK=$(PDK) $(ROOT)/docker/run.sh

export SLOT SCL PAD SRAM PDK PDK_FAMILY PDK_COMMIT

# Abort with a useful message when a prerequisite file is missing.
define require
	@test -e "$(1)" || { \
	  echo "error: missing $(1)"; \
	  echo "       $(2)"; \
	  exit 1; \
	}
endef

.PHONY: help shell pdk harden sim sim-gl precheck precheck-image clean

help: ## Show this help
	@echo "core-v-mcu-wafer-space"
	@echo
	@grep -hE '^[a-z0-9_-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[1m%-16s\033[0m %s\n", $$1, $$2}'
	@echo
	@echo "  slot=$(SLOT) pdk=$(PDK) scl=$(SCL)"

shell: ## Open a shell in the toolchain container
	@$(RUN)

pdk: ## Fetch the pinned GF180MCU PDK into ./pdk
	@mkdir -p $(PDK_ROOT)
	@$(RUN) ciel enable \
	  --pdk-root /foss/designs/pdk \
	  --pdk-family $(PDK_FAMILY) \
	  $(PDK_COMMIT)
	@echo "PDK ready at $(PDK_ROOT)"

harden: ## Run LibreLane RTL-to-GDS
	$(call require,$(ROOT)/flow/config.yaml,see flow/README.md)
	@$(RUN) librelane \
	  --pdk-root /foss/designs/pdk --pdk $(PDK) \
	  --save-views-to /foss/designs/flow/final \
	  /foss/designs/flow/config.yaml

sim: ## Run RTL simulation (cocotb)
	$(call require,$(ROOT)/sim/Makefile,see sim/README.md)
	@$(RUN) make -C /foss/designs/sim

sim-gl: ## Run gate-level simulation against the hardened netlist
	$(call require,$(ROOT)/sim/Makefile,see sim/README.md)
	@$(RUN) make -C /foss/designs/sim GL=1

precheck-image: ## Build the wafer.space precheck container
	@tmp=$$(mktemp -d) && git clone --depth 1 $(PRECHECK_REPO) $$tmp/precheck \
	  && docker build -t $(PRECHECK_IMAGE) $$tmp/precheck \
	  && rm -rf $$tmp

precheck: ## Check the final GDS against wafer.space submission rules
	$(call require,$(FINAL_GDS),run `make harden` first)
	@docker run --rm -v $(ROOT):/work:z $(PRECHECK_IMAGE) \
	  --top $(TOP) --slot $(SLOT) /work/flow/final/gds/$(TOP).gds

clean: ## Remove flow outputs (keeps the PDK)
	@rm -rf $(ROOT)/flow/runs $(ROOT)/flow/final $(ROOT)/sim/sim_build
