# Build the pinned PDK from source with the optional libraries enabled

Type: task
Status: resolved
Assignee: yusefkarim
Blocked by: 14

## Question

Can `ciel build` produce a `gf180mcuD` PDK at the pinned open_pdks commit that includes
`gf180mcu_ocd_ip_sram`, `gf180mcu_ocd_io` and `gf180mcu_as_sc_mcu7t3v3`, and is the result
still variant-pure?

**Ticket 14 widened this ticket from one library to three**, because a from-source build is
the expensive step and the marginal cost of each extra `-l` is small. Each answers a different
open question, and each is wanted for its own reason:

| Library | Wanted for | Question it answers |
| --- | --- | --- |
| `gf180mcu_ocd_ip_sram` | 2.6x density, the original reason | Does ticket 11 get 20.4 KiB or 7.7 KiB? |
| `gf180mcu_ocd_io` | separated core and IO supply domains | Can the die have a 5.0 V IO ring over a 3.3 V core? |
| `gf180mcu_as_sc_mcu7t3v3` | 3.3 V-native thin-oxide cells | Is there area or speed on the table against `fd_sc_mcu7t5v0`? |

Ticket 01 found that the prebuilt PDK `ciel enable` fetches carries only the `gf180mcu_fd_*`
libraries. Every non-foundry library is absent from `libs.ref` while still being referenced
elsewhere in the same tree: `libs.tech/magic/gf180mcuD.magicrc` adds a search path for
`gf180mcu_ocd_ip_sram` that does not exist, `.config/nodeinfo.json` pins it at commit
`efdbf734d806…`, and `libs.tech/librelane/` ships configs for `gf180mcu_ocd_io`,
`gf180mcu_as_sc_mcu7t3v3` and both `gf180mcu_osu_sc_*`. The pinned open_pdks knows about all
of them; this distribution simply did not build them.

The route is `ciel build` rather than `ciel enable`:

```
ciel build --pdk-family gf180mcu \
  -l gf180mcu_ocd_ip_sram -l gf180mcu_ocd_io -l gf180mcu_as_sc_mcu7t3v3 \
  -j <n> f6eeac7dad085ffcc829ccfd721f7b4ce39edcf7
```

`-l/--include-libraries` may be repeated, or take `all`. `nodeinfo.json` pins each of these
to a commit already (`efdbf734…`, `6e0e354a…`, `c35a86ac…`), so the versions are not a
choice.

This is the hidden cost of ticket 07's answer. The OCD macros are 2.6x denser and that is
what makes 32 KiB of L2 reachable, but ticket 11 cannot rest on a macro nobody has managed to
obtain. Ticket 14 chose a 3.3 V core, so this ticket is **in scope and unblocked**; had it
chosen 5.0 V the OCD macros would have been unusable regardless and this would have been
ruled out instead.

**What ticket 14 wants from `gf180mcu_ocd_io` specifically.** Its LibreLane config, which
ships in the pinned PDK at `libs.tech/librelane/gf180mcu_ocd_io/config.tcl`, lists two
`PAD_PLACE_IO_TERMINALS` entries that the `gf180mcu_fd_io` config does not have:

```
$::env(PAD_CELL_LIBRARY)__vss/VSS
$::env(PAD_CELL_LIBRARY)__vdd/VDD
```

Those are separate core power and ground pads. The foundry `fd_io` library has only `dvdd`
and `dvss`, which bond the IO rails and pass the core rails through unbonded, so a die built
from `fd_io` can only tie VDD to DVDD and be single-supply. Confirm the cells exist in the
built result, that they carry the level shifter between domains, and which supply corners
they are characterised at. Note the config maps the 3.3 V pad corners onto `ff_n40C_3v63` and
`ss_125C_2v97`, not the `3v60`/`3v00` names the standard cells use.

Watch for: whether the build needs network access or a GitHub token, whether it is
reproducible against the same commit, how long it takes, and whether anything it emits is
drawn against `gf180mcuC`. The last one is the important one. Ticket 08 died on exactly that
mismatch, and a from-source build is more likely to expose variant assumptions than a tarball
someone else validated.

## Definition of done

All three libraries exist under `pdk/gf180mcuD/libs.ref/` with LEF, Liberty and GDS,
produced from the pinned commit: `gf180mcu_ocd_ip_sram` with `sram1024x8m8wm1`,
`gf180mcu_ocd_io` with `__vdd` and `__vss` among its cells, and `gf180mcu_as_sc_mcu7t3v3`.
`make pdk` reaches that state from a fresh checkout, with the build flags recorded in the
Makefile rather than in a comment or in this ticket. The `gf180mcu_fd_*` libraries still work
afterwards, confirmed by re-running `make area`.

Then one measurement, since the build is the expensive part and this is nearly free:
`SCL=gf180mcu_as_sc_mcu7t3v3 make area`, compared against ticket 10's baseline of 311.3 kGE
and 3.417 mm² of cell area on `gf180mcu_fd_sc_mcu7t5v0`. A 3.3 V-native library uses
thin-oxide devices, so it may be smaller, faster or both at this supply, and area is the
binding constraint. **This measures, it does not switch**: changing the committed library is
a separate decision, taken on the number this produces.

Record the wall-clock build time, since it lands in the Run 3 schedule.

## Answer

**Yes, all three, and the result is variant-pure. But `ciel build` cannot do it**, and the
command in the question above would have quietly destroyed the working PDK. The build is now
`flow/pdk/build.sh`, driving open_pdks directly, and `make pdk` runs it.

All eight libraries are in `pdk/gf180mcuD/libs.ref/` with LEF, Liberty and GDS, from the pinned
open_pdks commit. `gf180mcu_ocd_ip_sram` has `sram1024x8m8wm1`, `gf180mcu_ocd_io` has `__vdd`
and `__vss`, `gf180mcu_as_sc_mcu7t3v3` is there. Nothing inside `gf180mcuD` references variant
A, B or C.

### Four things sat between `ciel build` and a PDK

Each is silent or misleading on its own, and the ticket's one-line command hits all four.

1. **`-l` is a whitelist, not an addition.** `ciel build` passes `--disable-<lib>` to open_pdks
   for every library it is *not* given. The command above names only the three new libraries, so
   it would have produced a PDK with no foundry standard cells at all, replacing a working one.
   The five `gf180mcu_fd_*` are only present by being ciel's default set.
2. **`HOME` has to be neutralised.** open_pdks does `unexport PDK_ROOT` on purpose
   (`gf180mcu/Makefile:101`) so a build cannot pick up an installed PDK. The toolchain image
   ships `/headless/.magicrc` that dereferences `$env(PDK_ROOT)` with no `catch`, so every magic
   call fails to parse its startup file, loses the technology, and the build dies. Reproducible
   in one line: `env -u PDK_ROOT magic -dnull` prints the exact error. Setting `PDK_ROOT` also
   silences it, but by sourcing the **previously installed PDK's tech file while building the
   new one**, which is precisely the contamination this ticket exists to avoid. Point `HOME` at
   an empty directory instead.
3. **Magic segfaults, intermittently.** The container has magic 8.3.678; this open_pdks commit
   was built with 8.3.674 (`.config/nodeinfo.json`). It faults with SIGSEGV in the io stage,
   reading the efabless custom pad `gf180mcu_ef_io` and writing its LEF back out. Genuinely
   nondeterministic: the same variant from identical sources crashed on one run and completed on
   the next, and it has hit variants B and D. The successful build took **three attempts**.
   `build.sh` retries up to four times from clean staging, and refuses to retry anything that is
   not this signature.
4. **`run.sh` does not forward `PDK_COMMIT`.** It only passes the variables it names, so the
   build script gets it explicitly. The standing trap, hit again.

### Why not `ciel build`

The one flag that matters is `--with-gf180mcu-variants=D`, and ciel hardcodes its configure
flags. Building only gf180mcuD halves the work, and this design is gf180mcuD-only anyway. It
also **removes a hazard the map lists**: `pdk/` no longer carries `gf180mcuA` through `D` as
symlinks into one version, so a mistyped variant name now fails instead of resolving to a real
populated directory.

Two further open_pdks details forced the shape of the script. `tech-%` invokes the real build as
`${MAKE} -j$(nproc) all`, with the job count **hardcoded**, so a `-j` from outside is ignored;
`build.sh` runs `make` in the `gf180mcu` subdirectory so `PDK_JOBS` means something. And
`make install` is unusable for one variant, because `install-B` depends on `install-A`, `C` on
`B`, `D` on `C`, a chain that ignores `VARIANTS` and dies on the first missing directory. The
script calls `staging_install.py` directly with `-link_from none`, which is also what makes the
result self-contained: the Makefile would have linked D's files back to a gf180mcuA that was
never built.

### The foundry libraries are unchanged, and that is measured

Every `gf180mcu_fd_*` library matches the prebuilt distribution file-for-file across lef, lib,
gds, spice, verilog, techlef, mag, maglef and cdl. Functionally too: `make area` returns
**118,998 cells and 3,416,649 um2**, identical to ticket 14. The from-source build reproduces
the distribution rather than approximating it.

### `gf180mcu_as_sc_mcu7t3v3`: measured, and the answer is no

`SCL=gf180mcu_as_sc_mcu7t3v3 make area` against ticket 10's baseline:

| library | cells | cell area (um2) | for SRAM |
| --- | ---: | ---: | ---: |
| `gf180mcu_fd_sc_mcu7t5v0` | 118,998 | 3,416,649 | 3.16 mm2, 20.4 KiB OCD |
| `gf180mcu_as_sc_mcu7t3v3` | 113,288 | 3,614,711 | 2.59 mm2, 16.7 KiB OCD |

**5.8% larger**, on fewer cells. The library has no `_1` drive strength of anything: its
smallest NAND2 is `nand2_2` at 15.366 um2 against the foundry `nand2_1`'s 10.976. It is 82 cells
against 229, three corners against fifteen, and an `lctime_templates` directory says it was
characterised with the open-source characteriser rather than by the foundry. There is no area on
the table, so **do not switch**, and the thin-oxide question is closed on measurement.

Watch the kGE column, which reads *lower* for this library (235.2 against 311.3) purely because
the reference cell is bigger. Comparing kGE across libraries is meaningless; compare um2.
`area_report.py` now picks the smallest `nand2_*` present and names it in the report, because a
fixed `nand2_1` simply does not exist here.

Speed is **not** measured. `sta.sh` reports two supply corners and this library has only the
three 3.3 V ones, so the 5.0 V arm cannot be built without reworking it. Not worth doing: area
is the binding constraint and the library already loses on it.

### What this hands the tickets downstream

**Ticket 11 gets more than it asked for.** `gf180mcu_ocd_ip_sram` ships **four** macro sizes,
not the one ticket 07 knew about: `sram64x8m8wm1`, `sram256x8m8wm1`, `sram512x8m8wm1` and
`sram1024x8m8wm1`, ten corners each at 1.8 V and 3.3 V, no 5 V. That is real banking
granularity. It also ships its own rebuild of the foundry `sram512x8m8wm1`, so the 2.6x density
claim can be checked at **equal capacity** instead of extrapolated across sizes.

**Ticket 18 has its answer on the supply domains.** `gf180mcu_ocd_io` is `gf180mcu_fd_io` plus
exactly three cells: `bi_a`, `__vdd`, `__vss`. Twelve corners, at 2.5 V, 3.3 V **and 5.0 V**, so
a 5 V ring over a 3.3 V core has characterised data behind it. The decisive evidence is in the
SPICE: `gf180mcu_ocd_io__vdd` bonds VDD/VSS and marks `* noconn DVDD` and `* noconn DVSS`, so it
passes the IO rails through untouched, with a 4 mm NMOS ESD clamp across the core rail. The
foundry `gf180mcu_fd_io__dvdd` has ports `DVDD DVSS VSS` and **no VDD port at all**, which is
ticket 14's "the foundry pads short the core and IO domains" seen at device level. Both
libraries' `bi_t` already carry separate VDD and DVDD; what `fd_io` lacked was any way to bond
the core rail.

One caution for ticket 18: `libs.tech/librelane/gf180mcu_ocd_io/config.tcl` sets `PAD_CDLS ""`
where `fd_io` inherits real CDL. `ocd_io`'s SPICE is a proper hierarchical netlist rather than a
stub, so the data exists, but the LibreLane integration does not point at it, and the
destination is a clean precheck.

### Cost, for the Run 3 schedule

About **10 minutes per attempt** for one variant, plus roughly 2 minutes of cloning on a cold
build. The segfault makes the expected cost a multiple of that: the successful run took three
attempts, **30 minutes** in total. Budget an hour and do not put it on the critical path of
anything time-boxed. The host was under real memory pressure throughout (358 MB free, 8.9 GB
swapped), which is an untested but plausible contributor to the crash rate; a machine with more
free RAM may well do this in one attempt.

`pdk/ciel/gf180mcu/versions/<commit>/gf180mcuD.prebuilt` is the original downloaded PDK, kept
as a fallback. It is 907 MB and can be deleted once the rebuilt one has been trusted for a
while.

### Traps for the next session

- **Liberty declares cells three different ways in one PDK.** `cell(` with no space in the
  foundry standard cells, `cell (` with a space in `gf180mcu_as_sc_mcu7t3v3`, and tab-indented
  `cell ("name")` with quotes in both IO libraries. A grep tuned to any one returns a confident
  zero on the others. Ticket 14 was nearly caught by the first; there are three.
- **`/usr/bin/time` is not installed on this host.** Wrapping a build in it produces a no-op
  that still reports success through the wrapper.
- `(UNNAMED)` in a build log is **benign**: `create_gds_library.py` deletes that cell by name as
  a matter of course. It is not a failure, and it appears in successful builds.
