# Copyright 2026 Yusef Karim
# Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# The cocotb entry point. hdl_toplevel is sim/tb/tb_top.sv, not
# chip_top directly -- see that file's header for why (cocotb can't reliably
# bit-select an inout vector under Icarus, so the flash model, the UART
# decode and the pass/fail latches all live in plain SV instead, and cocotb
# only ever touches whole scalar signals: clk_PAD, rst_n_PAD,
# boot_ok_seen, sram_pass_seen).
#
# Reset/clock helpers are lifted from the wafer.space project template's
# cocotb/chip_top_tb.py almost unchanged: this design's clk_PAD/rst_n_PAD
# port names match the template exactly, so there was
# nothing design-specific to adapt there.

import os
import logging
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, ClockCycles
from cocotb_tools.runner import get_runner

gl = os.getenv("GL", "0") == "1"

# Icarus for gate-level, Verilator for RTL. Gate level is pinned to Icarus
# because the PDK's icgtp model is built on a Verilog user-defined primitive
# and carries a specify block, and Verilator implements neither. That
# constraint is specific to reading the PDK standard-cell library, and only
# rtl/gf180mcu/gf180_clk_gate.sv makes an RTL run read it. Swapping that one
# file for the behavioural clock cells already vendored under
# core-v-mcu/rtl/vendor removes the last reference, so RTL needs nothing from
# libs.ref/gf180mcu_fd_sc_mcu7t5v0 and Verilator becomes usable. That matters:
# with waves off (see WAVES below) gate-level measures 23,360 ns/s against
# Verilator's 233,439 ns/s, so RTL is the ten-times-faster loop to iterate boot
# software in, and gate level is where the netlist gets confirmed. SIM
# overrides either default.
sim = os.getenv("SIM") or ("icarus" if gl else "verilator")
pdk_root = os.getenv("PDK_ROOT", str(Path(__file__).resolve().parent / "../../pdk"))
pdk = os.getenv("PDK", "gf180mcuD")
scl = os.getenv("SCL", "gf180mcu_fd_sc_mcu7t5v0")
pad = os.getenv("PAD", "gf180mcu_ocd_io")
flash_hex = os.getenv("FLASH_HEX", str(Path(__file__).resolve().parent / "../../flow/build/app/flash_image.hex"))

hdl_toplevel = "tb_top"

# clk_PAD is ref_clk_i bypassed undivided, i.e. periph_clk. 5 MHz is the
# frequency at which post-route STA closes at the slow corner. Keep in step
# with
# flow/config.yaml's CLOCK_PERIOD and sw/app/main.c's APP_BAUD_HZ (which sets
# tb_top.sv's CLKS_PER_BIT) if it changes again. 5 MHz also divides exactly:
# the Clock() call below floors 1e9/CLK_HZ to an integer ns, which silently
# truncated 166.67 to 166 at 6 MHz and is exactly 200 here.
CLK_HZ = 5_000_000

# A full boot-and-report is **28.204 ms** of simulated time, measured end to
# end on runs that reached "SRAM PASS" rather than extrapolated, and it is the
# same figure at RTL and at gate level (the design does the same work either
# way). With waves off that costs 121 s under Verilator (233,439 ns/s) and
# 1,207 s under Icarus at gate level (23,360 ns/s).
#
# So 45 ms is the useful setting: about 1.6x the real boot time, enough that a
# run which is merely slow is not cut off, small enough that a run which has
# genuinely hung gives up in well under an hour. The default here stays at
# 100 ms only as an unattended backstop.
#
# Two earlier estimates in this file were wrong, both worth knowing about:
#
# - The 20 ms this held before was replaced on the strength of arithmetic that
#   was wrong by 1000x. The SRAM models' first-access reports were read as
#   milliseconds, but that model declares `timescale 1 ps / 1 ps` and prints
#   with %0t, so 3.155 "ms" was 3.155 us. Beware: %0t prints in the precision
#   of the module doing the printing, not the testbench's.
# - "Boot either completes or hangs within tens of microseconds" was also
#   wrong, and it is why the deadline looked generous when it was not. The SPI
#   phase does finish in tens of microseconds, but crcSlow() is a bit-at-a-time
#   CRC32 over the whole image and the app then walks 512 B of L2 twice, which
#   is where the other 28 ms goes. Do not size a timeout off the flash trace.
TIMEOUT_NS = int(os.getenv("TIMEOUT_NS") or 100_000_000)


async def start_clock(dut):
    c = Clock(dut.clk_PAD, 1_000_000_000 // CLK_HZ, "ns")
    cocotb.start_soon(c.start())


async def reset(dut, time_ns=1000):
    # Drive reset high first so that pulling it low is a real falling edge.
    # Everything in the design resets with `always_ff @(posedge clk or negedge
    # rstn)`, which is level-sensitive in silicon but edge-sensitive in a
    # simulator: the reset branch only runs on a clock edge or on rstn falling.
    # Most of the chip is fine either way, because its clock is free-running and
    # the clock edges that arrive while rstn is low do the reset. The uDMA core
    # is not: udma_ctrl gates s_clk_core off until software enables a peripheral
    # (cg_core_o = |r_cg, zero out of reset), so every flop inside udma_core
    # sees no clock at all while reset is asserted and depends entirely on the
    # falling edge. Starting rstn at 0 gives it no edge to depend on, and
    # udma_arbiter's r_priority never loads its reset value of 1. With a
    # priority vector of zero, grant_o = req_i & g[S] is zero for every channel
    # forever while anyGrant_o still reports work pending, so the TX engine
    # pushes address-zero requests at L2 and no channel is ever served.
    #
    # The high phase has to be long enough for the falling edge to reach the
    # inside of the chip, which is why a one-nanosecond blip is not enough:
    # rst_n_PAD does not drive the SoC directly. safe_domain runs it through
    # rstgen_bypass, a four-deep shift register clocked by ref_clk, and only its
    # output (s_rstn_por) reaches soc_domain. That output starts low and can
    # only fall after it has first risen, which takes four clock edges with
    # rst_n_PAD held high. Twelve clock periods gives it three times the margin
    # it needs. The chip does execute from an unreset state during that window,
    # which is harmless: the reset that follows clears every register, and the
    # only state that survives is L2 SRAM, which the boot ROM overwrites.
    dut.rst_n_PAD.value = 1
    await Timer(12 * (1_000_000_000 // CLK_HZ), "ns")
    dut.rst_n_PAD.value = 0
    await Timer(time_ns, "ns")
    dut.rst_n_PAD.value = 1


@cocotb.test()
async def test_boot_and_uart(dut):
    """Boot from the SPI flash model and check the UART report."""

    logger = logging.getLogger("tb_top_tb")

    await start_clock(dut)
    await reset(dut)

    logger.info("Reset released, waiting for BOOT OK / SRAM PASS over UART0...")

    deadline_ns = TIMEOUT_NS
    step_ns = 100_000
    elapsed = 0
    while elapsed < deadline_ns:
        await Timer(step_ns, "ns")
        elapsed += step_ns
        if dut.sram_pass_seen.value == 1:
            break

    # "BOOT OK" is sw/app/main.c's first print, not the boot ROM's, so this
    # firing means the app never reached that print: either sw/bootrom/main.c
    # halt()ed (bad size or CRC mismatch) and never jumped, or the run hit
    # TIMEOUT_NS while boot was still in flight. Those look identical from
    # here, so check the decoded UART bytes tb_top.sv dumps (none at all means
    # nothing ever printed) and the SRAM models' own first-access reports,
    # which timestamp when the image region at 0x1C000000 was first written.
    assert dut.boot_ok_seen.value == 1, (
        "never saw 'BOOT OK' over UART0 -- sw/app/main.c never reached its "
        "first print (boot ROM halted, or timed out mid-boot)"
    )
    assert dut.sram_pass_seen.value == 1, (
        "'BOOT OK' was seen but 'SRAM PASS' never was -- either the SRAM "
        "read-write-read walk found a mismatch (see the decoded UART bytes "
        "in the sim log for 'SRAM FAIL <n>') or the run timed out before "
        "the app finished"
    )

    logger.info("BOOT OK and SRAM PASS both seen over UART0.")


def build_sources():
    sim_dir = Path(__file__).resolve().parent
    tb_dir = sim_dir / "../tb"
    root = sim_dir / "../.."

    sources = [tb_dir / "uart_rx.sv"]
    defines = {"FUNCTIONAL": True}
    includes = []

    if gl:
        # The netlist instantiates PDK standard cells by name, so GL has to read
        # their behavioural models and the UDPs in primitives.v that several of
        # them are built on. This is the sole reason GL is pinned to Icarus.
        sources.append(Path(pdk_root) / pdk / "libs.ref" / scl / "verilog" / f"{scl}.v")
        sources.append(Path(pdk_root) / pdk / "libs.ref" / scl / "verilog" / "primitives.v")
        sources.append(root / "flow/final/pnl/chip_top.pnl.v")
        # GL_SIM gates the parts of tb_top.sv that reach into RTL hierarchy.
        # Synthesis flattens everything but the macros, so paths like
        # i_soc_domain.boot_rom_i.rom_mem_i simply do not exist in the netlist
        # and Icarus fails to elaborate rather than warning.
        defines.update({"USE_POWER_PINS": True, "GL_SIM": True})
        # The netlist instantiates the marker cells directly too; RTL sim
        # gets these from flow/build/sources.yaml below instead (fusesoc
        # already resolved them there), so only GL needs them added by hand.
        sources += [
            root / "ip/gf180mcu_ws_ip__logo/vh/gf180mcu_ws_ip__logo.v",
            root / "ip/gf180mcu_ws_ip__marker/vh/gf180mcu_ws_ip__marker.v",
            root / "ip/gf180mcu_ws_ip__qrcode_id/vh/gf180mcu_ws_ip__qrcode_id.v",
            root / "ip/gf180mcu_ws_ip__shuttle_id/vh/gf180mcu_ws_ip__shuttle_id.v",
            root / "ip/gf180mcu_ws_ip__project_id/vh/gf180mcu_ws_ip__project_id.v",
        ]
    else:
        # flow/build/sources.yaml is flow/synth/sources.sh's fusesoc-resolved
        # file list (the same one `make harden` feeds LibreLane): chip_top.sv,
        # chip_core.sv, the whole SoC underneath and the marker IP already
        # flattened to one list. sim/Makefile regenerates it before this
        # runs, the same way `make harden` does, so this isn't relying on a
        # stale build/ dir.
        import yaml

        with open(root / "flow/build/sources.yaml") as f:
            manifest = yaml.safe_load(f)
        # gf180_clk_gate.sv is dropped and replaced below. It is the only file
        # in the design that names a PDK standard cell, so removing it is what
        # frees the RTL run from libs.ref and therefore from Icarus. Everything
        # it defines (pulp_clock_gating, cluster_clock_gating,
        # cv32e40p_clock_gate, pulp_clock_inverter, cluster_clock_inverter,
        # pulp_clock_mux2) has a behavioural twin already vendored, so no new
        # model is written here. Synthesis still reads the real cells: this
        # swap exists only inside the simulator.
        sources += [
            Path(p)
            for p in manifest["VERILOG_FILES"]
            if Path(p).name != "gf180_clk_gate.sv"
        ]
        vendor = root / "core-v-mcu/rtl/vendor"
        sources += [
            # pulp_clk_cells.sv and cluster_clk_cells.sv are thin wrappers that
            # forward to tc_clk_gating / tc_clk_inverter / tc_clk_mux2, so the
            # generic implementation of those has to come along as well.
            vendor / "pulp_platform_tech_cells_generic/src/rtl/tc_clk.sv",
            vendor / "pulp_platform_tech_cells_generic/src/deprecated/pulp_clk_cells.sv",
            vendor / "pulp_platform_tech_cells_generic/src/deprecated/cluster_clk_cells.sv",
            vendor / "openhwgroup_cv32e40p/bhv/cv32e40p_sim_clock_gate.sv",
        ]
        # The RTL is full of `include "pulp_soc_defines.svh"` and friends, which
        # resolve only against the include path fusesoc worked out. LibreLane
        # reads VERILOG_INCLUDE_DIRS out of this same manifest, so taking it
        # from here keeps `make sim` and `make harden` reading one source of
        # truth. Without it iverilog stops at apb_gpio.sv line 34.
        includes += [Path(p) for p in manifest.get("VERILOG_INCLUDE_DIRS", [])]

    # Not in sources.yaml either way (synthesis blackboxes these via
    # LEF/Liberty; simulation needs the real behavioral models).
    #
    # The pad cells and the SRAM macro are the exceptions. GL reads the PDK's
    # real models; RTL reads behavioural stand-ins in sim/tb, because both PDK
    # models depend on things a zero-delay RTL run does not provide. The pads
    # build their pull-up/pull-down out of `rnmos`, which Verilator does not
    # implement. The SRAM samples its inputs 100 ps after the clock edge and so
    # needs a clock-to-Q delay to hold them; without one it drops every access
    # and the memory reads back as zeros. Each stand-in's header has the
    # detail, including what is and is not carried over.
    sources += [
        Path(pdk_root) / pdk / f"libs.ref/{pad}/verilog/{pad}.v"
        if gl
        else tb_dir / "gf180mcu_ocd_io_behav.sv",
        # The SRAM stand-in is used for gate-level too, not just RTL. A
        # gate-level run here has no SDF annotation, so its netlist flops have
        # no clock-to-Q delay either and the PDK model drops accesses exactly
        # the same way. The macro is a hard block whose internals no simulator
        # models regardless, and `make sta` is what signs off its timing.
        tb_dir / "gf180mcu_ocd_ip_sram_behav.sv",
        # GD25Q128B, not our own: see tb_top.sv's header for why this model
        # rather than a hand-rolled BFM.
        root / "core-v-mcu/tb/qspi_model/GD25Q128B.v",
        tb_dir / "tb_top.sv",
    ]
    return sources, defines, includes


def build_args():
    if sim == "verilator":
        # --timing: GD25Q128B is a real behavioural part model built on delay
        # controls, so the event-driven scheduler is required rather than
        # optional. -Wno-fatal: the vendored PULP/CV32E40P RTL produces a large
        # number of lint warnings that are not this harness's to fix, and a
        # fatal lint stop would make the run useless.
        return ["--timing", "-Wno-fatal"]
    return ["-g2012"]


# Waveform dumping is off unless WAVES=1, because on a design this size it is
# not a small overhead, it is the dominant cost of the whole run.
#
# Measured on the RTL run that prompted this: 7.43 us of simulated time cost
# 1.5 GB of VCD and about seven minutes, i.e. roughly 18 ns/s. The 39,553 ns/s
# this file quotes elsewhere for Verilator is three orders of magnitude away
# from that, so waves were the difference. Extrapolating the VCD alone, the
# 40 ms a full boot needs would have been on the order of terabytes: the run
# could not have finished on this disk, let alone in reasonable time.
#
# Nothing in the test reads the VCD. Both assertions poll cocotb handles
# (boot_ok_seen / sram_pass_seen) and the UART bytes are printed by
# tb_top.sv's own $display, so the trace is purely a debugging aid. Turn it on
# deliberately, and when you do, cut TIMEOUT_NS right down to match.
WAVES = os.getenv("WAVES") == "1"


def main():
    sources, defines, includes = build_sources()

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel=hdl_toplevel,
        defines=defines,
        includes=includes,
        parameters={"FLASH_INIT_FILE": f'"{flash_hex}"'},
        always=True,
        build_args=build_args(),
        waves=WAVES,
    )

    runner.test(
        hdl_toplevel=hdl_toplevel,
        test_module="tb_top_tb",
        waves=WAVES,
    )


if __name__ == "__main__":
    main()
