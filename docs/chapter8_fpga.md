# Chapter 8

# FPGA Deployment and Hardware Acceleration

## 8.1 Introduction

Field-Programmable Gate Arrays (FPGAs) have become an essential platform for
accelerating computation-intensive and latency-sensitive tasks in real-time
systems due to their inherent parallelism, deterministic timing and
reconfigurability. In Brain–Computer Interface (BCI) applications, continuous
multi-channel EEG data streams, strict latency constraints and safety-critical
control requirements make FPGA-based acceleration particularly suitable [76],
[77].

This chapter documents the FPGA-based acceleration strategy adopted in the
proposed BCI Motion-Control System. The work was carried out across two
academic semesters, with two distinct deployment phases:

- **Semester 1 — prototype deployment on the Xilinx Zynq-7030 SoC.** The first
  phase of the project established the hardware–software co-design
  methodology, the security architecture, the simulation and verification flow
  in the Vivado Design Suite, and an early bit-exact prototype of the
  DB-ATCNet inference engine targeted at the Zynq-7030 platform. The
  prototype produced the early latency, resource and acceleration-factor
  measurements that proved the viability of FPGA-based MI classification
  for assistive motion control.
- **Semester 2 — full deployment on the AMD/Xilinx Zynq UltraScale+ MPSoC
  (XCZU7EV) on the ZCU106 evaluation board.** The second phase scaled the
  Semester 1 prototype into the complete DB-ATCNet architecture, migrated
  the design to a higher-tier SoC with the required DSP density, redesigned
  the Programmable-Logic (PL) RTL for fit and timing closure, integrated the
  design into a Vivado IP Integrator (IPI) block design with a hardened
  Processing System (PS), AXI-DMA and SmartConnect fabric, and exported the
  final hardware platform to Vitis for the bare-metal A53 host application.

Sections 8.4–8.4.10 below preserve the Semester 1 design narrative and its
numerical results; Sections 8.5 onward present the Semester 2 full
deployment, the new architecture and the consolidated performance evaluation.
A combined performance summary is presented in §8.8.

The integration of the FPGA within the overall system architecture is
illustrated in **[Insert Figure 8-1 here — Top-Level System Block Diagram
(from `thesis/block diagram`)]**, which shows the Vivado IPI architecture
that drives the Semester 2 deployment.

---

## 8.2 ZCU106 Hardware Platform Overview

The Semester 2 deployment platform is the Xilinx **ZCU106 Evaluation Board**,
populated with the **XCZU7EV-2FFVC1156** Zynq UltraScale+ MPSoC. A
photograph of the ZCU106 with numbered component callouts (reproduced from
[UG1244]) is shown in **[Insert Figure 8-2 here — Photograph of the ZCU106
evaluation board with numbered component callouts, after UG1244 Fig. 2-1,
from `thesis/info of fpga.pdf`]**.

Each numbered callout on the photograph corresponds to a physical component
on the board. The complete mapping is reproduced in Table 8-1.

**Table 8-1 — ZCU106 board component mapping (after UG1244 Table 2-1).**

| # | Reference Designator | Feature | Role in this Project |
|---|---|---|---|
| 1 | U1 | Zynq UltraScale+ XCZU7EV MPSoC with Radian fan sink | Hosts the entire FPGA inference engine and the Cortex-A53 bare-metal application. |
| 2 | U2, U99–U101 | PS-Side DDR4 (2 GB total) | Stores the EEG window buffer and the PS application heap/stack. |
| 3 | J1 | PL-Side DDR4 SODIMM Socket | Not populated in this project. |
| 4 | U119 | Quad SPI Flash Memory, 512 Mb | Bitstream/FSBL boot path (used in production deployment; JTAG used during development). |
| 5 | U116, J96 | USB 3.0 + USB 2.0 PHY | Not used in this project. |
| 6 | J100 | SD Card Interface | Reserved for future stored-data replay directly from the PS. |
| 7 | U151, J164 | Programmable Logic JTAG Programming | Primary load path used during development. |
| 8 | U182 | IDT8T49N287 FemtoClock Universal Frequency Translator | Provides the on-board reference clocks. |
| 9 | U98, P12 | Tri-speed Ethernet PHY | Not used in this project. |
| 10 | U94, P7 | HDMI Video Output (back) | Not used. |
| 11 | U19, P7 | HDMI Video Output (front) | Not used. |
| 12 | U97 | I²C1 (MIO 16–17) | Available for future board-management traffic. |
| 13 | U34 | I²C1 multiplexer | Not used in this project. |
| 14 | J55, J87 | User **PMOD GPIO Connectors** | Reference points for the PL-side UART routing described in §8.5.17. |
| 15 | J160 | User I²C1 Receptacle | Reserved for future expansion. |
| 16 | DS37–DS40 | User I/O LEDs | Status indication during development. |
| 17 | SW13 | User I/O 4-pos DIP switch | Reserved. |
| 18 | SW14, 15, 17, 18 | User I/O pushbuttons | Reserved. |
| 19 | SW20 | CPU reset pushbutton | Used during development. |
| 20 | SW3, SW4 | POR pushbuttons | Used during development. |
| 21 | U122, J98 | User CAN Receptacle | Not used. |
| 22 | SW1 | Power on/off slide switch | Used to enable/disable the board. |
| 23 | J52 | 12 V barrel power input | Used as the bench-time 12 V power source in the development rig. |
| 24 | SW5 | PROG_B pushbutton | Used during development. |
| 25 | J5 | FMC LPC Connector | Reserved for future expansion. |
| 26 | — | Board power system (top/bottom) | On-board Maxim regulators that power the SoC and peripherals. |
| 27 | P11 | DPAUX (MIO 27–30) | Not used. |
| 28 | J175 | Voltage/current monitoring header | Reserved. |
| 29 | U181 | HDMI Clock Recovery | Not used. |
| 30 | SW6 | MODE 4-pole DIP (boot mode select) | Set to JTAG for development boot. |
| 31 | U23 | I²C1 EEPROM | Used by the Vivado/Vitis tools for board identification. |
| 32 | U170 | PS M.2 SATA Connector | Not used. |
| 33 | J85 | POR Override Sel jumper | Default position. |
| 34 | J12, J13 | SYSMON I²C ADDR jumpers | Default position. |
| 35 | J20–J22 | POR circuit jumpers | Default position. |

The Vivado bitstream is loaded over JTAG (callout 7) during development; in
production the same bitstream is intended to be booted from the Quad SPI
flash (callout 4). The PS UART1 traffic is routed to the on-board CP2108
USB-UART bridge via PL pins AL17 (TX) and AH17 (RX), enumerating on the host
laptop as a virtual serial port — the details of this routing are given in
§8.5.17.

---

## 8.3 Hardware Resource Description

In addition to the numbered components in Table 8-1, the XCZU7EV MPSoC
itself provides the following resources that are accessed by the design:

- **Processing System (PS).** A quad-core 64-bit ARM Cortex-A53 application
  processor at up to 1.2 GHz, a dual-core ARM Cortex-R5 real-time processor,
  a Mali-400 MP2 GPU, 256 KiB of on-chip memory (OCM), a hardened DDR4
  controller, a 128 KiB PMU RAM, and dedicated cryptographic accelerators
  (SHA3, AES-GCM, RSA) inside the Configuration Security Unit (CSU).
- **Programmable Logic (PL).** 230 400 LUTs, 460 800 flip-flops, 312 36-Kb
  block RAM tiles (≈ 11 Mb), 96 UltraRAM blocks (≈ 27 Mb) and **1 728
  DSP48E2 slices**.
- **PS–PL interfaces.** Multiple HP/HPC/HPM AXI4 ports up to 128 bits wide,
  a cache-coherent ACE port, GP control ports, LPD–PL and PL–LPD bridges, and
  EMIO routing for the PS UART/I²C/GPIO peripherals into the PL.
- **High-speed transceivers.** 16 × 16.3 Gb/s GTH lanes and PCIe Gen4 hard
  IP (not used in this project).
- **Sysmon block.** On-die analog monitoring for temperature, supply voltage
  and external single-ended/differential sensors.

The XCZU7EV's top-level architecture is illustrated in **[Insert Figure 8-3
here — Zynq UltraScale+ MPSoC Top-Level Block Diagram (after UG1085 / UG1244
Fig. 3-1, from `thesis/archticture`)]**. This figure should be read together
with the IPI block diagram of §8.5.2 to understand how the implemented design
maps onto the silicon.

---

# Part A — Semester 1 Prototype Deployment

The work in this part was carried out during the first semester of the
project. It established the methodology that the Semester 2 deployment then
scaled. The numerical results in §8.4.8 reflect that early prototype and
should be read as the baseline against which the Semester 2 implementation
(Part B) is compared.

## 8.4 FPGA-Based Prototype on Zynq-7030

### 8.4.1 Semester 1 platform selection

The Xilinx **Zynq-7030 System-on-Chip** was selected as the initial target
FPGA platform due to its heterogeneous architecture that tightly integrates:

- A Processing System (PS) based on dual-core ARM Cortex-A9 processors.
- A Programmable Logic (PL) fabric optimized for massively parallel
  computation.

This architecture enables efficient hardware–software co-design, where
control-oriented and system management tasks execute on the PS, while
compute-intensive signal processing and neural network operations are
offloaded to the PL [79], [83]. Key advantages of the Zynq-7030 that
motivated the Semester 1 prototype include:

- High-bandwidth AXI interfaces between PS and PL.
- Deterministic and low-latency data transfer.
- Adequate logic and memory resources for an early-stage deep-learning
  accelerator.
- Compatibility with industry-standard FPGA development tools such as Vivado
  [76], [77].

The architectural overview of the Zynq-7000 family used in Semester 1 is
shown in **[Insert Figure 8-4 here — Zynq-7000 SoC Architecture Overview
(Semester 1 baseline)]**.

### 8.4.2 Deep Learning Model: DB-ATCNet

The deployed deep-learning model, **DB-ATCNet**, is a dual-branch
attention-based temporal convolutional network designed for EEG-based motor
imagery classification. The architecture combines temporal convolutional
layers with attention mechanisms to capture both temporal dynamics and
discriminative EEG patterns [36]. DB-ATCNet is well-suited for non-invasive
BCI systems due to its robustness against noise and its ability to extract
meaningful features from low signal-to-noise ratio EEG data. However, its
computational complexity poses challenges for real-time software-only
execution, motivating the use of FPGA-based acceleration in this project
[76], [77]. The architectural components of DB-ATCNet are illustrated in
**[Insert Figure 8-5 here — Components of the DB-ATCNet architecture, after
[36]]**.

### 8.4.3 Hardware–Software Co-Design and Partitioning

A hardware–software co-design approach was adopted to efficiently deploy the
DB-ATCNet model on the Zynq-7030 platform. The system functionality was
partitioned based on the specific strengths of the heterogeneous
architecture: the Processing System (PS) handles sequential control and
interfacing, while the Programmable Logic (PL) handles massive parallel
computation [76], [77], [83].

**Processing System (PS) responsibilities.** Managing tasks that require
high flexibility, complex decision logic or interaction with standard
communication protocols:

- EEG data reception and buffering by interfacing with the external EEG
  acquisition hardware (e.g. via USB, UART or SPI).
- High-level system control.
- Configuration of FPGA accelerators.
- Communication with user interfaces and external devices.
- Security mechanisms and decision supervision.

This division of responsibilities aligns with established FPGA-SoC
deployment practices for deep-learning workloads, where control-dominant and
communication-heavy tasks remain in software [79], [80].

**Programmable Logic (PL) responsibilities.**

- *Acceleration of convolutional layers* by mapping temporal convolutions
  to dedicated hardware structures. **Implementation:** maps temporal
  convolutions to dedicated hardware using the `temporal_conv` module. This
  design utilizes a systolic shift-register architecture that performs "loop
  unrolling" in the spatial domain, allowing the Multiply-Accumulate (MAC)
  operations for an entire kernel window to be computed in a single clock
  cycle [78], [85].
- *Parallel feature-extraction operations* to capture diverse temporal
  patterns. **Implementation:** the `dual_branch_conv` module exploits the
  spatial parallelism of the FPGA by instantiating two independent
  convolution pipelines (`Branch A` and `Branch B`) that operate
  concurrently on the same input data stream [36], [83].
- *Fixed-point optimized matrix operations.* All mathematical operations
  are optimized for fixed-point arithmetic to maximize resource efficiency.
  **Implementation:** modules such as `spatial_conv_serial_stream` utilize
  16-bit signed fixed-point arithmetic (Q8.8 format). This alignment with
  the FPGA's DSP48 slices enables single-cycle vector-matrix
  multiplication, avoiding the resource overhead and latency of
  floating-point units [78], [84].
- *Deterministic inference execution* by guaranteeing fixed-latency
  processing for every data window. **Implementation:** (1) static pipelined
  dataflow — the design uses a fixed chain of registers (`always_ff`)
  instead of software loops (`while/wait`); data advances one step per
  clock cycle, ensuring predictable processing; (2) zero-cache architecture
  — instead of CPU caches that suffer from cache-miss delays, the design
  uses flip-flops and shift registers; accessing these registers always
  takes exactly one clock cycle [76], [77], [85].

This partitioning allows the system to leverage FPGA parallelism while
maintaining software flexibility for algorithm updates.

### 8.4.4 Security Algorithms for FPGA-Based Deployment

Considering the critical nature of assistive rehabilitation and mobility
applications, the proposed EEG-based BCI system ensures that biosignals and
parameters are not accessed or manipulated by unauthorized individuals or
parties. In the proposed FPGA-SoC platform, the Processing System (PS) is
responsible for supervision and security control, whereas the Programmable
Logic (PL) is utilized for accelerating computationally intensive
operations such as neural-network evaluation. Security protection is
applied using a layered approach:

1. **Confidentiality of EEG/session data** — privacy at rest and in transit.
2. **Integrity/authenticity of motion and control commands** — anti-tamper.
3. **Trusted deployment and boot process** — bitstream and model
   authenticity.
4. **Tamper-evident safety and audit logging.**

#### 8.4.4.1 AES-256-GCM (Authenticated Encryption)

The Advanced Encryption Standard (AES) is a standardized symmetric encryption
algorithm for securing digital information [100]. AES is used with a 256-bit
secret key (AES-256) to protect confidentiality of EEG recordings and
sensitive system messages. To ensure that encrypted information cannot be
modified without detection, AES is applied using Galois/Counter Mode (GCM),
which provides authenticated encryption (AEAD) [101], [107].

AES-256-GCM takes a 256-bit secret key **K**, plaintext message **M**, a
unique IV/nonce **N** and optional associated authenticated data (AAD), and
produces ciphertext **C** and an authentication tag **T** (commonly 128-bit).
A key requirement in AES-GCM is uniqueness of the nonce/IV per encryption
under the same key. For embedded FPGA deployment, a deterministic nonce
format is adopted:

```
IV = Session_ID || Window_Counter
```

This guarantees uniqueness across EEG windows and command packets without
heavy randomness requirements [101].

#### 8.4.4.2 HMAC-SHA-256 (Command Authentication and Anti-Tampering)

In assistive motion-control systems, actuator commands must be protected
against command injection and tampering. HMAC (Keyed-Hash Message
Authentication Code) provides message authenticity and integrity using a
shared secret key [102]. SHA-256 is used as the underlying secure hash
algorithm [103]. For a message **M** and secret key **K**, an authentication
code is computed:

```
HMAC = HMAC_SHA256(K, M).
```

The receiver recomputes the HMAC using the same key. If values differ, the
message is rejected as untrusted [102], [103]. To prevent replay attacks,
sequence numbers or timestamps are included:

```
M = Command || Timestamp || Sequence_Number.
```

#### 8.4.4.3 SHA-256 Hash Chain for Tamper-Evident Logging

Safety and audit logs provide essential traceability for debugging, clinical
evaluation and security analysis. Logs can also be targeted by attackers
attempting to modify history to hide malicious behavior. To address this, the
system uses tamper-evident logging using SHA-256 [103]. A hash chain is
constructed as

```
H_i = SHA-256(H_{i-1} || Entry_i).
```

Any modification or deletion of a prior entry breaks chain verification,
making tampering detectable.

#### 8.4.4.4 Secure Boot and Bitstream Authentication (RSA/ECDSA)

FPGA devices rely on configuration bitstreams and boot images. If an attacker
replaces the design image or model, they may disable safety constraints or
manipulate system behavior. Secure boot ensures that only trusted images are
executed via digital signatures (RSA/ECDSA): hash the bitstream/boot image,
generate a signature using a private key, verify the signature during boot
using the public key, and refuse operational boot if verification fails. On
the Zynq family, secure boot and authenticated boot mechanisms are supported
through vendor-recommended deployment flows [104], [105].

#### 8.4.4.5 FPGA Bitstream Encryption

In addition to authenticity, FPGA designs require confidentiality of the
implementation. The FPGA configuration bitstream is AES-encrypted and
decrypted internally during configuration. Encryption keys are stored in
protected FPGA storage mechanisms such as BBRAM/eFUSE depending on vendor
support and security policy [105], [106]. Bitstream encryption protects the
HDL accelerator design and optimization, the deployed inference architecture
(DB-ATCNet mapping) and prevents cloning and unauthorized distribution
[106], [109].

#### 8.4.4.6 Key Management Considerations

Cryptographic algorithms depend on secure key management. Key generation,
storage, rotation and revocation must be addressed throughout the system
lifecycle. Recommended key-management practices are defined in security
guidance such as NIST SP 800-57 [108]. In this system, cryptographic keys
are managed by the PS, while the PL is reserved for deterministic inference
acceleration; vendor-protected key-storage mechanisms such as BBRAM/eFUSE
are used where available to reduce the risk of key extraction [105], [106].

### 8.4.5 Deployment of DB-ATCNet on Zynq-7030

The DB-ATCNet model [36] was adapted for FPGA deployment through a series of
optimization steps:

- Quantization of model parameters by converting all floating-point model
  parameters to 16-bit fixed-point representation to reduce logic usage.
- Layer fusion by combining convolution, summation and projection operations
  into a single pipelined block, removing the need to store intermediate
  results in RAM.
- Pipelined execution of convolutional and attention layers.
- Parallelization of independent computation paths.

The optimized model was synthesized and targeted for the Programmable Logic
of the Xilinx Zynq-7030. Data ingestion into the accelerator was managed by
a custom **Snapshot-Based Input Interface** (implemented in the
`window_reader` module). Instead of AXI protocols, this design employed a
**Shadow Register** mechanism to latch incoming parallel data windows
instantly. This effectively decoupled the high-speed inference pipeline from
the variable input acquisition rate, ensuring data consistency and
deterministic processing without the overhead of external memory arbitration.

### 8.4.6 Simulation and Verification Using Vivado

The FPGA design was simulated and verified using the Xilinx Vivado Design
Suite. Simulation was conducted at multiple levels to ensure functional
correctness, timing closure and system stability [76], [77]. Verification
steps included:

- Functional simulation of individual processing blocks.
- End-to-end simulation of the DB-ATCNet inference pipeline.
- Timing analysis to verify compliance with real-time constraints.

Vivado's simulation and analysis tools were instrumental in identifying
bottlenecks and validating the correctness of the accelerated inference
pipeline [78], [85]. The same simulation harness was reused unchanged in
Semester 2 to verify the scaled-up implementation against the Semester 1
golden vectors, which provided continuity between the two deployments.

### 8.4.7 Congestion Handling and Resource Optimization

A major challenge encountered during Semester 1 FPGA deployment was
computational and data congestion, arising from high-throughput EEG streams,
concurrent neural-network operations and limited on-chip memory resources
[76], [77]. The following congestion-handling techniques were applied:

- **Introduction of buffering.** Atomic snapshot buffering was used to smooth
  data flow and prevent data inconsistencies when transferring EEG windows
  between processing stages [78], [79].
- **Synchronous valid-signal handshaking.** Handshake-based flow-control
  mechanisms were employed to prevent resource contention and ensure safe
  data transfer between parallel processing modules [76], [83].
- **Pipelined execution.** Computation was distributed across multiple clock
  cycles using deeply pipelined architectures, enabling continuous data
  processing while maintaining deterministic latency [77], [85].
- **Optimization of memory access patterns.** Memory reuse, streaming-based
  data access and reduced off-chip memory dependency were applied to
  alleviate bandwidth pressure and improve throughput [80], [81].

These techniques significantly improved system stability and ensured
continuous real-time operation without data loss or processing stalls [76],
[78], [85]. Each of these techniques was carried forward into Semester 2 and
extended to address the much larger resource demands of the full DB-ATCNet
deployment.

### 8.4.8 Semester 1 Performance Evaluation

The performance of the FPGA-accelerated DB-ATCNet prototype was validated
through cycle-accurate behavioral simulation targeting a clock frequency of
**100 MHz** on the Xilinx Zynq-7030 device. The design demonstrated
significant improvements in latency and throughput compared to software-based
baselines, adhering to strict real-time constraints. The Semester 1 key
performance metrics are reproduced in Table 8-2.

**Table 8-2 — Semester 1 prototype performance (Zynq-7030, 100 MHz).**

| Resource Type   | Used | Available | Utilization |
|-----------------|------|-----------|-------------|
| Slice LUTs      | 2 662 | 78 600    | 3.39 %      |
| Slice Registers | 1 568 | 157 200   | 1.00 %      |
| DSPs            | 16   | 400       | 4.00 %      |
| Bonded IOB      | 52   | 250       | 20.80 %     |

Additional Semester 1 characterizations:

- **Low latency.** Fixed end-to-end latency of **64 clock cycles**,
  translating to **640 ns (0.64 µs)** at 100 MHz. This is orders of
  magnitude faster than typical human motor reaction times (≈ 200 ms) and
  standard EEG sampling intervals (4 ms at 250 Hz), ensuring negligible
  processing delay in the BCI control loop.
- **Deterministic execution.** A precise 640 ns response per input window,
  ensuring the reliability required for safety-critical mobility
  applications.
- **High-bandwidth throughput.** The fully pipelined architecture processes
  data at one sample per clock cycle. At 100 MHz this supports a theoretical
  throughput of **100 Mega-samples per second (MSPS)**, providing ample
  headroom to handle high-density multi-channel EEG streams.
- **Hardware resource utilization.** The design was synthesized for the
  Xilinx Zynq-7000 (xc7z030) and optimized resource usage by implementing
  sliding-window LUT-based memory, significantly reducing the need for
  dedicated Block RAM tiles.
- **Timing closure and operating frequency.** Post-synthesis timing analysis
  confirmed that the design met all setup and hold-time constraints at the
  target frequency of 100 MHz with a Worst Negative Slack (WNS) of
  **+3.222 ns** and a Maximum Frequency (Fmax) of **147.5 MHz**.
- **Acceleration factor.** To quantify the benefits of hardware
  acceleration, the FPGA latency was compared against a standard software
  implementation of ATCNet running on an embedded CPU (ARM Cortex-A9).

**Table 8-3 — Semester 1 acceleration comparison.**

| Platform        | Latency           | Speedup Factor |
|-----------------|-------------------|----------------|
| Software (CPU)  | ≈ 1.0 ms (estimated) | 1× (baseline) |
| Hardware (FPGA) | 0.64 µs           | ≈ 1 562×       |

**Important note.** The Semester 1 prototype implemented a *single
representative pipeline section* of DB-ATCNet to validate the methodology;
the full DB-ATCNet network — with all four temporal-convolution branches,
the dual-branch attention block, the temporal-fusion network and the dense
classifier — would not have fit on the Zynq-7030 (only 400 DSPs and 78 600
LUTs available). The Semester 1 numbers therefore represent a
proof-of-concept ceiling, not the full inference engine. The Semester 2
deployment in Part B of this chapter delivers the complete network.

### 8.4.9 Semester 1 Limitations and Design Trade-Offs

Despite its advantages, the Semester 1 FPGA prototype introduced trade-offs,
including:

- Increased design and verification complexity compared with a pure-software
  baseline.
- Longer development cycles.
- Constraints on model size and numerical precision (16-bit Q8.8 was the
  ceiling of the Zynq-7030 budget).
- Reduced flexibility compared to pure software implementations.

The most pressing limitation, however, was the **DSP and LUT budget**: the
full DB-ATCNet network requires approximately 1 719 DSPs and 193 k LUTs,
which exceeds the Zynq-7030's capacity by a factor of ≈ 4× in DSPs and
≈ 2.5× in LUTs. This limitation was the dominant motivation for the
Semester 2 platform migration documented in Part B.

### 8.4.10 Migration rationale

By the end of Semester 1, the prototype had demonstrated:

1. The methodology — Q8.8 quantization, dataflow pipelining, snapshot
   buffering, AXI-based PS/PL partitioning — was sound.
2. The Zynq-7030 was too small for the full network.
3. The control-and-security software stack would scale directly to a larger
   PS provided that the AXI interfaces were preserved.

The team therefore decided to migrate the design to the AMD/Xilinx Zynq
UltraScale+ MPSoC XCZU7EV on the ZCU106 evaluation board for the second
semester, while preserving the Semester 1 methodology, Q8.8 numerical
choices, RTL coding style and verification harness wherever possible.

---

# Part B — Semester 2 Full Deployment on ZCU106

## 8.5 Semester 2 Deployment on Zynq UltraScale+ XCZU7EV

### 8.5.1 Why the ZCU106 / XCZU7EV was chosen

The Semester 2 platform was chosen against three quantitative gates derived
from the full DB-ATCNet RTL synthesis:

1. **DSP slice density.** The full inference engine requires 1 719 of the
   1 728 DSP48E2 slices available on the XCZU7EV (99.5 % utilization). No
   member of the Zynq-7000 family has sufficient DSPs to host the design;
   the Zynq-7030 used in Semester 1 has only 400 DSPs.
2. **PS–PL data bandwidth.** The DB-ATCNet AXI-Stream input port needs to
   ingest a 6 000-byte EEG window each inference, which over the
   cache-incoherent 128-bit-wide HP0 (S_AXI_HP0_FPD) port of the
   XCZU7EV is comfortable at 50 MHz; the corresponding Zynq-7000 HP ports
   are 64-bit wide and run at lower frequencies.
3. **Tooling maturity.** Both Vivado Design Suite 2025.2 and Vitis Unified
   IDE 2025.2 support the ZCU106 as a first-class target with official
   board files [UG1244].

Alternative platforms briefly considered and discarded:

- **Zynq-7000 family** (Zynq-7030, Zynq-7045, Zynq-7100) — insufficient DSPs.
- **ZCU102** — adequate but more expensive than the ZCU106 and over-provisioned
  for the network.
- **Alveo U50** — requires a host PCIe slot and is not battery-friendly.

### 8.5.2 Vivado IPI Block-Design Architecture

The Semester 2 deployment is built around a Vivado IP Integrator (IPI)
block design, `db_atcnet_bd`, whose top-level structure is shown in
**[Insert Figure 8-6 here — Vivado IP Integrator Block Design for
`db_atcnet_bd` (from `thesis/block diagram`)]**. The figure shows the
canonical Zynq UltraScale+ embedded-acceleration template:

- **`zynq_ultra_ps_e_0`** — the hardened Zynq UltraScale+ MPSoC IP block
  with the PS configured per §8.5.3.
- **`axi_dma_0`** — the AXI-DMA engine in MM2S (memory-mapped to stream)
  mode, configured for 32-bit data width and no scatter-gather. The MM2S
  master port `M_AXI_MM2S` reads from DDR through the HP0 path; the
  AXI4-Stream output `M_AXIS_MM2S` feeds the inference engine.
- **`u_atcnet`** — the DB-ATCNet accelerator wrapper (`db_atcnet_axi_v_v1`,
  see §8.5.13). Three logical interfaces: AXI4-Stream slave `s_axis`,
  AXI4-Lite slave `s_axi` and `irq_done`.
- **`axi_smc`** and **`axi_smc_1`** — two AXI SmartConnect IP blocks that
  arbitrate the MM2S master onto the PS HP0 port and the PS GP0 master onto
  both `axi_dma_0`'s S_AXI_LITE and `u_atcnet`'s S_AXI control ports.
- **`rst_ps8_0_60M`** — a Processor System Reset IP block clocked from
  `pl_clk0` (50 MHz).

The PL clock `pl_clk0` is generated by the PS at 50 MHz and drives every
PL-side AXI clock domain. The PS-PL interrupt request line `pl_ps_irq0` is
reserved for the AXI-DMA MM2S done interrupt (not used in the implemented
polling-mode application but available for future interrupt-driven
extensions).

### 8.5.3 Processing System (PS) configuration

The Zynq UltraScale+ PS is configured in the IPI through the
`zynq_ultra_ps_e_0` IP wizard with the following settings relevant to this
project:

- **Cortex-A53 cluster.** All four cores enabled; the bare-metal application
  runs on core 0 only.
- **DDR4 controller.** Enabled, with the on-board 2 GB DDR4-2400 components.
- **PS peripherals.** UART0 (MIO-routed to the on-board CP2108 channel 0)
  enabled for the bare-metal `printf` console; UART1 routed to **EMIO** and
  exposed at PL pins AL17 (TX) and AH17 (RX) for the ESP32-S3 link (see
  §8.5.17).
- **HP master ports.** `S_AXI_HP0_FPD` enabled at 128-bit, clocked by
  `pl_clk0`. The MM2S path of the AXI-DMA reads from DDR through this port.
- **GP master port.** `M_AXI_HPM0_FPD` enabled at 32-bit, clocked by
  `pl_clk0`. The PS uses this port to access AXI-Lite control registers in
  the PL (`axi_dma_0` and `u_atcnet`).
- **PS-PL interrupt.** `pl_ps_irq0[0:0]` connected to `axi_dma_0.mm2s_introut`
  (reserved).
- **PL fabric clock 0.** Set to 50 MHz, which drives every PL-side AXI clock
  domain and the inference engine.

### 8.5.4 Programmable Logic (PL) configuration

The Programmable Logic is populated by three main IP cores plus the
SmartConnect fabric: `axi_dma_0`, `u_atcnet` and `rst_ps8_0_60M`. The
`u_atcnet` cell is a custom **module-reference** that points at the
top-level Verilog wrapper `db_atcnet_axi_v.v` (see §8.5.13); from the
IPI's perspective it appears as an ordinary cell with the AXI-Stream,
AXI-Lite, clock, reset and interrupt ports exposed.

A post-route schematic of the implemented PL netlist — showing the
Zynq UltraScale+ PS, the AXI-DMA engine, the two AXI SmartConnect
fabrics, the processor-system reset block and the `u_atcnet`
inference accelerator with their fully-routed AXI4 / AXI4-Lite /
AXI4-Stream interconnect — is reproduced in **[Insert Figure 8-7
here — Post-route schematic of `db_atcnet_bd` on the ZCU106 / XCZU7EV
(from `docs/thesis_figures/fig_8-7_implemented_netlist_routed.png`)]**.

### 8.5.5 RTL refactors that landed the fit

Migrating the network from the Semester 1 single-pipeline prototype to the
full Semester 2 implementation revealed three resource-bottleneck patterns
that initially prevented the design from fitting on the ZCU106. Three
targeted refactors were applied to the SystemVerilog sources to resolve them:

1. **`rtl/attention/eca1_pipeline.sv` — flat-vector buffer.** The
   `buf_mem` ring buffer was originally declared as a two-dimensional
   unpacked array (`[N_FRAMES][NUM_CH]`); this prevented BRAM inference
   because a single memory cannot have NUM_CH simultaneous write ports.
   The buffer was refactored into a one-dimensional flat-vector array
   (`logic [BUF_W-1:0] buf_mem [0:N_FRAMES-1]`) with the
   `(* ram_style = "block" *)` attribute, and the write address was
   unified across the `S_IDLE` and `S_INGEST` states. **Result:** the
   local FF count dropped from 768 318 to 282 and 21 RAMB36 tiles were
   inferred.
2. **`rtl/conv/branch_pipeline.sv` — flat-vector branch buffers.**
   The `pre_conv_buf` and `post_conv_buf` arrays followed the same
   pattern. They were refactored into flat-vector form and a registered
   `pre_pad_reg` flag was introduced to replace the previous
   combinational `sep_sample_at_idx()` padding function. **Result:**
   approximately 75 k FFs of local logic eliminated per branch.
3. **`rtl/conv/avg_pool_time.sv` — module-level `use_dsp = "no"`.**
   The pool's per-channel multiplication by the constant `INV_POOL` was
   inferring DSP48E2 slices that the design could not spare. A
   module-level `(* use_dsp = "no" *)` attribute was added to force the
   constant multiply into LUTs and CARRY8 chains. **Result:** 7×64 = 448
   DSPs released, which was the difference between the design closing
   (99.5 % DSP utilization) and exceeding the budget.

All three refactors were verified against the pre-existing bit-exact
regression suite — the Semester 1 verification harness — to confirm that
they preserved the network's mathematical behavior.

### 8.5.6 Memory architecture and address map

The Semester 2 design uses three memory regions:

**Table 8-4 — Implemented memory map (matches the IPI Address Editor).**

| Block | Base address | Size |
|---|---|---|
| `db_atcnet_axi.s_axi` (AXI-Lite control regs) | `0x4_0000_0000` | 4 GB region |
| `axi_dma_0.S_AXI_LITE` (DMA control regs) | `0xA000_0000` | 64 KB |
| DDR4 (PS) | `0x0000_0000` | 2 GB |

Inside the `db_atcnet_axi.s_axi` AXI-Lite slave the relevant register
offsets are:

**Table 8-5 — `db_atcnet_axi` AXI-Lite register map.**

| Offset | Name | R/W | Semantics |
|---|---|---|---|
| `0xF000` | `STATUS_REG` | R/O | bit 0 = `busy`, bit 1 = `done` |
| `0xF004` | `CLASS_REG`  | R/O | bit 0 = class result; reading clears `done` |

The PS application copies each 6 000-byte EEG window into a cache-line-
aligned DDR4 buffer, flushes the data cache for that range, then triggers
an AXI-DMA MM2S transfer that streams the data into the PL accelerator.
After polling `STATUS_REG.done == 1`, the PS reads `CLASS_REG` (which
returns the class bit and atomically clears the `done` flag) and emits the
single class byte on PS UART1 to the ESP32-S3.

### 8.5.7 AXI Interconnect Architecture

The Semester 2 deployment uses **AXI SmartConnect** rather than the legacy
AXI Interconnect IP. Two SmartConnect instances are present:

- `axi_smc` — combines the AXI-Lite control traffic from the PS GP0 master
  to two control endpoints: the `axi_dma_0` register file and the
  `u_atcnet` AXI-Lite slave.
- `axi_smc_1` — bridges the AXI-DMA's MM2S master onto the PS HP0 slave
  port, performing the 32-to-128-bit width adapter needed by HP0.

SmartConnect handles clock-domain crossing automatically and provides
better timing closure than the legacy AXI Interconnect for the Zynq
UltraScale+ family.

### 8.5.8 Data transfer mechanisms

A single inference window is transferred end-to-end as follows:

1. The PS copies the 6 000-byte window from the UART1 RX FIFO into a
   cache-line-aligned DDR4 buffer.
2. The PS executes `Xil_DCacheFlushRange((INTPTR)eeg_buf, WIN_BYTES)` to
   force any cached copies of the buffer out to DDR.
3. The PS programs the AXI-DMA to perform a 6 000-byte MM2S transfer from
   the buffer address.
4. The DMA reads from DDR through the PS HP0 port, packs the 32-bit
   beats onto its AXI4-Stream master, and streams them into the
   `u_atcnet.s_axis` slave.
5. The DB-ATCNet pipeline consumes the stream at one beat per `pl_clk0`
   cycle, processes the window through the full network and asserts
   `STATUS_REG.done`.
6. The PS polls `STATUS_REG`, reads `CLASS_REG` and transmits the class
   byte over UART1.

### 8.5.9 Constraints

The Semester 2 design uses two project-level XDC files. The first,
`constraints/db_atcnet_axi.xdc`, contains the timing-critical false-path
constraint and the historical RAM-style hint:

```tcl
# constraints/db_atcnet_axi.xdc — design-wide timing constraints
create_clock -period 16.667 -name pl_clk0 [get_ports clk]   ;# 50 MHz
set_false_path -from [get_ports rst]
```

The second, `constraints/uart1_emio_pmod.xdc`, pins the EMIO-routed PS
UART1 to PL pins AL17 / AH17 (CP2108 channel 2) on the ZCU106 with the
LVCMOS12 standard mandated by the board's I/O bank voltage:

```tcl
# constraints/uart1_emio_pmod.xdc — PS UART1 EMIO routing
set_property PACKAGE_PIN AL17      [get_ports UART_1_0_txd]
set_property PACKAGE_PIN AH17      [get_ports UART_1_0_rxd]
set_property IOSTANDARD LVCMOS12  [get_ports UART_1_0_txd]
set_property IOSTANDARD LVCMOS12  [get_ports UART_1_0_rxd]
set_property DRIVE 8              [get_ports UART_1_0_txd]
set_property SLEW SLOW            [get_ports UART_1_0_txd]
```

This second XDC is required for bitstream generation; without it the
write_bitstream step fails the NSTD-1 / UCIO-1 design-rule checks.

### 8.5.10 Vivado Design Flow

The Semester 2 Vivado flow follows a strict sequence:

1. **Project creation.** Target `xczu7ev-ffvc1156-2-e`; board file
   `xilinx.com:zcu104:part0:1.1`.
2. **RTL source addition.** The complete `rtl/` tree is added including the
   top-level Verilog wrapper `rtl/db_atcnet_axi_v.v` (§8.5.13).
3. **IP Integrator block design.** The IPI BD `db_atcnet_bd` is created
   with the structure of §8.5.2.
4. **Synthesis.** `synth_design` is launched against the
   `db_atcnet_bd_wrapper` top. Synthesis runs to completion in
   approximately 28 seconds on a workstation-class machine, with all
   sub-IPs synthesized out-of-context (OOC) for incremental rebuilds.
5. **Implementation.** `opt_design`, `place_design`, `route_design` and
   `phys_opt_design` are executed in sequence. Implementation runs to
   completion in ≈ 80 minutes on the same machine.
6. **Bitstream generation.** `write_bitstream` produces
   `db_atcnet_bd_wrapper.bit` (≈ 19 MB).
7. **Hardware-platform export.** `write_hw_platform -fixed -include_bit`
   produces `db_atcnet_zcu106.xsa` (≈ 7.1 MB).

### 8.5.11 Timing Closure at 50 MHz

The implemented bitstream closes timing at `pl_clk0 = 50 MHz`. Post-route
timing analysis reports:

- **Worst Negative Slack (WNS):** **+1.864 ns** (setup)
- **Total Negative Slack (TNS):** 0.000 ns
- **Worst Hold Slack (WHS):** **+0.010 ns** (hold)
- **Total Hold Slack (THS):** 0.000 ns
- **Failing endpoints (setup):** 0 of 333 052 total
- **Failing endpoints (hold):** 0 of 333 052 total
- **Clock pair classification:** *Clean*

Both WNS and WHS are positive, indicating that the design meets all
setup and hold-time constraints across the full PVT corner with margin.
A visual summary of the post-route clock interaction is reproduced in
**[Insert Figure 8-9 here — Post-route clock-interaction timing summary
for `clk_pl_0` at 50 MHz (from
`docs/thesis_figures/fig_8-9_clock_interaction_timing.png`)]**.

The 50 MHz operating frequency is a deliberate relaxation from the
Semester 1 prototype's 100 MHz: the full Semester 2 network — with its
dual-branch attention, attention temporal fusion, and dense classifier
stages — has substantially deeper combinational paths than the
Semester 1 single-pipeline prototype. The path through the most heavily
loaded MAC tree in `conv2d_temporal` and through the `eca1_pipeline`
flat-vector BRAM read defines the critical path. A 60 MHz operating
point was attempted first (see §8.10.5) but failed timing closure due
to additional routing congestion introduced by the ZCU106's specific
clock-region floorplan; the relaxation to 50 MHz comfortably exceeds
the real-time inference budget. At 250 Hz EEG sample rate (4 ms
inter-arrival), the 2.31 ms inference still leaves ≈ 4 300× margin in
the BCI control loop.

### 8.5.12 Final Resource Utilization

The post-implementation resource utilization on the ZCU106 (XCZU7EV-2e)
is summarized in Table 8-6 and reproduced visually in **[Insert Figure 8-8
here — Vivado post-implementation hierarchical utilization report on
the ZCU106 (from
`docs/thesis_figures/fig_8-8_utilization_zcu106.png`)]**.

**Table 8-6 — Semester 2 implementation resource utilization (XCZU7EV).**

| Resource | Used | Available | Utilization |
|---|---|---|---|
| Slice LUTs | 193 186 | 230 400 | **84 %** |
| Slice Registers | 103 487 | 460 800 | 22 % |
| 36 Kb BRAM tiles | 80.5 | 312 | 26 % |
| UltraRAM | 0 | 96 | 0 % |
| CARRY8 | 14 500 | 28 800 | 50 % |
| LUT as Logic | 193 015 | 230 400 | 84 % |
| LUT as Memory | 171 | 101 760 | < 1 % |
| **DSP48E2 slices** | **1 719** | **1 728** | **99.5 %** |
| BUFGCE | 26 | 208 | 13 % |
| BUFG_PS | 1 | 96 | 1 % |
| PS8 | 1 | 1 | 100 % |
| Bonded IOB | 2 | 360 | < 1 % |

The design uses **nine DSPs shy of the full XCZU7EV DSP budget** (1 719
of 1 728, or 99.5 %). Without the three RTL refactors of §8.5.5 the
design would have exceeded the DSP budget by approximately 4 % and
would not have fit on the device. The Bonded IOB count of two
corresponds to the `UART_1_0_txd` and `UART_1_0_rxd` external ports
pinned to package locations AL17 and AH17 per the ZCU106 board file
(see §8.5.9 and §8.5.17).

### 8.5.13 IPI module-reference wrapper (`db_atcnet_axi_v.v`)

A subtle property of the Vivado IPI flow is that the IPI does not
propagate Verilog `generic` parameters from the BD instantiation through
the out-of-context (OOC) sub-synth of a module-reference cell. The
DB-ATCNet RTL relies on 29 `*_FILE` generics that point at the on-disk
Q8.8 weight and look-up-table hex files for each layer. To overcome this,
a thin Verilog wrapper `rtl/db_atcnet_axi_v.v` was authored that
instantiates the SystemVerilog `db_atcnet_axi` module and **hardcodes the
29 absolute paths** of the weight/LUT files. This wrapper is the entity
that the IPI references; the underlying SystemVerilog logic is unchanged.
A representative excerpt:

```verilog
// rtl/db_atcnet_axi_v.v (excerpt)
db_atcnet_axi #(
    .CONV2D_W_FILE         ("/.../weights/conv2d_W.hex"),
    .CONV2D_B_FILE         ("/.../weights/conv2d_B.hex"),
    .ECA1_W_FILE           ("/.../weights/eca1_W.hex"),
    .SIG_LUT_FILE          ("/.../luts/sigmoid.hex"),
    .ELU_LUT_FILE          ("/.../luts/elu.hex"),
    /* ... 24 more *_FILE generics ... */
) u_inst (
    .clk        (clk),
    .rst        (rst),
    .s_axis_tdata (s_axis_tdata),
    /* ... AXI4-Stream and AXI4-Lite ports ... */
);
```

Without this wrapper the synthesis of `u_atcnet` produces a black box and
the bitstream omits the inference engine entirely.

### 8.5.14 Vitis Embedded Platform and Bare-Metal Application

The PS-side software stack is implemented using the **Vitis Unified IDE
2025.2** and the Vitis Embedded Development toolchain. The platform is
created from the exported `db_atcnet_zcu104.xsa` and configured for a
**standalone** OS targeting `psu_cortexa53_0`. The platform build emits:

1. A board-specific Board Support Package (BSP), with libraries `xilstandalone`,
   `xilffs`, `xilsecure`, and the device drivers `xaxidma`, `xuartps`,
   `xscugic`, `xclockps`, `xresetps`, etc.
2. A bare-metal **First-Stage Boot Loader (FSBL)** targeted at the
   Cortex-A53, capable of programming the PL from the embedded bitstream
   and handing off to the application.
3. A **Platform Management Unit Firmware (PMUFW)** for the on-die PMU.

The application is created as an `Empty Application(C)` on the platform,
populated with the project's `main.c`, and built against the standalone
BSP. The compiled ELF is 388 KB (text 54 KB, data 3 KB, BSS 30 KB) which
fits comfortably in the 256 KiB OCM but is deployed in DDR4 to keep OCM
free for low-latency runtime structures.

**Note on the system software model in production.** The implemented
deployment in this thesis runs on bare-metal Cortex-A53. The wider design
*specifies* an Embedded Linux / PetaLinux-based system software for
production deployment to support a richer set of safety services, file
systems for EEG session storage and integration with the security
algorithms documented in §8.4.4. The bare-metal application of this thesis
exercises the same hardware platform, AXI fabric and DDR controller as
the production Linux stack would use; the migration would change the
software stack but not the hardware design.

### 8.5.15 PS-Side C application

The PS bare-metal application is the host that drives the DB-ATCNet
inference loop. Its main responsibilities are documented in Chapter 7,
§7.11.1. A representative excerpt of the device-bringup section is:

```c
/* main.c — Zynq PS bare-metal host application (excerpt). */

#define DBA_BASE_ADDR      0x400000000ULL    /* matches BD addr-editor */
#define DBA_STATUS_OFFSET  0xF000             /* bit0=busy, bit1=done */
#define DBA_CLASS_OFFSET   0xF004             /* bit0=class           */
#define DBA_STATUS_BUSY    (1U << 0)
#define DBA_STATUS_DONE    (1U << 1)

#define WIN_SAMPLES        3000
#define WIN_BYTES          (WIN_SAMPLES * 2)

#define ESP_UART_BAUD      460800
#define ESP_UART_BASEADDR  XPAR_XUARTPS_1_BASEADDR    /* PS UART1 */
#define DMA_BASEADDR       XPAR_XAXIDMA_0_BASEADDR

static u8 eeg_buf[WIN_BYTES] __attribute__((aligned(64)));
static XAxiDma  dma;
static XUartPs  esp_uart;

static int init_uart_to_esp(void) {
    XUartPs_Config *cfg = XUartPs_LookupConfig(ESP_UART_BASEADDR);
    if (!cfg) return XST_FAILURE;
    int status = XUartPs_CfgInitialize(&esp_uart, cfg, cfg->BaseAddress);
    if (status != XST_SUCCESS) return status;
    XUartPs_SetBaudRate(&esp_uart, ESP_UART_BAUD);
    XUartPs_SetOperMode(&esp_uart, XUARTPS_OPER_MODE_NORMAL);
    return XST_SUCCESS;
}

static int init_dma(void) {
    XAxiDma_Config *cfg = XAxiDma_LookupConfig(DMA_BASEADDR);
    if (!cfg) return XST_FAILURE;
    int status = XAxiDma_CfgInitialize(&dma, cfg);
    if (status != XST_SUCCESS) return status;
    XAxiDma_IntrDisable(&dma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);
    XAxiDma_IntrDisable(&dma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DMA_TO_DEVICE);
    return XST_SUCCESS;
}
```

The Vitis 2025.2 toolchain uses the **System Device Tree (SDT)** flow
for resource enumeration; consequently the application uses
`XPAR_*_BASEADDR` constants rather than the legacy `XPAR_*_DEVICE_ID`
constants used by older Vivado/Vitis releases.

### 8.5.16 UART Communication with the ESP32

The PS UART1 to ESP32-S3 link is the primary data path between the FPGA
inference engine and the actuator-controller subsystem. The implemented
protocol is intentionally minimal:

| Direction | Payload | Notes |
|---|---|---|
| ESP32-S3 → Zynq | 6 000 bytes (3 000 × little-endian Q8.8) | One inference window per transmission, no framing bytes. |
| Zynq → ESP32-S3 | 1 byte (`0x00` hand-grip / `0x01` ankle) | Sent immediately after `STATUS_REG.done` asserts. |

Both directions run at **460 800 8N1**, no flow control. The 460 800
baud choice provides headroom both for the existing 1 byte / inference
return path and for a future bidirectional bio-amp data stream without
re-flashing the bitstream or the firmware.

The receiver re-synchronizes on idle: there are no framing bytes in the
6 000-byte EEG payload, so framing relies on the 460 800-baud serial line
being idle for at least one byte time between windows. A
`XUartPs_Recv()` call with the 6 000-byte buffer and a deadline of 1 500 ms
(approximately 12× the expected 130 ms payload time) is used in the PS
application.

### 8.5.17 PS UART1 routing via EMIO to PL pins

The Zynq UltraScale+ PS UART1 is not exposed on the ZCU106's MIO; instead,
the IPI BD configuration enables PS UART1 on EMIO and routes the resulting
PL ports `UART_1_0_txd` / `UART_1_0_rxd` to the on-board CP2108 USB-UART
bridge through PL pins AL17 and AH17 (see §8.5.9). The CP2108 then exposes
this UART as a virtual serial port on the host laptop, where the bench-time
host-bridge tool (`sw/host/bridge.py`) forwards data to the ESP32-S3's USB
serial connection.

In the production-target wearable build the PL pins AL17/AH17 are wired
directly to the ESP32-S3's UART2 RX/TX (GPIO16/17) pins, eliminating the
host-bridge step. The bitstream, RTL and constraints are identical in
both cases; only the off-board wiring changes.

### 8.5.18 Real-Time Inference Pipeline

The complete end-to-end real-time inference pipeline is:

1. **EEG window** (6 000 bytes = 3 000 × Q8.8 samples) arrives at PS UART1
   at 460 800 baud over ≈ 130 ms.
2. **PS bare-metal application** copies the window into a 64-byte-aligned
   DDR4 buffer and flushes the data cache.
3. **AXI-DMA MM2S** transfer is started; the engine reads from DDR through
   HP0 and presents the data on the AXI4-Stream master.
4. **`u_atcnet.s_axis`** consumes the stream and the deeply pipelined
   DB-ATCNet inference engine processes it through every stage.
5. **`u_atcnet.STATUS_REG.done`** asserts after ≈ 115 k cycles
   (≈ 2.31 ms at 50 MHz).
6. **PS reads `CLASS_REG`** (which clears `done`) and obtains the binary
   class.
7. **PS transmits 1 byte** on PS UART1 (≈ 25 µs at 460 800 baud).
8. **ESP32-S3** receives the class byte, applies the safety state machine
   and updates the corresponding PCA9685 channel.

### 8.5.19 Hardware acceleration strategy

The Semester 2 design exploits FPGA parallelism in four distinct ways:

- **Spatial parallelism in convolutional MACs.** Each clock cycle, all
  K_E × K_T (kernel-element × kernel-time) multiplications of a single
  output tap are executed in parallel by dedicated DSP48E2 slices.
- **Dual-branch attention concurrency.** Branches A and B of the
  attention dual-branch convolution operate concurrently on the same
  input stream, enabling 2× throughput at no extra latency cost.
- **Deep pipelining.** Every functional block is pipelined deeply enough
  that the per-cycle critical path is bounded by the longest single
  multiply-add and the per-window latency is bounded by the deepest
  pipeline stage's latency plus the data-arrival time.
- **Zero-cache deterministic execution.** All inter-stage storage is in
  flip-flops, shift registers or BRAM with single-cycle access. There
  are no caches, no DRAM accesses on the critical path, and no variable-
  latency operations, which yields strict cycle-deterministic execution.

### 8.5.20 Software stack

The implemented software stack for the Semester 2 deployment consists of:

- **Vivado Design Suite 2025.2** — RTL synthesis, IPI block design,
  implementation, bitstream generation, hardware platform export.
- **Vitis Unified IDE 2025.2** with the Vitis Embedded Development
  toolchain — platform creation, BSP build, FSBL/PMUFW generation,
  bare-metal application build and JTAG load.
- **Embedded Linux / PetaLinux** — specified as the production system
  software target for the wearable deployment, providing file system
  support for stored-data sessions, integration with the security
  algorithms of §8.4.4 and a TCP/IP stack for remote telemetry.
- **Vitis Embedded driver libraries** (`xilstandalone`, `xilffs`,
  `xilsecure`, `xaxidma`, `xuartps`, `xscugic`, etc.) used by both the
  bare-metal and the production Linux software stacks.
- **AArch64 GNU toolchain** bundled with Vitis 2025.2 used for compiling
  the application against the BSP.
- **Arduino IDE 2.x** with the ESP32-S3 board package and the
  `Adafruit_PWMServoDriver` library for the actuator-controller firmware.
- **Python 3.12** with `pyserial` for the host-side debug and bench bridge.

The full Vivado + Vitis flow is fully scripted (`scripts/vitis/build_app.tcl`)
to ensure reproducibility from the source repository.

---

## 8.6 Code Listings

This section presents representative code excerpts from the three main
codebases that constitute the Semester 2 deployment.

### 8.6.1 SystemVerilog: temporal convolution pipeline

The `temporal_conv` module implements the convolutional MAC tree at the
heart of every DB-ATCNet temporal layer. An excerpt of its pipelined
3-stage segmented MAC tree is:

```systemverilog
// rtl/conv/conv2d_temporal.sv (excerpt)
generate
    for (genvar seg = 0; seg < N_SEGMENTS; seg++) begin : g_seg
        always_ff @(posedge clk) begin
            // Stage 1: 8 parallel multiplies per segment.
            for (int t = 0; t < N_TAPS; t++)
                mac_seg[seg][t] <= $signed(buf_in[seg*N_TAPS+t])
                                * $signed(w_seg[seg][t]);
            // Stage 2: per-segment partial sum.
            sum_seg[seg] <= mac_seg[seg].sum();
        end
    end
endgenerate

always_ff @(posedge clk)
    // Stage 3: cross-segment final sum.
    out_q <= sum_seg.sum() + $signed(bias);
```

### 8.6.2 SystemVerilog: flat-vector eca1 buffer (post-refactor)

The `eca1_pipeline` module's `buf_mem` ring buffer was refactored into a
flat-vector form to enable BRAM inference:

```systemverilog
// rtl/attention/eca1_pipeline.sv (excerpt, post-refactor)
localparam int BUF_W = NUM_CH * Q88_W;   // pack one frame into one wide word
(* ram_style = "block" *) logic [BUF_W-1:0] buf_mem [0:N_FRAMES-1];

always_ff @(posedge clk) begin
    if (we) buf_mem[cnt] <= frame_in;      // single-port BRAM write
end
// Unpack on read.
generate
    for (genvar c = 0; c < NUM_CH; c++)
        assign frame_out[c] = $signed(buf_mem[rd_addr][c*Q88_W +: Q88_W]);
endgenerate
```

### 8.6.3 ESP32-S3 firmware: UART2 + I²C bring-up

The ESP32-S3 firmware (`sw/esp32/db_atcnet_esp32.ino`) configures its
hardware UART2 and the shared I²C bus at boot:

```cpp
// sw/esp32/db_atcnet_esp32.ino (excerpt — ESP32-S3 target)
constexpr long      UART2_BAUD       = 460800;
constexpr int       UART2_RX_PIN     = 18;        // Zynq PS UART1 TX
constexpr int       UART2_TX_PIN     = 17;        // Zynq PS UART1 RX
constexpr int       I2C_SDA_PIN      = 8;         // shared with ADS1115 + PCA9685
constexpr int       I2C_SCL_PIN      = 9;
constexpr uint32_t  I2C_CLOCK_HZ     = 400000;    // Fast-mode I2C
constexpr uint8_t   PCA9685_ADDR     = 0x40;
constexpr uint32_t  SERVO_FREQ_HZ    = 50;

void setup() {
    Serial.begin(115200);   // USB-serial debug
    Serial2.begin(UART2_BAUD, SERIAL_8N1, UART2_RX_PIN, UART2_TX_PIN);
    Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN);
    Wire.setClock(I2C_CLOCK_HZ);
    pca9685.begin();
    pca9685.setPWMFreq(SERVO_FREQ_HZ);
    state_machine.transition(STATE_HOMING);
}
```

### 8.6.4 Vitis build automation (xsct script)

To make the Vitis platform/application build fully reproducible from the
source tree, the project ships an `xsct` Tcl script that drives the full
build sequence:

```tcl
# scripts/vitis/build_app.tcl (excerpt)
setws $WORKSPACE
platform create -name $PLATFORM_NAME -hw $XSA \
                -proc psu_cortexa53_0 -os standalone \
                -fsbl-target psu_cortexa53_0 -out $WORKSPACE
platform active $PLATFORM_NAME
platform generate
app create -name $APP_NAME -platform $PLATFORM_NAME \
           -domain standalone_psu_cortexa53_0 \
           -template "Empty Application(C)"
importsources -name $APP_NAME -path $MAIN_C
app build -name $APP_NAME
```

---

## 8.7 SystemVerilog Architecture Analysis

The Semester 2 RTL hierarchy is organized to mirror the DB-ATCNet
architectural blocks of Figure 8-5. The top-level wrapper
`db_atcnet_axi` encapsulates the entire inference engine and exposes
only the AXI4-Stream, AXI4-Lite and interrupt interfaces to the IPI:

- `db_atcnet_axi` *(top-level AXI wrapper)*
  - `conv2d_temporal` — initial temporal convolution
  - `eca1_pipeline` — efficient channel attention #1
  - `branch_pipeline` × 2 (Branch A and Branch B) — dual-branch
    depthwise + separable convolutions
  - `cbam_channel_attn` — CBAM channel attention (D1/D2 pipelined)
  - `cbam_spatial_attn` — CBAM spatial attention with segmented partial
    sums
  - `eca2_pipeline` — efficient channel attention #2
  - `tcfn_pipeline` × 4 — attention temporal fusion convolution blocks
  - `dense_classifier` — 2-stage pipelined MAC dense head
  - Q8.8 fixed-point arithmetic throughout

**Clock and reset domains.** A single clock domain (`pl_clk0` at 50 MHz)
is used across the entire inference engine. Reset is supplied by the
IPI's `rst_ps8_0_60M` block and is treated as a synchronous active-low
signal at every module boundary.

**FSM design.** The streaming ingress logic uses a small three-state
FSM (`S_IDLE`, `S_INGEST`, `S_DONE`) that handshakes with the AXI-Stream
TVALID/TREADY signals and emits a `done` pulse on the AXI-Lite STATUS
register.

**Pipeline depth.** The end-to-end pipeline depth from the first stream
beat to `STATUS_REG.done` is approximately 115 k cycles, dominated by
the convolutional MAC tree depth and the attention temporal fusion
network's serial accumulation.

**Resource implications.** The pipelining choices — particularly the
3-stage MAC segmentation in `conv2d_temporal`, the D1/D2 split in
`cbam_channel_attn` and the segmented partial sums in
`cbam_spatial_attn` — were calibrated against the timing closure
constraint at 50 MHz; deeper pipelining would close timing at higher
frequencies but is not required for the project's BCI latency budget.

---

## 8.8 Performance Evaluation across Semesters

The performance of the Semester 1 prototype and the Semester 2
implementation is summarized side-by-side in Table 8-7.

**Table 8-7 — Cross-semester performance summary.**

| Metric | Semester 1 (Zynq-7030 proto.) | Semester 2 (ZCU106 full) |
|---|---|---|
| FPGA device | xc7z030 | XCZU7EV-2FFVC1156 |
| PS processor | Cortex-A9 (×2) | Cortex-A53 (×4) + R5 (×2) + Mali-400 |
| Operating frequency `pl_clk0` | 100 MHz | **50 MHz** |
| Inference latency | 640 ns (proof-of-concept slice) | **≈ 2.31 ms (full network)** |
| Worst Negative Slack (WNS) | +3.222 ns | **+1.864 ns** |
| Worst Hold Slack (WHS) | not reported | +0.010 ns |
| LUTs used | 2 662 (3.39 %) | **193 186 (84 %)** |
| FFs used | 1 568 (1.00 %) | 103 487 (22 %) |
| DSPs used | 16 (4.00 %) | **1 719 (99.5 %)** |
| BRAM tiles used | not reported | 80.5 (26 %) |
| Total on-chip power (Vivado Power Report) | not reported | **5.109 W** |
| Throughput | 100 MSPS (theoretical) | 50 MSPS (continuous stream) |
| Network coverage | single representative stage | **complete DB-ATCNet** |
| Verification | bit-exact regression vs Python ref | same harness, scaled up |

The principal observations are:

1. The Semester 2 implementation deploys the **complete DB-ATCNet
   inference engine**, whereas Semester 1 deployed a single
   representative pipeline stage.
2. The Semester 2 operating frequency (50 MHz) is lower than the
   Semester 1 prototype's (100 MHz), reflecting the much deeper
   combinational paths of the full network. This is an intentional
   trade-off: a 2.31 ms inference at 50 MHz is more than 5 000× faster
   than the 250 Hz EEG arrival rate, so the loop margin is unchanged in
   practical terms.
3. The migration to a larger device (XCZU7EV vs xc7z030) was strictly
   necessary; the full network's 1 719 DSPs exceed the Zynq-7030's
   400-DSP budget by a factor of ≈ 4.3×.
4. The Semester 1 verification harness — golden Q8.8 vectors generated
   from the Python reference — was reused unchanged in Semester 2,
   providing continuity and confidence in the migrated design.

---

## 8.9 Power Analysis

The implemented design's power consumption was measured post-route using
the Vivado Power Report tool against the routed checkpoint, with
vector-less switching-activity estimation at 25 °C ambient and the
Vivado-default vector-less confidence level (low). The summary is
reproduced in Table 8-7 and visualized in **[Insert Figure 8-10 here —
Vivado on-chip power summary at 50 MHz, 25 °C ambient (from
`docs/thesis_figures/fig_8-10_power_summary.png`)]**.

**Table 8-7 — Post-route on-chip power summary (XCZU7EV, 50 MHz).**

| Component | Power | Share of total |
|---|---:|---:|
| **Total on-chip power** | **5.109 W** | 100 % |
| Dynamic (subtotal) | 4.405 W | 86 % |
|     Clocks | 0.106 W | 2 % |
|     Signals | 0.737 W | 17 % |
|     Logic | 0.678 W | 15 % |
|     BRAM | 0.032 W | 1 % |
|     DSP | 0.196 W | 4 % |
|     I/O | < 0.001 W | < 1 % |
|     PS (Cortex-A53 + peripherals) | 2.655 W | 60 % |
| Static (subtotal) | 0.704 W | 14 % |
|     PL leakage | 0.604 W | 12 % |
|     PS leakage | 0.100 W | 2 % |

The **Processing System dominates the dynamic-power budget at 60 %
(2.655 W)** — primarily the active Cortex-A53 cluster, the DDR4
controller and the SCU/L2 caches. The Programmable-Logic side is
unexpectedly modest given its 99.5 % DSP utilization: BRAM consumes
only 32 mW, DSP slices 196 mW, and the clock network 106 mW. Together
the PL active power is approximately 1.75 W (excluding the PS),
leaving 90 % of the chip-level thermal headroom intact at 25 °C
ambient.

The Vivado power report establishes the following thermal margins
under default board-cooling assumptions (Effective θJA = 1.0 °C/W):

| Parameter | Value |
|---|---:|
| Junction temperature (T_J) | 30.0 °C |
| Ambient temperature (T_A) | 25.0 °C |
| Thermal margin to T_J,max (100 °C) | 70.0 °C |
| Effective θJA | 1.0 °C/W |

Three implemented optimizations contribute to the modest PL-side
dynamic power:

- **Clock gating** is enabled by Vivado's default synthesis on the
  inference engine's idle-state branches, so the DSP slices only toggle
  during a window's inference period (≈ 2.31 ms per 4 ms sample window,
  giving an effective duty cycle of ≈ 58 %).
- **`use_dsp = "no"` on `avg_pool_time`** (§8.5.5) forces a small block
  to LUTs and CARRY8 chains rather than DSPs, which were already at
  99.5 % utilization; this both fits the design and reduces
  unnecessarily allocated DSP activity.
- **BRAM packing** for the eca1 ring buffer (§8.5.5) allowed Vivado to
  power-gate large blocks of distributed RAM that the pre-refactor
  design used heavily.

A wearable variant of the system would benefit from additional PS-side
optimizations (Cortex-A53 frequency scaling, DDR self-refresh, PL clock
disabling between inferences) that are documented as future work in
§8.12. With a LiPo 3S battery of 2200 mAh capacity, the implemented
system draws approximately 5.1 W from the supply, giving an estimated
continuous-operation runtime of (11.1 V × 2.2 Ah) / 5.1 W ≈ **4.8
hours**, well in excess of a single rehabilitation-therapy session.

---

## 8.10 Deployment Challenges and Resolutions

Three categories of deployment challenge were encountered during the
Semester 2 work; their resolutions are documented here both for
reproducibility and as engineering lessons for future ZCU106
deployments.

### 8.10.1 Vivado synthesis memory exhaustion

The pre-refactor `eca1_pipeline.sv` module synthesized into ≈ 768 k
flip-flops, which pushed Vivado's process memory beyond the 16 GB
workstation's physical RAM and triggered swap thrashing. The fix
(flat-vector buffer with `ram_style = "block"`, §8.5.5) reduced the
local FF count to 282 and allowed synthesis to complete in 28 s
with a 4 GB peak.

### 8.10.2 Constraint validation stall

The original `db_atcnet_axi.xdc` contained
`set_false_path -from rst -to [all_registers]`, which Vivado expanded
into approximately one million endpoint pairs during constraint
validation, stalling synthesis for hours. Replacing the constraint
with `set_false_path -from [get_ports rst]` (without the explicit
`-to`) reduced the constraint to a single source-side declaration
and constraint validation to under 1 second.

### 8.10.3 Vitis 2025.2 ZynqMP platform-creation regression

Vitis Unified IDE 2025.2's Python CLI exhibits a regression in which
`client.create_platform_component(...)` reliably fails with
`Application error processing RPC` for *any* ZynqMP fixed XSA,
including AMD's own example `zcu106.xsa`. The Java backend completes
the SDT generation and the CPU list, then drops the gRPC connection
between the server and the Python client. The workaround applied was:

1. Install the **Vitis Embedded Development** package alongside the
   base Vitis 2025.2 install.
2. Use the unified IDE's **graphical** Create Platform Component flow,
   which invokes the same backend operations through a slightly
   different RPC sequence that does not trigger the regression.

The bitstream and `.xsa` produced under the GUI flow are byte-identical
to what the failing Python flow would have produced; only the
platform-component creation path is affected.

### 8.10.4 SDT-based driver enumeration

Vitis 2025.2's bare-metal application uses the **System Device Tree
(SDT)** flow for resource enumeration, which has removed the legacy
`XPAR_*_DEVICE_ID` constants in favor of `XPAR_*_BASEADDR`. Application
code targeting Vitis 2024.x or earlier must be updated to use
`XUartPs_LookupConfig(XPAR_XUARTPS_1_BASEADDR)` rather than
`XUartPs_LookupConfig(XPAR_XUARTPS_1_DEVICE_ID)`. The PS application
in §8.5.15 has been adapted to the new API.

### 8.10.5 Board misidentification and 60 → 50 MHz timing trade-off

A two-stage deployment issue was encountered during the Semester 2
hardware bring-up that warrants documentation as a lesson learned.

**Stage 1 — Board misidentification.** The bring-up bench initially
targeted the Xilinx ZCU104 evaluation board for the entire Vivado IPI,
synthesis, implementation, bitstream, `.xsa` export and Vitis platform
flow. During pre-flight JTAG verification at the laboratory the board
silkscreen and the FPGA top-marking were re-examined, and the hardware
was identified as a **ZCU106 evaluation board** with the same chip
`XCZU7EV-2FFVC1156`. This was a non-trivial discovery: the chip is
identical to the ZCU104's, but the surrounding PCB peripherals
(CP2108 USB-UART channel mapping, PMOD locations, on-board LED/switch
locations, PS-to-PL voltage banks) differ between the two boards.
The Vivado board file was retargeted from
`xilinx.com:zcu104:part0:1.1` to `xilinx.com:zcu106:part0:2.6`, and the
custom XDC was updated from the ZCU104 `uart2_PL` pins (C19/A20,
LVCMOS18) to those of the ZCU106 (AL17/AH17, LVCMOS12). The
Zynq-PS preset was reapplied to absorb the new MIO map and DDR
configuration. The user RTL was unchanged.

**Stage 2 — Routing congestion at 60 MHz.** With the ZCU106 board file
applied, the re-targeted implementation closed placement comfortably
(Worst Negative Slack +1.486 ns at place) but the router introduced
2.16 ns of additional delay due to the ZCU106's different clock-region
floorplan, yielding a final post-route WNS of −0.677 ns and a total
negative slack of −18.754 ns. The bitstream completed but failed
static-timing closure. After verifying that the failing paths were
spread across the inference engine's MAC trees (not localised to a
single fixable net), the operating frequency was **relaxed from 60 MHz
to 50 MHz**. At the new 20 ns period the re-run closed with WNS
+1.864 ns and WHS +0.010 ns with 0 failing endpoints, as documented in
§8.5.11. The 50 MHz operating frequency increases the per-window
inference latency from 1.92 ms to 2.31 ms, which is functionally
inconsequential because the EEG sample arrival rate is 250 Hz (4 ms
per sample). The board-pivot + clock-relaxation pair is therefore the
final operating point of the deployed system.

---

## 8.11 FPGA Deployment Workflow

The complete, end-to-end deployment workflow used to produce the
Semester 2 system is summarized below. Each step references the
section in which it is described in detail.

1. **Generate Q8.8 weights** for every DB-ATCNet layer from the trained
   floating-point checkpoint using the Python pipeline in `scripts/`.
2. **Run the bit-exact RTL simulation regression** to confirm that the
   updated weights produce the expected class on the golden EEG
   window (§8.4.6).
3. **Synthesize the design out-of-context** to confirm resource fit
   on the XCZU7EV (§8.5.10–§8.5.12).
4. **Build the IPI block design** `db_atcnet_bd` with the structure of
   §8.5.2 and validate it.
5. **Run implementation and bitstream generation** in Vivado
   (§8.5.10–§8.5.11).
6. **Export the hardware platform** as `db_atcnet_zcu104.xsa`
   (§8.5.10).
7. **Create the Vitis platform** from the `.xsa` and build the BSP +
   FSBL + PMUFW (§8.5.14).
8. **Create the bare-metal application**, drop `main.c` into its
   `src/` directory and build the ELF (§8.5.15).
9. **Power the ZCU106**, set boot-mode SW6 to JTAG, connect the
   on-board USB and load the bitstream + ELF over JTAG from Vitis.
10. **Connect the ESP32-S3 dev board**, flash the firmware from the
    Arduino IDE and verify the I²C bus and PCA9685 (§7.8, §7.12).
11. **Stream a test EEG window** from the host into PS UART1 and
    verify that the ESP32-S3 receives the corresponding class byte and
    actuates the correct servo (§8.5.18).

The same workflow is documented in machine-readable form in
`PHASE_B_BRINGUP.md`.

---

## 8.12 Future Enhancements

Future work may extend the FPGA utilization and the BCI capability in
the following directions:

- **Dynamic partial reconfiguration.** Allow the inference engine to be
  swapped in-field between MI variants without a full board re-boot,
  which would support multi-subject calibration without re-flashing the
  bitstream.
- **Hardware-level security primitives.** Move the AES-256-GCM and
  HMAC-SHA-256 operations of §8.4.4 from the PS into dedicated PL
  cryptographic accelerators that operate at line rate on the EEG
  stream, eliminating any timing variability and reducing PS load.
- **Power-aware optimizations** for wearable BCI systems, including
  PS clock-frequency scaling between inferences, DDR self-refresh and
  PL-clock gating in the idle window between successive 4 ms EEG
  samples.
- **Partial or full acceleration of additional inference stages**, e.g.
  moving the FBCSP / Riemannian-geometry preprocessing pipelines [4],
  [68] into the PL for closed-loop comparison against DB-ATCNet.
- **Live-EEG migration to the production Linux stack** with the
  security algorithms of §8.4.4 enabled, providing the certified BCI
  data path required for clinical evaluation.
- **Multi-class extension.** The implemented network classifies two MI
  classes (hand-grip vs. ankle); the underlying DB-ATCNet architecture
  supports the full four-class BCI Competition IV-2a [30] taxonomy,
  which would extend the system's rehabilitation coverage to additional
  joints.

---

## 8.13 Summary

This chapter presented the FPGA-based acceleration and deployment of
the DB-ATCNet inference engine in two phases. Part A documented the
Semester 1 prototype on the Xilinx Zynq-7030 platform, which validated
the hardware–software co-design methodology, the security architecture,
the bit-exact verification flow and the early performance ceilings
(640 ns latency, 1 562× acceleration over the Cortex-A9 software
baseline) on a representative pipeline section of DB-ATCNet. Part B
documented the Semester 2 full deployment on the AMD/Xilinx Zynq
UltraScale+ MPSoC XCZU7EV on the ZCU106 evaluation board, in which the
*complete* DB-ATCNet network — all four temporal-convolution branches,
the dual-branch attention block, the temporal-fusion network and the
dense classifier — was implemented, fit (with 99.5 % DSP utilization),
brought to timing closure at 50 MHz (WNS +1.864 ns, WHS +0.010 ns), and
deployed via the Vivado IPI + Vitis Embedded bare-metal toolchain. The
full Semester 2 inference latency is approximately 2.31 ms — over
4 300× faster than the 250 Hz EEG arrival rate — which leaves the BCI
control loop a comfortable real-time margin and ensures that the
mechanical actuators are commanded well within the user's voluntary
motor-reaction threshold. Post-implementation power analysis reports a
total on-chip dissipation of 5.109 W (4.405 W dynamic + 0.704 W
static), of which the Cortex-A53 processing subsystem accounts for
60 % of the dynamic budget; this enables an estimated 4.8 hours of
continuous operation from a LiPo 3S 2200 mAh wearable battery, well in
excess of a single rehabilitation-therapy session. Combined with the
safety-critical analog front-end and actuator firmware of Chapter 7,
the implemented system demonstrates the feasibility of complete,
deterministic, FPGA-accelerated deep-learning inference for assistive
rehabilitation BCIs.

The complete FPGA deployment described here is captured in the project
repository under `rtl/`, `constraints/`, `synth/`, `sw/zynq_ps/` and
`scripts/vitis/`, and is reproducible from a clean repository check-out
using the Vivado 2025.2 and Vitis 2025.2 tooling that was validated in
the course of this work.

---

*End of Chapter 8.*
