// Copyright 2026 Yusef Karim
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Latch technology map for gf180mcu_as_sc_mcu7t3v3.
//
// The PDK ships a latch_map.v for gf180mcu_fd_sc_mcu7t5v0 but not for this
// library, and area.sh needs one to keep `dfflibmap`-mapped flops and latches
// in the same netlist. See flow/synth/area.sh for how it is picked up.
//
// Pin names differ from the foundry library: these cells are sky130-style
// (dlxtp/dlxtn, enable pin ENA) rather than gf180-style (latq, enable pin E).
//
// The library has no set/reset latch, so there is no equivalent of the foundry
// map's $_DLATCH_PN0_ (latrnq_1) or $_DLATCH_PN1_ (latsnq_1). That is a real
// gap in the library, but not one this design hits: after flattening, the SoC
// keeps exactly four latches and all four are plain positive ones, so only
// $_DLATCH_P_ is actually exercised. A design that inferred a set/reset latch
// would leave it unmapped here rather than failing loudly, which is worth
// knowing before anyone treats this library as a drop-in replacement.

// positive D-latch, transparent when ENA is high
module \$_DLATCH_P_ (input E, input D, output Q);
    gf180mcu_as_sc_mcu7t3v3__dlxtp_2 _TECHMAP_REPLACE_ (
        .ENA (E),
        .D   (D),
        .Q   (Q)
    );
endmodule

// negative D-latch, transparent when ENA is low
module \$_DLATCH_N_ (input E, input D, output Q);
    gf180mcu_as_sc_mcu7t3v3__dlxtn_2 _TECHMAP_REPLACE_ (
        .ENA (E),
        .D   (D),
        .Q   (Q)
    );
endmodule
