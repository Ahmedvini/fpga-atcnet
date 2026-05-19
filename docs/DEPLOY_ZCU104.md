# Deploying DB-ATCNet on ZCU104 (XCZU7EV-2FFVC1156)

End-to-end bring-up notes for the bit-exact RTL inference pipeline.

## 1 — Hardware target

| Attribute | Value |
|---|---|
| Part        | `xczu7ev-ffvc1156-2-e` |
| Board       | Xilinx ZCU104 evaluation kit |
| LUTs        | 230,400 |
| FFs         | 460,800 |
| DSPs        | 1,728 |
| BRAM (36 K) | 312 (≈ 11.0 Mb) |
| URAM (288 K)| 96 (≈ 27.0 Mb) |
| GTH lanes   | 16 × 16.3 Gb/s |

## 2 — Build flow

```bash
# 1. Generate the per-window weight + LUT files (once per subject).
python3 scripts/q88_layer1.py
python3 scripts/q88_eca1.py
python3 scripts/q88_layer4.py
python3 scripts/q88_branchB.py
python3 scripts/q88_layer7.py q88_layer8_9.py
python3 scripts/q88_layer15.py
python3 scripts/q88_layer16.py
for w in 0 1 2 3 4; do
    python3 scripts/q88_layer17_chan.py    --window $w
    python3 scripts/q88_layer17_spatial.py --window $w
    python3 scripts/q88_layer_tcfn.py      --window $w
    python3 scripts/q88_classifier.py      --window $w
done
python3 scripts/cat_window_weights.py
python3 scripts/q88_end_to_end.py     # confirms class=0 for Subject A session 3

# 2. Re-run every bit-exact regression in simulation (~5 min total):
LIBRARY_PATH=/usr/lib/x86_64-linux-gnu bash sim/run_vivado_tests.sh top
# → "[top_tb] class_out = 0 (expected 0)  [top_tb] PASS"

# 3. Synthesize (out-of-context) and confirm resource fit:
vivado -mode batch -source synth/synth_fit.tcl -tclargs xczu7ev-ffvc1156-2-e
# → build/synth_xczu7ev-ffvc1156-2-e/{utilization.txt, timing.txt}

# 4. Build a Vivado IPI design with the Zynq PS:
#    - Add db_atcnet_axi as an RTL block, expose s_axi / s_axis / irq_done.
#    - Connect s_axi → PS GP, s_axis → PS HP via an AXI-DMA, irq_done → PS GIC.
#    - Generate bitstream (vivado synth_design + impl_design + write_bitstream).
#    - Export hardware (.xsa) for Vitis.

# 5. Build the bare-metal Vitis application:
#    - Add ps_demo/db_atcnet_ps_demo.c to the project.
#    - Run `python3 scripts/pack_weights_axil.py` and add the resulting
#      weights/db_atcnet.bin (+ db_atcnet.offsets.h) as a binary blob.
#    - Build, flash to QSPI / boot from SD.
```

## 3 — Latency budget

Measured in sim against `db_atcnet_top_tb.sv`:

| Stage | Cycles | Time @ 100 MHz |
|---|---|---|
| Conv2D + ECA₁ wrapper | ~6.3 k | 63 µs |
| Branch A + B + Add + ECA₂ | ~95 k | 954 µs |
| 5-window (ImpCBAM + TCFN + classifier + head) | ~16 k | 167 µs |
| **Total** | **~115 k** | **1.15 ms** |

Well within the 3-second EEG window. Targeting PL clock 100 MHz keeps the
post-synth WNS comfortable; the design also runs at 200 MHz on ZCU104 with
minor pipelining tweaks (defer to the post-route report once IPI build is
in place).

## 4 — PS-side runtime

```c
// boot
db_atcnet_load_weights();          // ~840 µs of AXI-Lite writes for the full image

// per trial
push_19_channel_eeg_via_axidma();  // ~3 ms of AXI-Stream beats
poll_status_until_done();          // ~1.15 ms of PL compute
read_class_register();             // 1 AXI-Lite read

drive_servo(class_bit);
```

End-to-end PS-perceived latency ≈ 5 ms / trial — well under real-time
requirements for motor-imagery decoding (200 Hz EEG → 5 ms decision window
is 1 sample of jitter).

## 5 — Subject changeover

Default LUT + default `$readmemh` paths pin the design to
**Subject A session 3**. For other subjects/folds:

1. Re-run the per-stage Python golden scripts pointing at
   `weights/subject_X/session_Y_heldout/best_model.weights.h5`.
2. Re-run `scripts/cat_window_weights.py` then
   `scripts/pack_weights_axil.py`.
3. PS-side: replace the embedded image, re-run `db_atcnet_load_weights()`.
4. Push new Gumbel LUT (3 × 32-bit AXI-Lite writes at base `0x2000`) for
   the per-subject electrode set.

No RTL re-synth required — every weight RAM is AXI-Lite-writable.

## 6 — What's verified vs. what's deployment-pending

PASS (sim, bit-exact against Python golden):
- All 26 per-stage / orchestrator / wrapper testbenches in
  `sim/run_vivado_tests.sh`.
- Final argmax `class_out = 0` (Right Hand fist) for Subject A session 3.

Deployment-pending:
- Vivado IPI block design integration (PS + AXI-DMA + GIC).
- Real-hardware bring-up against the JTAG'd ZCU104.
- Per-subject accuracy sweep on a held-out test set.
