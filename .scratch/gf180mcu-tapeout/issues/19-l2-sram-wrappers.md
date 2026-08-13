# Write the L2 SRAM wrappers and re-measure

Type: task
Status: open
Blocked by: none

## Question

Ticket 11 committed the configuration; this builds it. Nothing here is a decision.

Write `rtl/gf180mcu/gf180_interleaved_ram.sv` and `rtl/gf180mcu/gf180_private_ram.sv`, both
1024 words by 32 bits from four ganged `gf180mcu_ocd_ip_sram__sram1024x8m8wm1`. They are the
same module under two names, since ticket 11 sized both banks at 4 KiB, so write one body and
decide whether upstream's two module names justify two files or one file with two wrappers.

Apply the parameter set from ticket 11's answer:

| file | parameter | from | to |
| --- | --- | ---: | ---: |
| `rtl/includes/pulp_soc_defines.svh:32` | `NB_L2_CHANNELS` | 4 | 2 |
| `l2_ram_multi_bank.sv:23` | `BANK_SIZE_INTL_SRAM` | 32768 | 1024 |
| `l2_ram_multi_bank.sv:24` | `BANK_SIZE_PRI0` | 8192 | 1024 |
| `l2_ram_multi_bank.sv:25` | `BANK_SIZE_PRI1` | 8192 | 1024 |
| `soc_domain.sv:101` | `L2_BANK_SIZE` | 29184 | 1024 |

and the memory map, contiguous from `0x1C00_0000`: private bank 0 to `0x1C00_1000`, private
bank 1 to `0x1C00_2000`, interleaved TCDM to `0x1C00_4000`.

Points to get right rather than discover:

- **Pin mapping.** `CEN`, `GWEN` and `WEN[7:0]` are active low. The bus carries a 4-bit `be_i`,
  one bit per byte lane, and each macro is one byte lane, so macro `k` takes
  `WEN = {8{~be_i[k]}}`. Record the mapping in `rtl/gf180mcu/README.md` as the map's Notes
  require.
- **Instantiate, do not infer**, as ticket 16 established, which means `read_liberty -lib` on
  `gf180mcu_ocd_ip_sram` before `read_slang` in `filelist.sh` exactly as the clock cells needed.
  Without it yosys-slang stops on the unknown module.
- **Liberty `area` for these macros is wrong** by 1.35x, so if `area_report.py` starts counting
  macros, take their area from LEF `SIZE`. See ticket 20.
- Delete the matching stubs from `flow/synth/stubs.sv` as each wrapper lands.

## Definition of done

`make elaborate` reports two fewer black boxes. `make area` and `make sta` run to completion and
their new numbers are quoted, with the flattened total read against ticket 16's 0.3% precision
floor rather than as an exact delta. `rtl/gf180mcu/README.md` updated: the technology-cell table
loses both memory rows, `core_v_mcu_interleaved_ram` having gone from 4 instances to 2.

## Answer

<!-- filled on resolution -->
