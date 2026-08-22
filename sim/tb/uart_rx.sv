// Copyright 2026 Yusef Karim
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Plain synchronous UART receiver for tb_top.sv's monitor side, sampling on
// the same clk_PAD the design itself runs from (ticket 05/24: periph_clk is
// ref_clk_i bypassed undivided, i.e. the same net as clk_PAD), so
// CLKS_PER_BIT is exactly periph_clk_hz / baud -- the same division sw/app's
// uart0_open() programs into UART_SETUP.DIV, not an independent estimate.

module uart_rx #(
    parameter int CLKS_PER_BIT = 52
) (
    input  logic clk,
    input  logic rst_n,
    input  logic rx,
    output logic byte_valid,
    output logic [7:0] byte_data
);

  localparam int Half = CLKS_PER_BIT / 2;

  typedef enum logic [1:0] {
    Idle,
    Start,
    Data,
    Stop
  } state_t;

  state_t state;
  int cnt;
  int unsigned bit_idx;
  logic [7:0] shift;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= Idle;
      cnt <= 0;
      bit_idx <= 0;
      shift <= 8'h00;
      byte_valid <= 1'b0;
      byte_data <= 8'h00;
    end else begin
      byte_valid <= 1'b0;
      unique case (state)
        Idle: begin
          if (!rx) begin
            state <= Start;
            cnt <= 0;
          end
        end

        // Sample mid-start-bit to confirm it's real, then re-zero cnt: from
        // this point, cnt reaching CLKS_PER_BIT-1 lands on the middle of the
        // next bit, and every subsequent bit after that.
        Start: begin
          if (cnt == Half) begin
            if (!rx) begin
              state <= Data;
              cnt <= 0;
              bit_idx <= 0;
            end else begin
              state <= Idle;
            end
          end else begin
            cnt <= cnt + 1;
          end
        end

        Data: begin
          if (cnt == CLKS_PER_BIT - 1) begin
            cnt <= 0;
            shift[bit_idx] <= rx;
            if (bit_idx == 7) begin
              state <= Stop;
            end else begin
              bit_idx <= bit_idx + 1;
            end
          end else begin
            cnt <= cnt + 1;
          end
        end

        Stop: begin
          if (cnt == CLKS_PER_BIT - 1) begin
            state <= Idle;
            cnt <= 0;
            byte_valid <= 1'b1;
            byte_data <= shift;
          end else begin
            cnt <= cnt + 1;
          end
        end

        default: state <= Idle;
      endcase
    end
  end

endmodule
