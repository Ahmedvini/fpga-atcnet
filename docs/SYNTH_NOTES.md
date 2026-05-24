# Synthesizing DB-ATCNet on Vivado — gotchas

## Why "Run Synthesis" in the GUI blows IOB budget

If you create a project with `db_atcnet_axi` (or any AXI top) as the
top-level and click **Run Synthesis**, Vivado tries to bond every
port of the top to a physical pin. The wrapper has:

```
clk, rst                                    (2 IOs)
s_axis_tdata[31:0], tvalid, tready, tlast   (35 IOs)
s_axi_*  (write + read channels)            (~140 IOs)
irq_done                                    (1 IO)
```

≈ 180 IOs. Multiply for unpacked signals → Vivado tries to grab thousands of
IOBs (the screenshot of `eeg_security_top` showed **10,520** Bonded IOBs vs
360 available — that's why the row is red).

The fix is **out-of-context synthesis**: the synthesizer treats the design
as a sub-block, *doesn't* insert I/O buffers, and resource counts only the
real internal logic.

## Three correct ways to synthesize

### A — Tcl batch (recommended, fully automated)

```bash
cd /home/ahmedelsheikh/Documents/GitHub/fpga-atcnet-main
vivado -mode batch -source synth/synth_fit.tcl \
       -tclargs xczu7ev-ffvc1156-2-e
```

This:
1. Creates an in-memory project against the ZCU104 part.
2. Adds every RTL file + the constraints file.
3. Adds every weight/LUT `.hex` under `data/golden_q88/` and `data/lut/`
   as a Memory Initialization File, and binds them as `-generic`
   parameter strings on the `db_atcnet_axi` top.
4. Calls `synth_design -mode out_of_context`.
5. Writes `build/synth_<part>/utilization.txt` + `timing.txt`.

Host needs ≥ 12 GB RAM (Vivado peaks ~10 GB during DSP packing on this
design size). If you OOM-killed, free up memory / close other apps.

### Why every `*_FILE` generic MUST be bound

The NN modules — `conv2d_temporal`, `depthwise_spatial`,
`conv1d_temporal_tm`, `tcfn`, `dense_classifier`, `eca_attention`,
`cbam_channel_attn`, `cbam_spatial_attn` — store their weights and
sigmoid/ELU LUTs in internal arrays initialised at elaboration via
`$readmemh(WEIGHTS_FILE, …)`. If the parameter is the default empty
string, `$readmemh` is a silent no-op. The array stays all-zero,
Vivado constant-propagates the entire datapath into a single
"output = 0" wire, and synthesis reports something like:

```
LUTs: 304   FFs: 264   DSPs: 0   BRAMs: 0
```

That is the design *synthesised out of existence*, not a successful
fit. Look for tell-tale log lines:

```
WEIGHTS_FILE bound to: (null)
WARNING: [Synth 8-6014] Unused sequential element shift_reg_reg[…] was removed
```

`synth_fit.tcl` guards against this by `add_files`-ing every `.hex`
into the project as a Memory Initialization File AND passing each
`-generic <NAME>=<path>` on the `synth_design` command. The script
aborts early if any file is missing.

### Weights are baked into the bitstream (current limitation)

The PS uses AXI-Lite for the `status` / `class` mailbox and `irq_done`,
but the NN weights are ROM in this build — retraining requires
re-running `synth_fit.tcl` with the new `.hex` files. The scaffolding
for runtime weight reload (`rtl/weights/weight_bank.sv`,
`rtl/weights/axi_lite_weight_loader.sv`) is present but the NN modules
don't yet instantiate `weight_bank` — they own their own static arrays.
Wiring that through is a future refactor.

### B — Vivado GUI, OOC project

1. Vivado → Manage IP → Create New Project, Part = `xczu7ev-ffvc1156-2-e`.
2. Add every `.sv` under `rtl/`.
3. Add `constraints/db_atcnet_axi.xdc`.
4. Add every `.hex` under `data/golden_q88/` and `data/lut/` as
   *Memory Initialization Files* — without these the network synthesises
   to a constant zero (see warning above).
5. Set Top = `db_atcnet_axi`.
6. Project → **Generics / Parameters** → set every `*_FILE` parameter
   (see `synth/synth_fit.tcl` for the full list) to its `.hex` path.
7. Right-click the synthesis run → **Synthesis Settings** → check
   *"Out-of-context"* OR set `-mode out_of_context` in the `more options`.
8. Run Synthesis.

Path A (the Tcl batch flow) does all of 4/6/7 automatically — strongly
preferred unless you specifically need the GUI run.

### C — Inside an IPI block design (final deployment path)

1. Create a Block Design.
2. Add Zynq UltraScale+ MPSoC, enable PL_CLK0 = 100 MHz, M_AXI_HPM0_FPD,
   S_AXI_HPC0_FPD, IRQ0 → PL→PS.
3. Add an AXI-DMA, hook MM2S → s_axis_*.
4. Add `db_atcnet_axi` as a custom RTL module (Add Module → pick the file).
5. Connect:
   - `clk` ← PL_CLK0
   - `rst` ← Processor System Reset
   - `s_axi_*` ← AXI Interconnect from M_AXI_HPM0_FPD
   - `s_axis_*` ← AXI-DMA MM2S
   - `irq_done` → IRQ0
6. **Validate Design** then **Create HDL Wrapper** then **Run Synthesis** /
   Run Implementation / Generate Bitstream.

In this flow the ports of `db_atcnet_axi` are all internal to the IPI
diagram and IOBs only get inserted for the chip-edge pins (clock, MIO,
DDR) that the PS owns.

## Constraints

`constraints/db_atcnet_axi.xdc` ships in this repo with:
- `create_clock -period 10.000 [get_ports clk]` (100 MHz).
- I/O delay defaults so timing reports aren't spammed by unconstrained ports.
- `RAM_STYLE = block` hints on the ECA₁ replay buffer (`buf_mem_reg`),
  the branch pipeline's pre/post-conv buffers, etc.
- `RAM_STYLE = ultra` hints on the TCFN weight banks (16 k entries each →
  good URAM fit on ZCU104's 96 URAMs).

If you build via IPI you can keep this XDC; it only references signals
exported through the wrapper.

## Resource expectations (estimated for ZCU104)

| Resource | Estimate | ZCU104 budget | Util |
|---|---|---|---|
| LUTs    | ~30 k | 230 k | ~13 % |
| FFs     | ~50 k | 460 k | ~11 % |
| DSP48E2 | ~250  | 1,728 | ~14 % |
| BRAM36  | ~50   | 312   | ~16 % |
| URAM    | ~10   | 96    | ~10 % |

The big drivers are:
- The 96 KB ECA₁ replay buffer → ~22 BRAMs.
- TCFN weight banks (~80 KB across 5 windows) → 4-8 URAMs (or 20 BRAMs).
- conv2d_temporal (KE=64, F1=16, fully parallel) → ~64 DSPs.
- conv1d_temporal_tm (one shared bank, F_OUT-parallel) → 32 DSPs.
- chan/spat/cls dense MACs → ~50 DSPs.

Plenty of headroom on ZCU104. The same design **does not fit Z-7020**
(220 DSPs, 140 BRAMs) without further time-multiplexing of conv2d_temporal
and reusing the weight RAMs more aggressively.
