# rtl/chip/

The wafer.space die: pad ring, power, and one instance of the upstream `core_v_mcu` SoC.
This is the boundary between upstream RTL and this shuttle, so it stays here and is never
contributed upstream.

`chip_top.sv` holds the pad cells and the five marker cells and nothing else, so its instance
names stay a one-to-one match for the pad lists in `flow/slot_1x1.yaml`. `chip_core.sv` is
everything between the ring and the SoC.

Pin-out, pad budget and configuration bits: [docs/reference/pinout.md](../../docs/reference/pinout.md).
