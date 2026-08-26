# rtl/gf180mcu/

One implementation per technology-dependent cell: SRAM wrappers, clock cells, the boot ROM,
the clock generator, and the eFPGA stub. Nothing here should contain design logic.

Files here are intended for upstream, so match upstream's style and keep PDK cell
instantiation confined to this directory. Reference macros by cell name only; LEF, LIB and
GDS come from `PDK_ROOT` and must never be committed.

`make elaborate` lists every module the design instantiates but does not define, which is the
work list for this directory. It is currently empty.

Full reference: [docs/reference/rtl.md](../../docs/reference/rtl.md).
