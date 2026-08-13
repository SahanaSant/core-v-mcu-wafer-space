# Pad and IO budget: fit 57 signals into 56 pads

Type: grilling
Status: open
Blocked by: 02

## Question

A 1x1 slot provides 56 signal pads: 40 bidirectional, 14 input-only, 2 analog. Upstream needs
57. `core_v_mcu.sv` exposes `N_IO = 48` general-purpose pads plus `jtag_tck`, `jtag_tdi`,
`jtag_tdo`, `jtag_tms`, `jtag_trst`, `ref_clk_i`, `rstn_i`, `bootsel_i` and `stm_i`.

The proposal in `rtl/chip/README.md` is to drop `N_IO` from 48 to 40 and put the eight
remaining signals on input-only pads, with `jtag_tdo_o` sharing a bidirectional pad as an
output. That leaves `N_APBIO` overcommitted: GPIO(32) plus PWM(16) plus I2CS(3) is 51
functions competing for 40 pads.

So the real question is which functions lose their multiplexer entries. That is a product
decision, not a mechanical one, and it interacts with two other tickets: ticket 12 may remove
peripherals entirely, which frees their pads, and ticket 04 is now resolved — net **+3** pads
(4 new QSPI pins for SPI flash boot, 1 freed by dropping `bootsel_i`), well inside the 8-pad
slack this plan already has. Resolve after ticket 12 if the ordering allows, or resolve it
provisionally and revisit.

`pad_control.sv` and `safe_domain.sv` are generated files. The answer has to be expressed as
a modified `perdef.json` with the multiplexer regenerated through upstream's
`util/ioscript.py`. Hand-edited pad tables will drift from the software headers `make sw`
produces and will not be accepted upstream.

## Definition of done

A `perdef.json` on the fork that describes 40 bidirectional and 8 input-only signal pads,
with `pad_control.sv` and `safe_domain.sv` regenerated from it, `N_IO` and `N_APBIO` updated
in `pulp_soc_defines.svh`, and the design still elaborating. The answer records which
functions were cut and why.

## Answer

<!-- filled on resolution -->
