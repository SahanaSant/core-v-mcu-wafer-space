// Copyright 2026 Yusef Karim
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Gate-level (and RTL) sim harness top level for ticket 31. cocotb drives
// clk_PAD/rst_n_PAD and reads boot_ok_seen/sram_pass_seen here rather than on
// chip_top directly, because chip_top's other pads (bidir_PAD, input_PAD) are
// wide inout vectors, and cocotb's Python-side VPI access to a single bit of
// an inout vector is unreliable under Icarus. Wiring the flash model and the
// UART byte watcher at the SV level instead sidesteps that: this file only
// ever bit-selects nets in SV, which every simulator supports natively, and
// exposes cocotb nothing narrower than a whole scalar port. The wafer.space
// project template's own chip_top_tb.py flags exactly this limitation in a
// comment ("cocotb cannot write to individual bits of a vector... use
// individual pad names") and this wrapper is that fix.
//
// qspim0 pad indices (35=CLK, 36=CSN0, 37=DATA0/MOSI, 38=DATA1/MISO) and
// uart0 TX index (26) are both confirmed from
// core-v-mcu/rtl/core-v-mcu/top/pad_control.sv, not assumed from the pad
// table alone.

`timescale 1ns / 1ps

module tb_top #(
    parameter FLASH_INIT_FILE = "flash_image.hex"
) (
    input  wire clk_PAD,
    input  wire rst_n_PAD,
    output reg  boot_ok_seen,
    output reg  sram_pass_seen
);

  localparam int NUM_INPUT_PADS = 11;
  localparam int NUM_BIDIR_PADS = 40;
  localparam int NUM_ANALOG_PADS = 2;

  wire [NUM_INPUT_PADS-1:0] input_PAD;
  wire [NUM_BIDIR_PADS-1:0] bidir_PAD;
  wire [NUM_ANALOG_PADS-1:0] analog_PAD;
  wire jtag_tdo_PAD;

  // Every input pad idle: no JTAG activity, no stray edges on the spares.
  assign input_PAD = '0;
  assign analog_PAD = '0;

  // chip_top declares clk_PAD and rst_n_PAD as `inout wire`, because they are
  // pads. Wiring this module's `input` ports straight into them makes the
  // connection look like an assignment to an input, which Verilator rejects
  // outright (ASSIGNIN) even though the design only ever reads these two.
  // Driving an intermediate net instead keeps the direction legal for both
  // simulators, and keeps cocotb writing to a plain scalar input port.
  wire clk_PAD_i = clk_PAD;
  wire rst_n_PAD_i = rst_n_PAD;

`ifdef USE_POWER_PINS
  wire VDD = 1'b1;
  wire VSS = 1'b0;
  wire DVDD = 1'b1;
  wire DVSS = 1'b0;

  chip_top dut (
      .VDD(VDD),
      .VSS(VSS),
      .DVDD(DVDD),
      .DVSS(DVSS),
      .clk_PAD(clk_PAD_i),
      .rst_n_PAD(rst_n_PAD_i),
      .jtag_tdo_PAD(jtag_tdo_PAD),
      .input_PAD(input_PAD),
      .bidir_PAD(bidir_PAD),
      .analog_PAD(analog_PAD)
  );
`else
  chip_top dut (
      .clk_PAD(clk_PAD_i),
      .rst_n_PAD(rst_n_PAD_i),
      .jtag_tdo_PAD(jtag_tdo_PAD),
      .input_PAD(input_PAD),
      .bidir_PAD(bidir_PAD),
      .analog_PAD(analog_PAD)
  );
`endif

  // --- SPI flash model on qspim0 --------------------------------------------
  // GD25Q128B.v is vendored in core-v-mcu/tb/qspi_model/ for upstream's own
  // (unused-here) tb_pulp.sv; reused rather than hand-rolling a QSPI BFM,
  // since it's a real, timing-accurate behavioral model of a real part and
  // sw/bootrom/spi.c's JEDEC single-line READ (0x03) is exactly what any real
  // flash of this shape answers.
  wire flash_sclk = bidir_PAD[35];
  wire flash_cs = bidir_PAD[36];
  wire flash_si = bidir_PAD[37];
  wire flash_so;
  assign bidir_PAD[38] = flash_so;

  // Icarus requires an inout port's actual to be something that supports
  // continuous assignment, not a bare literal, hence the wires here.
  wire flash_wp = 1'b1;
  wire flash_hold = 1'b1;

  GD25Q128B #(
      .initfile(FLASH_INIT_FILE)
  ) flash (
      .sclk(flash_sclk),
      .si(flash_si),
      .cs(flash_cs),
      .wp(flash_wp),
      .hold(flash_hold),
      .so(flash_so)
  );

  // --- UART0 TX watcher ------------------------------------------------------
  // bidir_PAD[26] is uart0's TX line at its reset-default pad mux (mode 0),
  // so sw/app never has to touch REG_PADMUX for this to work.
  wire uart_tx = bidir_PAD[26];

  logic uart_byte_valid;
  logic [7:0] uart_byte_data;

  uart_rx #(
      .CLKS_PER_BIT(43)  // 5 MHz periph_clk / 115200 baud, sw/app/main.c's APP_BAUD_HZ
  ) uart_rx_i (
      .clk(clk_PAD),
      .rst_n(rst_n_PAD),
      .rx(uart_tx),
      .byte_valid(uart_byte_valid),
      .byte_data(uart_byte_data)
  );

  // "BOOT OK\r\n" -- 9 bytes -- and "SRAM PASS\r\n" -- 11 bytes -- both
  // written literally rather than through a generic parametrized matcher, to
  // avoid depending on SystemVerilog string/array-parameter features that
  // are less consistently supported under Icarus than a plain case statement.
  int boot_idx;
  always_ff @(posedge clk_PAD or negedge rst_n_PAD) begin
    if (!rst_n_PAD) begin
      boot_idx <= 0;
      boot_ok_seen <= 1'b0;
    end else if (uart_byte_valid && !boot_ok_seen) begin
      case (boot_idx)
        0: boot_idx <= (uart_byte_data == "B") ? 1 : 0;
        1: boot_idx <= (uart_byte_data == "O") ? 2 : ((uart_byte_data == "B") ? 1 : 0);
        2: boot_idx <= (uart_byte_data == "O") ? 3 : ((uart_byte_data == "B") ? 1 : 0);
        3: boot_idx <= (uart_byte_data == "T") ? 4 : ((uart_byte_data == "B") ? 1 : 0);
        4: boot_idx <= (uart_byte_data == " ") ? 5 : ((uart_byte_data == "B") ? 1 : 0);
        5: boot_idx <= (uart_byte_data == "O") ? 6 : ((uart_byte_data == "B") ? 1 : 0);
        6: boot_idx <= (uart_byte_data == "K") ? 7 : ((uart_byte_data == "B") ? 1 : 0);
        7: boot_idx <= (uart_byte_data == 8'h0D) ? 8 : ((uart_byte_data == "B") ? 1 : 0);
        8: begin
          if (uart_byte_data == 8'h0A) begin
            boot_ok_seen <= 1'b1;
            boot_idx <= 0;
          end else begin
            boot_idx <= (uart_byte_data == "B") ? 1 : 0;
          end
        end
        default: boot_idx <= 0;
      endcase
    end
  end

  int sram_idx;
  always_ff @(posedge clk_PAD or negedge rst_n_PAD) begin
    if (!rst_n_PAD) begin
      sram_idx <= 0;
      sram_pass_seen <= 1'b0;
    end else if (uart_byte_valid && !sram_pass_seen) begin
      case (sram_idx)
        0: sram_idx <= (uart_byte_data == "S") ? 1 : 0;
        1: sram_idx <= (uart_byte_data == "R") ? 2 : ((uart_byte_data == "S") ? 1 : 0);
        2: sram_idx <= (uart_byte_data == "A") ? 3 : 0;
        3: sram_idx <= (uart_byte_data == "M") ? 4 : ((uart_byte_data == "S") ? 1 : 0);
        4: sram_idx <= (uart_byte_data == " ") ? 5 : 0;
        5: sram_idx <= (uart_byte_data == "P") ? 6 : ((uart_byte_data == "S") ? 1 : 0);
        6: sram_idx <= (uart_byte_data == "A") ? 7 : 0;
        7: sram_idx <= (uart_byte_data == "S") ? 8 : ((uart_byte_data == "S") ? 1 : 0);
        8: sram_idx <= (uart_byte_data == "S") ? 9 : 0;
        9: sram_idx <= (uart_byte_data == 8'h0D) ? 10 : ((uart_byte_data == "S") ? 1 : 0);
        10: begin
          if (uart_byte_data == 8'h0A) begin
            sram_pass_seen <= 1'b1;
            sram_idx <= 0;
          end else begin
            sram_idx <= (uart_byte_data == "S") ? 1 : 0;
          end
        end
        default: sram_idx <= 0;
      endcase
    end
  end

  // Dump every UART byte as it's decoded, so a failing run's log shows the
  // real "SRAM FAIL <n>" text rather than just a timeout.
  always @(posedge clk_PAD) begin
    if (uart_byte_valid) begin
      $write("%c", uart_byte_data);
      $fflush;
    end
  end

  // Timestamp each flash chip-select assertion (active low). The first run to
  // reach its natural end left roughly 15ms unaccounted for between the boot
  // ROM's first stack access at 3.155ms and the first write to the image
  // region at 18.261ms, and the SPI transactions udma_qspim_open(),
  // udma_flash_reset_enable(), udma_flash_reset_memory() and udma_flash_read()
  // issue are the only thing in between. Printing them makes the next run show
  // where that time actually goes instead of leaving it to be inferred from
  // the SRAM models' first-access reports.
  always @(negedge flash_cs) begin
    $display("tb_top: flash CS asserted @ %0t", $time);
    $fflush;
  end

  // CS never asserting leaves two very different explanations open: the uDMA
  // is completely idle, or it is running and driving the wrong line. Counting
  // SCLK edges separates them, because the qspim cannot shift a command
  // without toggling its clock. First few only, so a working run does not
  // flood the log.
  integer sclk_edges = 0;
  always @(posedge flash_sclk) begin
    sclk_edges <= sclk_edges + 1;
    if (sclk_edges < 4) begin
      $display("tb_top: flash SCLK edge %0d @ %0t", sclk_edges, $time);
      $fflush;
    end
  end

  // --- Boot progress tracer ------------------------------------------------
  // RTL only. Synthesis flattens everything except the macros, so this
  // hierarchical path does not exist in the netlist, and Icarus makes that an
  // elaboration error rather than a warning. Gate-level keeps the flash chip
  // select trace and the UART decode, which are both at the pads.
`ifndef GL_SIM
  // A full boot is roughly 24ms of simulated time, several minutes of wall
  // time, almost all of it crcSlow(). Without some sign of life a run that is
  // working and a run that is wedged look the same for minutes at a stretch.
  //
  // Trace transitions rather than sampling on a timer. A periodic dump
  // interleaves with the UART bytes the block above writes one character at a
  // time, and at 115200 baud a byte arrives every 87us, so any print interval
  // short enough to be useful scatters "BOOT OK" one letter per line.
  //
  // The boot ROM is 207 words, so 0x1A000000 + 4*A maps straight back to an
  // instruction in the disassembly. The core leaving the ROM for good is the
  // one milestone between the last flash transfer and the app's first print.
  wire       brom_cen = dut.i_chip_core.i_core_v_mcu.i_soc_domain.boot_rom_i.rom_mem_i.CEN;
  wire [10:0] brom_a  = dut.i_chip_core.i_core_v_mcu.i_soc_domain.boot_rom_i.rom_mem_i.A;

  reg [10:0] brom_last_a = 0;
  always @(posedge clk_PAD) if (!brom_cen) brom_last_a <= brom_a;

  reg        brom_running = 1'b0;
  integer    brom_idle = 0;
  localparam int BROM_IDLE_CYCLES = 10000;  // ~1.7ms at 6MHz, far longer than any ROM loop

  always @(posedge clk_PAD) begin
    if (!brom_cen) begin
      brom_idle <= 0;
      if (!brom_running) begin
        brom_running <= 1'b1;
        $display("tb_top: core fetching from boot ROM, first word %0d @ %0t", brom_a, $time);
        $fflush;
      end
    end else if (brom_running) begin
      brom_idle <= brom_idle + 1;
      if (brom_idle == BROM_IDLE_CYCLES) begin
        brom_running <= 1'b0;
        $display("tb_top: core left the boot ROM, last word %0d @ %0t", brom_last_a, $time);
        $fflush;
      end
    end
  end

`else
  // --- Gate-level liveness -------------------------------------------------
  // Nothing reaches a pad until the SPI transfer starts, so a netlist that is
  // wedged and one that is working look identical from outside until the first
  // chip select. There is no boot ROM instance to watch either: ticket 23
  // dropped the a2_bootrom black box, so the ROM is synthesised into gates and
  // `a2_bootrom` does not appear in the netlist at all.
  //
  // The L2 macros do survive, as escaped flat identifiers rather than real
  // hierarchy (`\i_chip_core...i_sram`, note the required trailing space).
  // Counting their chip enables says the core is clocked, out of reset and
  // executing, which is what separates "the harness does not work at gate
  // level" from "the netlist runs and boot fails for a known reason".
  integer l2_access = 0;
  always @(posedge clk_PAD)
    if (!dut.\i_chip_core.i_core_v_mcu.i_soc_domain.l2_ram_i.bank_sram_pri0_i.i_bank.gen_byte_lane[0].i_sram .CEN)
      l2_access <= l2_access + 1;

  initial begin
    forever begin
      #(500_000);  // 0.5ms: this module's timescale is 1ns, and a GL run is slow
      $display("tb_top: gl liveness: L2 accesses=%0d sclk_edges=%0d @ %0t",
               l2_access, sclk_edges, $time);
      $fflush;
    end
  end
`endif  // GL_SIM

endmodule
