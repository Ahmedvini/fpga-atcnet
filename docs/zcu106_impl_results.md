# ZCU106 Implementation Results — Semester 2 Final Numbers

**Build**: `db_atcnet_zcu106_clean`
**Device**: XCZU7EV-2FFVC1156 (ZCU106 production)
**Board file**: `xilinx.com:zcu106:part0:2.6`
**pl_clk0**: **50 MHz** (period 20 ns)
**Status**: ✅ `write_bitstream Complete`

This file is the authoritative source of post-impl numbers to cite in
Chapter 8 of the thesis. All values come directly from the Vivado
post-implementation reports.

---

## 1. Timing closure

| Metric | Value | Status |
|---|---:|---|
| Worst Negative Slack (setup, WNS) | **+1.864 ns** | ✅ closed with margin |
| Total Negative Slack (setup, TNS) | 0.000 ns | ✅ |
| Failing endpoints (setup) | 0 | ✅ |
| Total endpoints (setup) | 333 052 | — |
| Worst Hold Slack (WHS) | **+0.010 ns** | ✅ closed |
| Total Hold Slack (THS) | 0.000 ns | ✅ |
| Failing endpoints (hold) | 0 | ✅ |
| Total endpoints (hold) | 333 052 | — |
| Clock pair classification | **Clean** | ✅ |
| pl_clk0 frequency | 50.00 MHz | drives 107 879 loads |

**Inference latency at 50 MHz** = 115 453 cycles / 50 MHz ≈ **2.31 ms**
(was 1.92 ms at 60 MHz; still ≈4 300× faster than the 250 Hz EEG arrival
rate).

**Reference figure for thesis**: `docs/thesis_figures/fig_8-9_clock_interaction_timing.png`

---

## 2. Resource utilization

| Resource | Used | Available | Utilization |
|---|---:|---:|---:|
| CLB LUTs | 193 186 | 230 400 | **84%** |
| CLB Registers | 103 487 | 460 800 | 22% |
| CARRY8 | 14 500 | 28 800 | 50% |
| F7 Muxes | 9 778 | 115 200 | 8% |
| F8 Muxes | 3 133 | 57 600 | 5% |
| CLB | 28 527 | 28 800 | **99%** |
| LUT as Logic | 193 015 | 230 400 | 84% |
| LUT as Memory | 171 | 101 760 | <1% |
| Block RAM Tile | 80.5 | 312 | 26% |
| **DSP48E2** | **1 719** | **1 728** | **99.5%** |
| Bonded IOB | 2 | 360 | <1% |
| BUFGCE | 26 | 208 | 13% |
| BUFG_PS | 1 | 96 | 1% |
| PS8 | 1 | 1 | 100% |

Note: nine fewer DSPs than the ZCU104 attempt because the relaxed 50 MHz
target allowed Vivado to use slightly different inference choices for
constant multipliers in `avg_pool_time`.

**Reference figure for thesis**: `docs/thesis_figures/fig_8-8_utilization_zcu106.png`

---

## 3. Power analysis

| Component | Power | Share |
|---|---:|---:|
| **Total On-Chip Power** | **5.109 W** | 100% |
| Dynamic (total) | 4.405 W | 86% |
|   – Clocks | 0.106 W | 2% |
|   – Signals | 0.737 W | 17% |
|   – Logic | 0.678 W | 15% |
|   – BRAM | 0.032 W | 1% |
|   – DSP | 0.196 W | 4% |
|   – I/O | <0.001 W | <1% |
|   – PS (Cortex-A53 + peripherals) | 2.655 W | 60% |
| Static (total) | 0.704 W | 14% |
|   – PL leakage | 0.604 W | 86% of static |
|   – PS leakage | 0.100 W | 14% of static |

Thermal headroom:
- Junction temperature: 30.0 °C
- Ambient: 25.0 °C
- Effective θJA: 1.0 °C/W
- Thermal margin: 70.0 °C (70.2 W)

Confidence level: Low (vector-less estimation; would be Medium/High
with actual workload-driven SAIF activity).

**Reference figure for thesis**: `docs/thesis_figures/fig_8-10_power_summary.png`

---

## 4. Routed netlist

The post-route schematic confirms full connectivity end-to-end through
the PS, AXI-DMA, SmartConnects and the `u_atcnet` inference engine.
All AXI nets are reported as "Fully routed."

**Reference figure for thesis**: `docs/thesis_figures/fig_8-7_implemented_netlist_routed.png`

---

## 5. Bitstream and platform artifacts

| Artifact | Path |
|---|---|
| Bitstream | `build/db_atcnet_zcu106_clean/db_atcnet_zcu106_clean.runs/impl_1/db_atcnet_bd_wrapper.bit` |
| .xsa hardware platform | `build/db_atcnet_zcu106.xsa` (to be exported) |
| Vivado checkpoint (routed) | `.../impl_1/db_atcnet_bd_wrapper_routed.dcp` |
| Timing report | `.../impl_1/db_atcnet_bd_wrapper_timing_summary_routed.rpt` |
| Utilization report | `.../impl_1/db_atcnet_bd_wrapper_utilization_placed.rpt` |
| Power report | `.../impl_1/db_atcnet_bd_wrapper_power_routed.rpt` |

---

## 6. Differences from Semester 1 (Zynq-7030) prototype

| Metric | Sem 1 (Zynq-7030 proto) | Sem 2 (ZCU106 / XCZU7EV) |
|---|---:|---:|
| Device | xc7z030 | xczu7ev-ffvc1156-2-e |
| Board | n/a (prototype only) | ZCU106 (board file v2.6) |
| pl_clk0 | 100 MHz | **50 MHz** |
| LUTs | 2 662 (3.4%) | 193 186 (84%) |
| FFs | 1 568 (1.0%) | 103 487 (22%) |
| DSPs | 16 (4.0%) | **1 719 (99.5%)** |
| BRAM tiles | not reported | 80.5 (26%) |
| Inference latency | 640 ns (proof-of-concept slice) | **2.31 ms (complete network)** |
| WNS | +3.222 ns | +1.864 ns |
| WHS | n/r | +0.010 ns |
| Power | n/r | 5.109 W total |

---

## 7. Figures index for thesis

| Figure | File | Caption draft |
|---|---|---|
| Fig 8-7 | `fig_8-7_implemented_netlist_routed.png` | Post-route schematic of the `db_atcnet_bd` integrated design on the ZCU106, showing fully routed AXI interconnect between the Zynq UltraScale+ PS, AXI-DMA, AXI SmartConnects, processor-system reset, and the `u_atcnet` inference accelerator. |
| Fig 8-8 | `fig_8-8_utilization_zcu106.png` | Post-implementation resource utilization on the ZCU106 (XCZU7EV-2FFVC1156). DSP48E2 utilization reaches 99.5% (1 719 of 1 728), confirming that the full DB-ATCNet inference engine fits within the device DSP budget with one slice of headroom. |
| Fig 8-9 | `fig_8-9_clock_interaction_timing.png` | Post-route clock-interaction timing summary for `clk_pl_0` at 50 MHz. WNS = +1.864 ns; WHS = +0.010 ns; 0 failing endpoints across 333 052 total endpoints; clock pair classification is **Clean**. |
| Fig 8-10 | `fig_8-10_power_summary.png` | Vivado-reported on-chip power summary for the implemented design at 25 °C ambient. Total power is 5.109 W (4.405 W dynamic, 0.704 W static). The Cortex-A53 processing subsystem dominates the dynamic power at 60% (2.655 W). |
