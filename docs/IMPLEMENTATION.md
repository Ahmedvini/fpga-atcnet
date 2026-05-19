# DB-ATCNet FPGA Implementation — Engineering Reference

**Project**: Bit-exact RTL inference of HaLT DB-ATCNet (2-class motor-imagery EEG
classifier) targeting Zynq Ultrascale+ (XCZU7EV, ZCU104) with Z-7020 considered
as a low-end target.

**Status (this document)**: simulation-verified end-to-end, synthesis-ready;
deployed via AXI-Stream input + AXI-Lite control wrapper.

---

## 1. Problem statement & scope

DB-ATCNet is a deep neural network for binary EEG motor-imagery classification
(Right Hand fist vs Left Leg ankle) trained per-subject on the HaLT dataset
(19-channel scalp EEG @ 200 Hz, 3-second trials = 600 samples). The reference
implementation (Keras, float32) achieves **95.72 % ± 2.13 %** accuracy on
Subject A across three folds. The fold deployed in this implementation is
Subject A's session-3-heldout fold (Gumbel-selected channels
`[9, 11, 12, 14, 3]` = O2, F8, T3, T5, F4).

The deliverable is a fully synthesizable SystemVerilog implementation that:

1. Accepts a 19-channel raw EEG trial via AXI4-Stream.
2. Performs the entire forward pass (Gumbel selection → Conv2D → ECA₁ →
   Branch A + Branch B → Add → ECA₂ → 5-window pipeline with ImpCBAM + TCFN
   + per-window Dense → Average + argmax) in fixed-point Q8.8 arithmetic.
3. Emits a 1-bit class prediction via AXI4-Lite mailbox in ~1.15 ms @ 100 MHz
   (vs the 3-second EEG window — three orders of magnitude faster than
   real-time).
4. Supports runtime weight reload (per-subject retraining) without
   re-synthesis, using the same AXI-Lite slave port.

The reference for every numerical result is a per-layer Python script
(`scripts/q88_*.py`) that ingests the trained `.h5` and emits Q8.8 hex
artifacts. The RTL is bit-exact against those artifacts for every layer and
for the final argmax.

---

## 2. Numerical methodology — Q8.8 fixed point

### 2.1 Format

All activations, weights, and biases are signed 16-bit integers interpreted
as **Q8.8** (1 sign bit + 7 integer bits + 8 fractional bits). Saturating
arithmetic on overflow:

```
Q8.8 range = [-32768, 32767] / 256 = [-128.0, 127.996...]
LSB         = 1/256 ≈ 0.0039
```

Multiply-accumulate uses a 48-bit signed accumulator (`ACC_WIDTH=48`) — enough
headroom for the largest fan-in (TCFN: K=4 taps × F_IN=32 channels × 5
sliding windows accumulated separately, but always within a single dot
product the worst case is 4·32·(2^15)² ≈ 2^36).

### 2.2 BatchNorm folding

BN layers are fused into the preceding conv at export time:

```
scale[f]  = γ[f] / sqrt(σ²[f] + ε)
bias[f]   = β[f] - μ[f] · scale[f] + b_conv[f] · scale[f]
W_folded  = W_conv ⊙ scale (broadcast over output channel)
```

Removes runtime divides/sqrts. `ε = 1e-3` matches Keras default. This
collapses Layers 1+2, 4+BN, 7+BN, 10+BN, 13+BN, and the 20 TCFN BNs into
single bias-adjusted conv weights.

### 2.3 Reciprocal-multiply for division

Hardware-friendly substitute for the GlobalAveragePool and AvgPool
divisions:

```
INV_N      = round(2^24 / N)             # precomputed once
GAP_q88[c] = sat( (sum_q88[c] · INV_N) >>> 24 )
```

Used in `gap_accumulator.sv` (ECA₁ N=3000, ECA₂ N=10, ImpCBAM-channel
N=6, ImpCBAM-spatial N=32). For N=32 the shift-only form is exact
(N=2^5 → INV_N=2^19, `>>>5` is identical), used directly in spatial CBAM.

### 2.4 Sigmoid + ELU via universal LUTs

Both transcendentals are implemented as per-input-range lookup tables
loaded once from `data/lut/sigmoid_q88.hex` / `data/lut/elu_q88.hex`:

| LUT | Entries | Range | Addressing |
|---|---|---|---|
| Sigmoid | 1024 | ±4.0 | `addr = (clip(x, ±LUT_RANGE) + LUT_RANGE) >>> 1` |
| ELU (α=1) | 256 | only x<0 needed; x≥0 passes through | `addr = (-x) >>> 3`, clip to LUT_N-1 |

Both LUTs are subject-independent (universal mathematical functions), so
they compile into the bitstream as $readmemh ROMs.

### 2.5 Stochastic pool (ImpCBAM spatial)

The CBAM spatial attention's third descriptor (in addition to avg and max
pools across channels) is a *stochastic pool* — deterministic at inference:

```
norm[t]      = sum_c |x[t,c]|
inv_norm[t]  = floor(2^24 / max(norm[t], 1))      # one serial divide / t
stoch[t]     = sat( (sum_c (|x| · inv_norm[t]) · x[t,c]) >>> 24 )
```

We factor the division out of the per-channel loop so only **one** integer
division is needed per timestep (5 windows × 6 timesteps = 30 divisions
per inference total, ~960 cycles). The divider is a radix-2 restoring
integer divider (`rtl/util/serial_divider.sv`, 32-bit num / 25-bit denom,
~32 cycles per op).

### 2.6 Quantization-induced behavior

* **Saturation**: occurs in TCFN intermediate activations (the four
  cascaded Conv1D with no rescaling can drive Q8.8 values past ±128 in
  worst-case channels). Both Python and RTL saturate identically; the
  test remains bit-exact at the saturation boundary.
* **ECA reciprocal-multiply rounding**: with N=3000 the 1/3000-class
  difference between including or excluding any single sample in the
  GAP sum is below 1 LSB and rounds away. With N=10 (ECA₂) the same
  bug would produce visible mismatches — caught and fixed during
  development (see § 4.5).

---

## 3. Architecture & module hierarchy

### 3.1 Top-level diagram

```
                ┌────────────────────────────────────────────┐
                │              db_atcnet_axi.sv               │
                │  ┌───────────────────────────────────────┐ │
   AXI-Stream───┤  │  gumbel_channel_adapter.sv (19→5)     │ │
   (19ch raw    │  └──────────────────┬────────────────────┘ │
    EEG)        │                     │ (5ch raw EEG)        │
                │  ┌──────────────────▼────────────────────┐ │
                │  │  db_atcnet_top.sv                      │ │
                │  │  ┌──────────────────────────────────┐ │ │
                │  │  │ db_atcnet_conv2d_eca1.sv         │ │ │
                │  │  │   conv2d_temporal + eca1_pipe    │ │ │
                │  │  └────────────┬─────────────────────┘ │ │
                │  │               │ (T=3000, F1=16 gated) │ │
                │  │  ┌────────────▼─────────────────────┐ │ │
                │  │  │ db_atcnet_post_eca1.sv           │ │ │
                │  │  │   branchA + branchB              │ │ │
                │  │  │   + sat_add + eca1_pipe (ECA₂)   │ │ │
                │  │  └────────────┬─────────────────────┘ │ │
                │  │               │ (eca2_buf: 10×32)     │ │
                │  │  ┌────────────▼─────────────────────┐ │ │
                │  │  │ db_atcnet_window_pipeline.sv     │ │ │
                │  │  │   for w in 0..4:                 │ │ │
                │  │  │     ImpCBAM-channel + spatial    │ │ │
                │  │  │     + TCFN + Dense(2)            │ │ │
                │  │  │   output_head: Σ logits + argmax │ │ │
                │  │  └────────────┬─────────────────────┘ │ │
                │  └───────────────┼───────────────────────┘ │
                │                  │ class_out[0]            │
   AXI-Lite◄────┤  status / class register mailbox          │
   (control     │  axi_lite_weight_loader → fan-out wr_en/  │
    + weights)  │  wr_addr/wr_data broadcast to every bank  │
                └────────────────────────────────────────────┘
```

### 3.2 Compute primitives

Each is a self-contained, parameterized RTL module verified bit-exact
against `scripts/q88_*.py` via an independent SystemVerilog testbench.

| Module | Math | Resource pattern |
|---|---|---|
| `conv/conv2d_temporal.sv` | per-electrode temporal Conv2D, KE=64, F1=16, same-pad | KE·F1 = 1024 mults, fully parallel |
| `conv/depthwise_spatial.sv` | depthwise (1, C_IN=5), D∈{2,4}, per-timestep emit | Streaming, C_IN·F2 mults across 5 cycles |
| `conv/elu.sv` | per-channel ELU LUT | NUM_CH parallel LUT lookups |
| `conv/avg_pool_time.sv` | AvgPool (POOL,1), reciprocal-multiply | NUM_CH mults at flush |
| `conv/conv1d_temporal.sv` | F_OUT × F_IN × KE fully-parallel separable conv | 16,384 mults (US+ only) |
| `conv/conv1d_temporal_tm.sv` | **Time-multiplexed** variant: F_OUT-parallel, KE·F_IN cycles/sample | 32 mults, 514 cycles/sample — synth-fit for Z-7020 + US+ |
| `conv/sat_add.sv` | saturating signed Q8.8 add | NUM_CH adders |
| `conv/tcfn.sv` | TCFN: 4 causal dilated Conv1D + BN + ELU + 3 residual adds | F_IN-parallel MACs, ~768 cycles/conv, internal weight banks N_WIN=5 |
| `attention/gap_accumulator.sv` | streaming GAP w/ reciprocal-multiply | NUM_CH accumulators |
| `attention/eca_attention.sv` | 3-tap Conv1D + sigmoid LUT | NUM_CH × 3 mults |
| `attention/gate_apply.sv` | per-channel Q8.8 multiply + saturate | NUM_CH mults |
| `attention/cbam_channel_attn.sv` | Avg+Max GAP → shared Dense(R)+ReLU+Dense(C) → sigmoid → gate | 2·R·C mults, N_WIN-banked |
| `attention/cbam_spatial_attn.sv` | Avg+Max+Stochastic over C → Conv2D(7,7,3,1) → sigmoid | Uses serial divider; collapsed 1D-conv |
| `classifier/dense_classifier.sv` | Dense(F → N_CLS) | F·N_CLS mults, N_WIN-banked |
| `classifier/output_head.sv` | sum logits across N_WIN windows, argmax | N_WIN × N_CLS additions, 1-cycle compare tree |
| `util/serial_divider.sv` | radix-2 restoring divider | ~32 cycles, generic |
| `window/gumbel_channel_adapter.sv` | 19→5 electrode select with runtime LUT, handles LUT duplicates | 5 comparators, match-mask drain FSM |
| `weights/axi_lite_weight_loader.sv` | AXI4-Lite slave shim | Pure protocol, broadcasts (wr_en, wr_addr, wr_data) |
| `weights/weight_bank.sv` | generic Q8.8 weight RAM, PACK_2 byte-decode, $readmemh init for sim | BRAM/URAM (synthesized), N×16-bit entries |

### 3.3 Orchestrators (build a graph from the primitives)

| Module | Responsibility |
|---|---|
| `attention/eca1_pipeline.sv` | Ingest N_FRAMES (NUM_CH)-wide vectors, compute gate, replay through gate_apply. Reused as ECA₁ (NUM_CH=16, N=3000) and ECA₂ (NUM_CH=32, N=10). |
| `conv/branch_pipeline.sv` | One full branch: dwise → ELU → pool(8) → sep (time-mux) → ELU → pool(7). Same module for Branch A (D=2) and Branch B (D=4). |
| `db_atcnet_conv2d_eca1.sv` | Raw 5-channel EEG → ECA₁-gated stream (chains conv2d_temporal + eca1_pipeline, drops first KE-1 warmup outputs). |
| `db_atcnet_post_eca1.sv` | ECA₁-gated stream → eca2_buf[10][32] (two branches in parallel + sat_add + ECA₂). |
| `db_atcnet_window_pipeline.sv` | eca2_buf → 1-bit class (5 sliding windows, single-instance cbam_channel/spatial/tcfn/dense + output_head). |
| `db_atcnet_top.sv` | Composition of all three orchestrators with start/done handshakes. |
| `db_atcnet_axi.sv` | Deployment wrapper: AXI-Stream input + AXI-Lite control & weight load + IRQ output. |

### 3.4 Single-instance / time-multiplex design choice

The 5-window sliding pipeline is implemented as **one instance** of each
learnable block (ImpCBAM-channel, ImpCBAM-spatial, TCFN, Dense classifier)
with **N_WIN-banked internal weight RAMs** addressed by a `window_idx`
input that switches each window pass.

* Area: 1× block instead of 5× → fits ZCU104 comfortably and would fit
  any board that holds the underlying block (Z-7020 marginally).
* Latency: 5 × per-block latency (acceptable: ~16 k cycles total for the
  window pipeline at 100 MHz = 167 µs vs the 3-s acquisition window).
* Runtime weight reload: AXI-Lite writes target any one of the 5 banks
  by base-address, so retraining a single window's classifier doesn't
  require re-synthesis.

The same N_WIN parameter (default 1, set to 5 in `db_atcnet_top`) keeps
the per-block testbenches working in both single-window debug mode and
multi-window deployment mode, with a single source of truth in the RTL.

---

## 4. Verification methodology

### 4.1 Bit-exact Python golden + SystemVerilog regression

The verification strategy is **forward** rather than co-simulation. For
each model layer we wrote a Python script (`scripts/q88_*.py`) that:

1. Loads the trained Keras `.h5` weights.
2. Applies the same fixed-point quantization the RTL will see (Q8.8,
   integer math, explicit saturation, reciprocal-multiply for divisions,
   identical LUT lookups).
3. Emits one `.hex` file per data tensor and per weight tensor.

Each SystemVerilog testbench then drives the matching RTL module from
the input `.hex`, captures the output, and compares against the expected
`.hex` byte-for-byte. **Pass = zero mismatches across the entire output
vector**.

This catches every mismatch — rounding, saturation, indexing,
endianness, signed/unsigned, off-by-one — at the *layer* level, so when
the integration testbenches run, any divergence localises immediately
to the most recently-added stage.

### 4.2 Test inventory

26 testbenches in `sim/run_vivado_tests.sh`, all PASS bit-exact:

| Layer / module | TB |
|---|---|
| Conv2D + BN (Layer 1+2) | `conv2d_temporal` |
| ECA₁ Conv1D + sigmoid | `eca` / `gap` / `gate_apply` |
| Branch A dwise (D=2) | `dwise_a` |
| Branch A ELU + pool(8) | `elu` / `pool1_a` |
| Branch A separable Conv2D | `sep_a` |
| Branch A pool(7) | `pool2_a` |
| Branch B dwise (D=4) | `dwise_b` |
| Branch B separable | `sep_b` |
| Add(A, B) | `sat_add` |
| ECA₂ integrated | `eca2` |
| ImpCBAM channel attn (window 0) | `chan_w0` |
| Serial divider | `divider` |
| ImpCBAM spatial attn (window 0) | `spat_w0` |
| TCFN (window 0) | `tcfn_w0` |
| Dense classifier (window 0) | `dense_w0` |
| Output head | `head` |
| All-windows: ImpCBAM-chan / -spat / TCFN | `chan_all` / `spat_all` / `tcfn_all` |
| 5-window pipeline | `pipe` |
| Time-mux Conv1D (Branch A, B) | `sep_a_tm` / `sep_b_tm` |
| ECA₁ orchestrator | `eca1_pipe` |
| Branch A/B pipelines | `branchA_pipe` / `branchB_pipe` |
| ECA₂ orchestrator (reuse eca1) | `eca2_pipe` |
| Post-ECA₁ orchestrator | `post_eca1` |
| Conv2D + ECA₁ wrapper | `c2e1` |
| **End-to-end RTL inference** | **`top`** |
| AXI-Lite weight loader | `axil` |
| Gumbel adapter (no-dup + duplicate LUT) | `gca` |

### 4.3 End-to-end result

```
[top_tb] class_out = 0 (expected 0)
[top_tb] PASS
$finish called at time : 1,154,535 ns
```

= 115,453 cycles = **1.15 ms at 100 MHz** to classify a 3-second 5-channel
EEG trial. Class 0 = Right Hand fist, matching `scripts/q88_end_to_end.py`
(which itself matches the float Keras model's argmax).

### 4.4 Synthesis verification

`build.sh` runs `xvlog + xelab` on the complete RTL tree against the
`db_atcnet_axi` top. Clean parse and elaboration:

```
[build] xvlog parse-check (model + security)...
[build] xvlog: clean
[build] xelab elaborate top='db_atcnet_axi'...
[build] done.
```

`synth/synth_fit.tcl` provides a Vivado out-of-context synth path for
ZCU104 (XCZU7EV-2FFVC1156). The XDC at `constraints/db_atcnet_axi.xdc`
constrains the 100 MHz `clk`, declares I/O delays, false-paths the
reset, and adds `RAM_STYLE block / ultra` hints so the large buffers
target BRAM/URAM rather than registers.

### 4.5 Notable bugs caught during development

These are the ones worth highlighting in a methodology section:

| Bug | Symptom | Fix | Where |
|---|---|---|---|
| Signed × unsigned multiply | Negative GAP values became huge positives | `$signed({1'b0, INV_N_WIDTH'(INV_N)})` | ECA pipelines |
| Bit-slicing strips signed | Comparing `s > SAT_HI[15:0]` ran unsigned | Use properly-sized signed constants | Channel CBAM saturation |
| `-x` overflow at INT_MIN | ELU(-32768) read wrong LUT slot | Sign-ext to 17 bits before negation | `elu_q88` in TCFN |
| Tap order mismatch | Causal conv weights applied in reverse | `back = conv_k × dilation` (not `(K-1-conv_k)·d`) | `tcfn.sv` |
| frame_last latched off-by-1 | gap_acc missed the last input → hung in S_WAIT_GATE | Make `frame_last_internal` combinational | `eca1_pipeline.sv` |
| GAP missed first sample | ECA₂ visibly off (1/10 LSB), ECA₁ silently identical | Gate gap_acc with `(state==IDLE \|\| state==INGEST) && x_valid` | `eca1_pipeline.sv` |
| Accumulator state leakage across windows | 1-LSB drift on every window after the first | Add `frame_started` flag, reset acc on first x_valid of a fresh frame | `cbam_channel_attn.sv` |
| S_READY never exits | Spatial attn hung after first window | Auto-transition to S_IDLE after last apply_valid | `cbam_spatial_attn.sv` |
| NORM_WIDTH=24 truncates 2^24 | Stochastic-pool quotient was always 0 | Bump NORM_WIDTH ≥ 25 | `cbam_spatial_attn.sv` |
| Naive AXIS handshake double-issues | TB pulsed `tvalid` twice within one `tready=1` window | Poll `in_ready` at each posedge before driving | conv1d_tm test pattern |

---

## 5. Performance & resource characterization

### 5.1 Latency breakdown (sim, 100 MHz)

| Stage | Cycles | Time |
|---|---|---|
| Conv2D streaming (KE=64 same-pad) | 3315 | 33 µs |
| ECA₁ ingest + gate + replay | ~6300 | 63 µs |
| Branch A (D=2) end-to-end | ~46 k | 460 µs |
| Branch B (D=4) end-to-end (parallel with A) | ~92 k | 920 µs |
| sat_add + ECA₂ | ~30 | <1 µs |
| 5-window pipeline | ~16 k | 167 µs |
| **End-to-end** | **~115 k** | **1.15 ms** |

Branch B dominates because its time-multiplexed Conv1D has 2× the `F_IN`
(64 vs 32) and therefore 2× cycles per output sample. The branches run
*in parallel* in the post-ECA₁ orchestrator, so the wall-clock cost is
Branch B's time, not the sum.

### 5.2 Resource estimate (ZCU104 / XCZU7EV)

| Resource | Estimate | Budget | Utilisation |
|---|---|---|---|
| LUTs    | ~30 k | 230,400 | ~13 % |
| FFs     | ~50 k | 460,800 | ~11 % |
| DSP48E2 | ~250  | 1,728   | ~14 % |
| BRAM36  | ~50   | 312     | ~16 % |
| URAM    | ~10   | 96      | ~10 % |

Dominant consumers:

* `conv2d_temporal` fully-parallel KE·F1 = 1024 mults → ~64 DSPs (each
  DSP48E2 packs 16-bit × 16-bit mult + 48-bit accumulator).
* `conv1d_temporal_tm` shared across A/B → 32 DSPs each instance.
* TCFN/CBAM/Dense dense MACs → ~100 DSPs total across the 5 instances.
* `eca1_pipeline.buf_mem` = 3000 × 16 × 16 bits = 96 KB → ~22 BRAM36.
* TCFN weight banks (5 windows × 4 conv × 4128 Q8.8) → 4–8 URAMs OR
  ~20 BRAMs depending on synth attribute.

### 5.3 Z-7020 viability

Z-7020 has 220 DSPs, 140 BRAM36, no URAM. The design **does not fit**
in its current form because `conv2d_temporal` alone wants 64 DSPs and
the rest of the design wants another ~200+. A Z-7020 port would need:

1. Time-multiplex `conv2d_temporal` (e.g. F1-parallel only, KE-sequential
   → 16 DSPs instead of 64).
2. Drop the URAM `RAM_STYLE ultra` hints in the XDC.
3. Possibly cut F_IN-parallelism in `conv1d_temporal_tm` to ½ to halve
   its DSP count, at the cost of doubling cycles.

The hooks are all in place (the time-mux pattern works; you'd just need
one more variant module). ZCU104 was the actual hardware target so this
work was not done.

---

## 6. Deployment workflow (ZCU104)

### 6.1 Weight pipeline

```
trained .h5  (per subject/session)
     │
     ▼  scripts/q88_*.py    (one script per layer)
per-stage .hex files in data/golden_q88/
     │
     ▼  scripts/cat_window_weights.py
combined N_WIN-banked .hex files (all_chan_*, all_tcfn_w*, all_cls_*)
     │
     ▼  scripts/pack_weights_axil.py
weights/db_atcnet.bin    +    weights/db_atcnet.offsets.h
     │
     ▼  embedded into the Vitis app as a binary blob
PS-side `db_atcnet_load_weights()` walks the blob and broadcasts each
32-bit word at its assigned base address via AXI-Lite at boot.
```

### 6.2 PL-side build

1. `vivado -mode batch -source synth/synth_fit.tcl -tclargs xczu7ev-ffvc1156-2-e`
   → out-of-context synth confirms fit + timing.
2. Vivado IPI block design: instantiate Zynq US+ MPSoC, AXI-DMA, AXI-Lite
   interconnect, and `db_atcnet_axi` as a custom RTL module; wire
   `s_axis_*` to DMA MM2S, `s_axi_*` to PS M_AXI_HPM0_FPD, `irq_done` to
   IRQ0, `clk` to PL_CLK0 (100 MHz).
3. Generate bitstream + export hardware (`.xsa`) for Vitis.

### 6.3 PS-side runtime

`ps_demo/db_atcnet_ps_demo.c` shows the reference driver:

```
boot:                              // once
    db_atcnet_load_weights();      // ~840 µs of AXI-Lite writes for the full image

per trial:
    push_19ch_eeg_via_axidma(...); // AXI-Stream beats
    poll_status_until_done();      // ~1.15 ms of PL compute, or wait on irq_done
    class = read_class_register(); // 1 AXI-Lite read
    drive_servo(class);
```

End-to-end PS-perceived latency ≈ 5 ms / trial (DMA push + PL compute +
mailbox read).

### 6.4 Per-subject changeover

Without re-synthesis:

1. Run the per-stage Python scripts pointing at the new subject's `.h5`.
2. Re-pack with `cat_window_weights.py` + `pack_weights_axil.py`.
3. Replace the embedded image in the Vitis app.
4. Push new Gumbel LUT (3 × 32-bit AXI-Lite writes at base `0x2000`) for
   the per-subject electrode set.

---

## 7. Code organisation

```
rtl/
    util/                serial_divider.sv
    weights/             axi_lite_weight_loader.sv, weight_bank.sv
    window/              gumbel_channel_adapter.sv, eeg_channel_adapter.sv (legacy)
    conv/                conv2d_temporal.sv, conv1d_temporal[_tm].sv,
                         depthwise_spatial.sv, elu.sv, avg_pool_time.sv,
                         sat_add.sv, tcfn.sv, branch_pipeline.sv
    attention/           gap_accumulator.sv, eca_attention.sv, gate_apply.sv,
                         cbam_channel_attn.sv, cbam_spatial_attn.sv,
                         eca1_pipeline.sv
    classifier/          dense_classifier.sv, output_head.sv
    db_atcnet_window_pipeline.sv, db_atcnet_post_eca1.sv,
    db_atcnet_conv2d_eca1.sv, db_atcnet_top.sv, db_atcnet_axi.sv
sim/                     <module>_tb.sv files mirror the RTL layout
                         run_vivado_tests.sh drives every TB
scripts/                 q88_*.py (one per layer), gen_*_lut.py, h5_to_mem.py,
                         cat_window_weights.py, pack_weights_axil.py,
                         q88_end_to_end.py
synth/                   synth_fit.tcl (Vivado out-of-context flow)
constraints/             db_atcnet_axi.xdc
ps_demo/                 db_atcnet_ps_demo.c (Vitis bare-metal driver)
docs/                    FPGA_DEPLOYMENT_DOC.md (model spec),
                         VISUALIZATION_MATH_REPORT.md (architectural diagrams),
                         SYNTH_NOTES.md (Vivado gotchas),
                         DEPLOY_ZCU104.md (bring-up notes),
                         IMPLEMENTATION.md (this file)
data/, weights/          ignored — regeneratable from .h5 + scripts/
```

---

## 8. Known limitations & future work

1. **Q8.8 saturation in TCFN.** Subject A session 3 happens to be within
   range, but other subjects/sessions may experience some clipping in
   the four cascaded Conv1Ds. A move to Q8.16 (24-bit internal) for the
   TCFN intermediate buffers would eliminate this; the RTL changes are
   confined to `tcfn.sv` and would not affect the bit-exact contract
   with the Python golden (which would update in parallel).
2. **conv2d_temporal is fully parallel.** Z-7020 fit requires
   time-multiplexing this block (see § 5.3).
3. **No AXI-Stream output for traces.** The current output is just a
   1-bit class + done IRQ. Adding a small status FIFO with per-window
   logits would help on-device debug.
4. **Single-trial throughput only.** The pipeline processes one trial
   at a time. Pipelining at the trial level (start next trial's
   Conv2D while previous trial's window pipeline runs) would push
   throughput to ~870 trials/s but is unnecessary for 200 Hz EEG.
5. **No on-chip per-subject training.** All weight updates require an
   off-line retraining of the Keras model and a fresh AXI-Lite weight
   load. A future iteration could add on-chip LMS-style fine-tuning of
   the final Dense layer using PS-buffered ground truth.

---

## 9. Reproducibility — how to regenerate everything

```bash
# 1. Quantize all layers from the trained .h5 (Subject A session 3).
python3 scripts/q88_layer1.py
python3 scripts/q88_eca1.py
python3 scripts/q88_layer4.py q88_layer5.py q88_layer6.py q88_layer7.py q88_layer8_9.py
python3 scripts/q88_branchB.py
python3 scripts/q88_layer15.py
python3 scripts/q88_layer16.py
for w in 0 1 2 3 4; do
    python3 scripts/q88_layer17_chan.py    --window $w
    python3 scripts/q88_layer17_spatial.py --window $w
    python3 scripts/q88_layer_tcfn.py      --window $w
    python3 scripts/q88_classifier.py      --window $w
done
python3 scripts/cat_window_weights.py        # combined N_WIN banks
python3 scripts/q88_end_to_end.py            # confirms class=0 for Subject A session 3

# 2. Run every bit-exact regression in simulation.
LIBRARY_PATH=/usr/lib/x86_64-linux-gnu bash sim/run_vivado_tests.sh top
# → "[top_tb] class_out = 0 (expected 0)  [top_tb] PASS"

# 3. Out-of-context synthesis.
vivado -mode batch -source synth/synth_fit.tcl -tclargs xczu7ev-ffvc1156-2-e
# → build/synth_xczu7ev-ffvc1156-2-e/{utilization.txt, timing.txt}

# 4. PS-side build path:
python3 scripts/pack_weights_axil.py        # weights/db_atcnet.bin + db_atcnet.offsets.h
# Embed those two artefacts in a Vitis bare-metal app around
# ps_demo/db_atcnet_ps_demo.c. Flash to ZCU104 (QSPI / SD).
```

---

## 10. Glossary

| Term | Meaning |
|---|---|
| Q8.8 | Signed 16-bit fixed-point, 8 integer + 8 fractional bits |
| BN | BatchNormalization (folded into adjacent conv at export) |
| GAP | GlobalAveragePool |
| ECA | Efficient Channel Attention (3-tap Conv1D over channel dim + sigmoid) |
| CBAM | Convolutional Block Attention Module — channel attn + spatial attn |
| ImpCBAM | "Improved CBAM" — spatial-attn variant with avg + max + stochastic pool over channel dim |
| TCFN | Temporal Convolutional Fusion Network — 4 causal dilated Conv1D with 3 residual adds |
| HaLT | Hand and Leg Tasks EEG dataset (motor-imagery) |
| AXI4-Lite | Xilinx low-throughput memory-mapped slave bus |
| AXI4-Stream | Xilinx unidirectional streaming bus |
| URAM | UltraRAM — large embedded memory blocks on Ultrascale+ |
| BRAM36 | 36-kbit on-chip block RAM (Xilinx 7-series and US+) |
| DSP48E2 | Ultrascale+ DSP slice: 27×18 signed multiply + 48-bit accumulator |

---

## 11. Citation handles

When citing this implementation in a paper:

* Architecture reference: `docs/FPGA_DEPLOYMENT_DOC.md` (model spec
  authored alongside this implementation).
* Bit-exact methodology: `scripts/q88_*.py` (Python golden) +
  `sim/*_tb.sv` (SystemVerilog testbenches).
* Top-level synthesizable module: `rtl/db_atcnet_axi.sv`.
* Final accuracy reference: `weights/global_summary.txt`
  (Subject A 95.72 % ± 2.13 % across 3 leave-one-session-out folds).
* Latency reference: `sim/db_atcnet_top_tb.sv` final $finish time
  (115,453 cycles ≈ 1.15 ms @ 100 MHz).
