# Licence

`SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1`

This repository is licensed under the Solderpad Hardware License, Version 2.1, which operates
as a wraparound license to the Apache License, Version 2.0.

This matches the licence of [openhwgroup/core-v-mcu](https://github.com/openhwgroup/core-v-mcu),
so RTL developed here can be contributed upstream without a licence change.

- Solderpad Hardware License v2.1: <https://solderpad.org/licenses/SHL-2.1/>
- Apache License v2.0: <https://www.apache.org/licenses/LICENSE-2.0>

The canonical text is reproduced in `core-v-mcu/LICENSE.md` in the submodule.

## Third-party components

The GF180MCU PDK, its standard cell, IO and SRAM libraries are licensed separately by
GlobalFoundries and Google under Apache-2.0. They are fetched at build time by `make pdk` and
are not redistributed here.
