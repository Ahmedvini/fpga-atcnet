# Chapter 7

# Hardware Design and Circuit Implementation

## 7.1 System Hardware Overview

The implemented Brain–Computer Interface (BCI) for assistive motion control is a
mixed-signal embedded platform that converts neural intent, captured as scalp
electroencephalographic (EEG) potentials, into controlled mechanical motion of
two rehabilitative actuators (an ankle servomotor and a hand-finger gripper
servomotor). The system supports two complementary operational modes — a
real-time live-EEG mode based on the OpenBCI Cyton/Daisy headset and a
stored-data mode based on a pre-recorded dataset hosted on an SD card — so that
the same hardware can be used both for online clinical evaluation and for
repeatable offline validation [1], [2], [54].

The complete hardware architecture is shown in
**[Insert Figure 7-1 here — System Hardware Architecture (from `thesis/full curcuit`)]**.
The architecture is partitioned into seven coupled subsystems:

1. **EEG acquisition subsystem** — OpenBCI Cyton/Daisy biopotential headset
   delivering up to sixteen channels of high-impedance scalp EEG [9].
2. **Signal conditioning subsystem** — a low-noise unity-gain instrumentation
   buffer built around the Texas Instruments TLV9061 operational amplifier,
   followed by a passive first-order RC low-pass filter that band-limits the
   EEG to the physiologically meaningful band.
3. **Data acquisition subsystem** — a Texas Instruments ADS1115 16-bit
   successive-approximation analog-to-digital converter (ADC) with an
   integrated programmable-gain amplifier and an I²C interface.
4. **Communication subsystem** — an Espressif ESP32-S3 dual-core microcontroller
   acting as the bridge between the analog-domain front-end and the digital
   FPGA back-end. The ESP32-S3 manages I²C transactions to the ADS1115,
   window-buffers EEG frames, and transmits them to the Zynq UltraScale+ over
   a hardware UART link.
5. **FPGA processing subsystem** — an AMD/Xilinx Zynq UltraScale+ MPSoC
   (XCZU7EV) hosted on the ZCU106 evaluation board. The Processing System
   (PS) implements supervisory control and host interfacing; the Programmable
   Logic (PL) implements the DB-ATCNet motor-imagery classifier as a fixed,
   deterministic dataflow accelerator [36], [86], [87].
6. **Servo control subsystem** — an NXP PCA9685 16-channel, 12-bit
   I²C-controlled Pulse Width Modulation (PWM) driver and two analog hobby-grade
   servomotors representing the ankle joint and the hand-finger gripper.
7. **Power subsystem** — a 3-cell (11.1 V nominal) lithium-polymer (LiPo)
   battery feeding an 8 A protection fuse, two switch-mode buck converters
   (6 V/6 A for actuators, 5 V/3 A for logic) and a low-noise 3.3 V linear
   dropout regulator (LDO) for analog rails, organized around a single star
   ground.

Logically the system follows a deterministic, unidirectional data path
(electrodes → analog conditioning → ADC → microcontroller → FPGA inference →
PWM controller → mechanical actuator), which is critical because all
downstream blocks must produce a fresh actuation decision within a fixed
window relative to the cortical event being decoded [3], [22], [73]. The
hardware partitioning into mixed-signal, processing and actuation domains
follows established practice for FPGA-accelerated embedded BCI platforms
[76], [77], [82].

---

## 7.2 Deep Circuit-Level Analysis

Chapter 7 is intended as a hardware *design* chapter rather than a parts
catalog. For each subsystem this section answers four engineering questions:

1. *Why was this specific component selected?*
2. *How does the component operate internally to the level of detail relevant
   for this design?*
3. *Why is it wired in the configuration shown on the schematic in
   **[Insert Figure 7-1 here]**?*
4. *What are the electrical and signal-integrity considerations, and what
   trade-offs were accepted?*

The discussion follows the EEG signal in its physical order through the
circuit: electrodes → analog buffer → analog filter → ADC → microcontroller →
FPGA → PWM driver → motor. Each subsystem is therefore both a logical block
and the next stage of a signal-processing chain whose objective is to convert
a noisy microvolt-scale biopotential into a deterministic mechanical command
with bounded end-to-end latency.

---

## 7.3 Signal Path Analysis

Table 7-1 summarizes the characteristics of the signal at every stage of the
chain. The values are derived directly from the implemented schematic
(**[Insert Figure 7-1]**), datasheets of the selected components and the
characterization of the ADS1115 and TLV9061 at the configured operating point.

**Table 7-1: Stage-by-stage signal characteristics of the implemented EEG-to-servo path.**

| Stage | Input | Output | Voltage range | Format | Dominant noise concern | Added latency |
|---|---|---|---|---|---|---|
| Scalp / electrode | brain dipole | differential potential | ±100 µV | analog continuous | tissue + electrode-half-cell noise [3] | n/a |
| OpenBCI headset | electrode pair | buffered, optionally amplified | ±100 µV (raw) / up to ±1 V (after onboard gain) | analog continuous | electrode-pop, line interference | < 1 ms |
| TLV9061 buffer | high-Z analog | low-Z analog | ±2.0 V (rail-headroom from 3.3 V supply) | analog continuous | op-amp voltage noise (≈ 10 nV/√Hz) | < 1 µs |
| RC low-pass filter | unfiltered buffered signal | band-limited signal | same as input | analog continuous | thermal noise of R; out-of-band attenuation | RC time constant ≈ 0.33 ms |
| ADS1115 ADC | analog single-ended | 16-bit two's-complement code | ±2.048 V (PGA = ±2.048 V) | digital, I²C | quantization (≈ 62.5 µV LSB) | 1/SPS (≈ 4 ms at 250 SPS) |
| ESP32-S3 | I²C words | Q8.8 16-bit fixed-point samples | n/a | digital, internal buffer | bus contention, ISR jitter | windowed at 250 Hz |
| PS UART1 link | byte stream | byte stream | LVCMOS12 | 460 800 8N1 | bit jitter | ≈ 130 ms for a 6000-byte window |
| PL inference engine | streamed Q8.8 EEG | 1-bit class | rail-to-rail | digital | none (bit-exact, deterministic) | ≈ 2.31 ms |
| PS UART1 return | byte | byte | LVCMOS12 | 460 800 8N1 | line jitter | ≈ 25 µs |
| PCA9685 PWM | I²C control word | 50 Hz analog PWM | 0–6 V | analog PWM | servo response | < 1 ms register write |
| Servo | PWM | torque, mechanical angle | mechanical | analog mechanical | mechanical wear, gear backlash | 100–300 ms (mechanical) |

The combined electrical end-to-end latency from the start of a 3-s analysis
window leaving the ESP32-S3 to the corresponding servo command leaving the
PCA9685 is approximately **134 ms**, of which only ≈ 2.31 ms is the actual
neural-network inference; the remainder is dominated by the UART payload
transmission. This is well below the typical human voluntary motor reaction
threshold (≈ 200 ms) [3], [73], so the BCI loop does not introduce a
perceptible latency relative to a directly elicited motor command.

---

## 7.4 EEG Acquisition Subsystem

### 7.4.1 Component

OpenBCI Cyton + Daisy biosensing board (16-channel configuration), provided
with a research-grade dry/wet EEG electrode harness referenced to the OpenBCI
ground/bias electrode pair [9].

### 7.4.2 EEG signal characteristics

Spontaneous EEG occupies the band from roughly 0.5 Hz (slow delta rhythms) to
approximately 100 Hz, with the discriminative motor-imagery (MI) information
concentrated in the µ (8–13 Hz) and β (13–30 Hz) sensorimotor rhythms over
the central scalp [3], [41], [73]. Typical scalp amplitudes are 10–100 µV
peak-to-peak, contaminated by electromyographic and ocular artefacts that can
exceed the EEG amplitude by an order of magnitude. The signal source impedance
at the skin–electrode interface is in the range of 1 kΩ to 100 kΩ depending on
preparation [3]. These properties motivate every downstream design decision:
the requirement for high-input-impedance buffering, low input-referred noise,
mains-suppressing filtering and high-resolution conversion.

### 7.4.3 Electrode placement and channel configuration

The implemented configuration uses the international 10-20 placement scheme
with the eight or sixteen recording electrodes centred over the sensorimotor
strip (C3, C4, Cz, FC3, FC4, CP3, CP4, FCz being a typical motor-imagery
subset) and the bias/ground electrode placed at AFz. This concentration over
the motor strip maximizes the signal-to-noise ratio of the µ/β rhythms that
DB-ATCNet exploits during MI classification [36], [73].

### 7.4.4 Why OpenBCI was selected

The OpenBCI Cyton/Daisy platform was selected over alternative biopotential
front-ends for four reasons that map directly to the project's design
constraints:

1. *Open hardware.* The full schematic, layout and firmware of the Cyton
   board are publicly documented [9], permitting the team to characterize
   noise paths and to electrically interface the analog output safely.
2. *Research-grade analog quality.* The Cyton uses an ADS1299 24-bit
   instrumentation ADC with input-referred noise specified below 1 µV RMS at
   sampling rates up to 16 kSPS [9], which exceeds the per-sample resolution
   requirements of the µV-scale rhythms targeted in this work.
3. *Flexible electrode harness.* The standard 16-channel daisy-chain
   configuration covers the entire sensorimotor strip with one
   medical-grade headset, eliminating the integration burden of a custom
   electrode array.
4. *Cost and availability.* In comparison with proprietary clinical
   EEG amplifiers (Brain Products, g.tec) the Cyton/Daisy provides
   research-comparable signal quality at a fraction of the cost, which is
   compatible with an academic capstone budget [54].

### 7.4.5 Data output mechanism

In the implemented system, the OpenBCI board is used as the physical
electrode and bias-network harness; the analog buffered electrode signal is
routed out of the Cyton expansion header to the discrete signal-conditioning
chain described in §7.5–7.6. This bypasses the on-board ADS1299 in favour of
the discrete TLV9061 + ADS1115 chain in order to keep the analog front-end
within the same low-voltage domain as the ESP32-S3 and to give the team
direct control over filter cutoff frequency, gain and ADC sampling rate. The
on-board USB and battery-powered digital data path of the Cyton remains
available as a future option for a fully wireless deployment.

---

## 7.5 Analog Front-End: TLV9061 Buffer

### 7.5.1 Component

Texas Instruments **TLV9061** — single, low-noise, rail-to-rail input/output
operational amplifier in a 5-pin SC-70 package, specified to operate from a
single supply between 1.8 V and 5.5 V with an input-referred voltage noise
density of approximately 10 nV/√Hz at 1 kHz.

### 7.5.2 Implemented configuration

The TLV9061 is implemented as a **non-inverting unity-gain voltage buffer**
between the OpenBCI electrode/expansion header and the ADS1115 ADC input, as
shown in **[Insert Figure 7-1, Block 2]**. The non-inverting input is driven
from the OpenBCI buffered electrode tap; the inverting input is tied directly
to the output, producing a closed-loop gain of exactly +1 V/V. The output
drives a series-1 kΩ resistor that, together with the 330 nF shunt capacitor
described in §7.6, forms the antialiasing filter that precedes the ADC.

### 7.5.3 Why TLV9061 was selected

Three properties of the TLV9061 are dominant for this design:

1. **Low input voltage noise (≈ 10 nV/√Hz).** For an EEG bandwidth of
   approximately 100 Hz the integrated input-referred noise is therefore on
   the order of 100 nV RMS, which is below the lowest EEG signal level of
   interest and one to two orders of magnitude below the dominant
   physiological noise sources [3].
2. **Rail-to-rail input/output range with single-supply operation.** Because
   the entire analog front-end is referenced to the same 3.3 V LDO that
   supplies the ADS1115's analog rail, a rail-to-rail op-amp avoids any
   need for split supplies or level translation.
3. **Low quiescent current (< 0.6 mA).** Battery-operated systems benefit
   from sub-milliampere active currents; with the buffer and ADC together
   drawing less than 1 mA the analog rail load is dominated by the OpenBCI
   board, not the discrete conditioning chain.

### 7.5.4 Closed-loop gain derivation

For the non-inverting configuration the closed-loop gain is

```
A_v = 1 + R_f / R_g
```

The implemented topology corresponds to R_f = 0 (direct output-to-inverting
short) and R_g = ∞ (open), yielding the unity-gain expression

```
A_v = 1 + 0 / ∞ = 1.
```

A unity-gain buffer was preferred over a configured-gain stage because the
desired ADC full-scale of ±2.048 V is significantly larger than the raw
electrode amplitude of ±100 µV; the additional headroom is exploited at the
ADS1115 stage by selecting an aggressive PGA gain (see §7.7) rather than by
amplifying inside the op-amp, which keeps the buffer fully linear and avoids
any saturation under electrode-pop transients.

### 7.5.5 Bandwidth and signal integrity

The TLV9061 has a unity-gain bandwidth of approximately 10 MHz; at the
project's signal bandwidth (< 100 Hz) the buffer is therefore operating
five decades below its bandwidth limit, so its small-signal transfer
function is essentially flat and linear across the entire EEG band. The
input capacitance is negligible compared with the source impedance of the
OpenBCI buffered output (< 1 kΩ), so the buffer does not load the
acquisition source.

---

## 7.6 Antialiasing RC Filter Analysis

### 7.6.1 Topology and component values

A passive first-order RC low-pass filter is implemented between the TLV9061
buffer output and the ADS1115 analog input. From the schematic
(**[Insert Figure 7-1, Block 2]**) the implemented values are
**R = 1 kΩ** in series with the buffer output and **C = 330 nF** shunting
the ADC node to analog ground.

### 7.6.2 Transfer function and cutoff frequency

The transfer function of a first-order RC low-pass section is

```
H(s) = 1 / (1 + s · R · C),
```

with a –3 dB cutoff angular frequency ω_c = 1 / (R·C). The –3 dB cutoff
frequency in hertz is therefore

```
f_c = 1 / (2 · π · R · C).
```

Substituting the implemented values:

```
f_c = 1 / (2 · π · 1 kΩ · 330 nF)
    = 1 / (2 · π · 3.3 × 10⁻⁴)
    ≈ 482 Hz.
```

### 7.6.3 Frequency response and EEG preservation

A –3 dB cutoff at 482 Hz preserves the entire physiologically relevant EEG
band (0.5 Hz to ≈ 100 Hz) with attenuation of less than 0.02 dB, while
attenuating the spectrum above 1 kHz by at least 12 dB/octave. The cutoff
deliberately sits well above the 250 Hz EEG sampling rate that the system
exposes externally so that the filter does not soften the upper bound of
the discriminative β band; the residual antialiasing margin is provided
inside the ADS1115 by its on-die digital decimation filter (§7.7) [78],
[81].

### 7.6.4 Why this cutoff was selected

A cutoff above the Nyquist limit of 125 Hz might appear redundant for a
250 Hz sample rate. The implemented value reflects three engineering
constraints:

1. *Mains-frequency margin.* A filter centred at the Nyquist limit (125 Hz)
   would have an asymptotic attenuation at 50/60 Hz that is essentially
   zero, defeating its purpose; placing the cutoff at ≈ 5 × the highest
   useful EEG frequency keeps the filter's role purely antialiasing and
   leaves mains rejection to the digital notch in firmware.
2. *Op-amp noise integration.* A narrower filter would integrate less
   wideband op-amp noise but at the cost of an additional pole that would
   produce a non-flat magnitude response in the µ/β band; the implemented
   cutoff yields a flat magnitude response over the band of interest with
   negligible noise penalty.
3. *Component availability.* Standard E96-series values of 1 kΩ and 330 nF
   are inexpensive and stable, and produce a frequency that is easy to
   document and reproduce in further units.

---

## 7.7 Analog-to-Digital Conversion: ADS1115

### 7.7.1 Component

Texas Instruments **ADS1115** — a 16-bit, four-channel, sigma-delta
successive-approximation ADC with an integrated programmable-gain amplifier
(PGA), oscillator and I²C interface, in a 10-pin VSSOP package.

### 7.7.2 Implemented configuration

In the implemented system the ADS1115 is configured as follows:

- **PGA gain:** ±2.048 V (`FSR = 0b001`).
- **Mode:** single-shot conversion, triggered from the ESP32-S3.
- **Data rate:** 250 SPS.
- **I²C address:** `0x48` (ADDR pin tied to ground).
- **Input multiplexer:** the buffered, filtered EEG signal from §7.5–§7.6 is
  routed to AIN0; AIN1 is grounded at the analog star point to provide a
  fully differential reading and reject common-mode pickup.

The ADS1115 shares the same I²C bus as the PCA9685 servo driver; the bus is
pulled up to the 3.3 V analog rail through 4.7 kΩ resistors.

### 7.7.3 LSB and effective voltage resolution

For a single-ended PGA gain of ±2.048 V the full-scale digital code maps to
±32 767, so the least-significant-bit voltage is

```
LSB = (2 × FSR) / 2^N
    = (2 × 2.048 V) / 2^16
    = 4.096 V / 65 536
    ≈ 62.5 µV.
```

Because the input is buffered at unity gain by the TLV9061, the LSB in
electrode-equivalent volts is also 62.5 µV. This is fine enough to resolve
the µV-scale rhythms after digital amplification in firmware (Q8.8
rescaling, §7.8.4) but coarse enough to keep quantization noise well below
the analog noise floor — the ADC therefore captures the analog signal
without dominating the noise budget.

### 7.7.4 Sampling architecture

The ADS1115 uses an oversampling sigma-delta architecture with on-chip
decimation to produce a 16-bit output at the configured data rate. Internal
oversampling provides an additional low-pass response with a stop-band
attenuation that further suppresses any spectral content above the
configured data rate, complementing the discrete RC filter of §7.6 [78].

### 7.7.5 Why ADS1115 was selected

The ADS1115 was selected over competing 12-bit and 16-bit ADCs for four
reasons:

1. *Sufficient resolution at low system cost.* The 62.5 µV LSB matches the
   amplitude scale of the buffered EEG without requiring an additional
   programmable-gain amplifier external to the ADC.
2. *Integrated PGA and reference.* The on-die PGA and 2.048 V reference
   reduce the part count and remove the need for an external precision
   voltage reference, simplifying board area and bill-of-materials.
3. *I²C interface compatibility.* The ESP32-S3 already implements I²C in
   hardware for the PCA9685; sharing a bus across the analog and actuator
   peripherals halves the GPIO consumption and removes any additional SPI
   wiring.
4. *Low quiescent current and small footprint.* Below 1 mA active
   consumption and a 10-pin VSSOP footprint, the ADS1115 fits within the
   wearable form-factor budget targeted by the LiPo-powered system.

---

## 7.8 ESP32-S3 Microcontroller Stage

### 7.8.1 Component

Espressif **ESP32-S3** dual-core 32-bit Xtensa LX7 microcontroller
development board, clocked at up to 240 MHz with integrated Wi-Fi and
Bluetooth Low Energy radios and 512 KiB on-die SRAM. The device is mounted
on a generic ESP32-S3-DevKitC-style development board with the USB Serial
adapter providing both power for development and firmware upload.

### 7.8.2 Role in the system

The ESP32-S3 is the conductor of the analog-domain side of the system. It
performs four distinct duties:

1. *Polling and reading the ADS1115* over I²C at the configured 250 SPS
   sample rate.
2. *Window construction*: assembling 600 contiguous samples × 5 channels of
   16-bit Q8.8 data — the input dimensionality expected by DB-ATCNet [36] —
   into a 6 000-byte little-endian frame in on-chip SRAM.
3. *Transmitting the frame* over hardware UART2 to the Zynq UltraScale+
   Programmable System UART1 at 460 800 8N1 with no flow control.
4. *Receiving the inference result* (one byte: `0x00` for the hand-grip
   motor-imagery class or `0x01` for the ankle motor-imagery class) and
   commanding the PCA9685 to drive the appropriate servo, with all
   safety-of-operation logic (rate limiting, watchdog, majority voting)
   evaluated locally in firmware.

The ESP32-S3 implements the safety state machine — `BOOT`, `HOMING`,
`IDLE`, `RUNNING`, `FAULTING`, `FAULT` — that protects the user from
classification glitches, communication loss and out-of-range commands.
A representative excerpt of the embedded firmware is shown below.

```cpp
// ESP32-S3 UART2 ↔ Zynq PS UART1 link (excerpt from db_atcnet_esp32.ino)
constexpr long  UART2_BAUD   = 460800;
constexpr int   UART2_RX_PIN = 18;   // Zynq PS UART1 TX (PL pin AL17 / CP2108 ch.2)
constexpr int   UART2_TX_PIN = 17;   // Zynq PS UART1 RX (PL pin AH17 / CP2108 ch.2)
constexpr int   I2C_SDA_PIN  = 8;    // shared bus to PCA9685 + ADS1115
constexpr int   I2C_SCL_PIN  = 9;
constexpr uint32_t I2C_CLK   = 400000;   // Fast-mode I2C

void setup() {
    Serial2.begin(UART2_BAUD, SERIAL_8N1, UART2_RX_PIN, UART2_TX_PIN);
    Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN);
    Wire.setClock(I2C_CLK);
    pca9685.begin();
    pca9685.setPWMFreq(SERVO_FREQ_HZ);
    state_machine.transition(STATE_HOMING);
}
```

### 7.8.3 I²C transactions to ADS1115 and PCA9685

The ESP32-S3 hosts a single I²C bus shared between the ADS1115 (at slave
address `0x48`) and the PCA9685 (at slave address `0x40`). The bus operates
in fast mode (400 kHz) with 4.7 kΩ pull-up resistors to 3.3 V. Bus collisions
are avoided in firmware by issuing all ADS1115 reads as blocking transactions
in the sample interrupt service routine, and all PCA9685 writes as
non-blocking transactions in the main loop; the two never coexist because
the ADC transaction completes in less than 100 µs.

### 7.8.4 Data formatting

The 16-bit signed ADS1115 output is rescaled in firmware into the
**Q8.8 fixed-point format** used by the FPGA pipeline. This conversion is
performed as

```cpp
int16_t q88 = (int16_t)((adc_value * Q88_SCALE) >> ADS_SHIFT);
```

where `Q88_SCALE` and `ADS_SHIFT` are calibration constants chosen so that
the dynamic range of physiologically relevant EEG occupies the most
significant byte of the Q8.8 representation. The Q8.8 choice mirrors the
internal data path of DB-ATCNet (see Chapter 8, §8.20) so that no
re-scaling occurs at the PS/PL boundary.

### 7.8.5 UART packet structure and synchronization

A single inference window consists of 3 000 samples × 2 bytes = 6 000 bytes
sent back-to-back without framing bytes. The receiver re-synchronizes on
the timeout of the receive idle line, taking advantage of the 460 800 baud
serial-line idle being unambiguously distinguishable from the 130 ms
back-to-back transmission of a full frame. After the FPGA finishes
inference (≈ 2.31 ms), it transmits a single byte back; the ESP32-S3
treats any byte value other than `0x00` or `0x01` as a fault condition
and steers the safety state machine to `FAULTING`, returning the servos
to their resting angles.

### 7.8.6 Why ESP32-S3 was selected

The ESP32-S3 was selected over an STM32 or Arduino Uno class
microcontroller because it offered:

1. *Sufficient SRAM for a full 6 000-byte window* (512 KiB total) without
   external memory, simplifying the layout and PCB area.
2. *Dual hardware UARTs and hardware I²C*, decoupling the ADC, PCA9685 and
   FPGA links onto independent peripheral channels.
3. *Integrated USB-Serial for development* and a free FreeRTOS-compatible
   environment, accelerating firmware iteration during the project.
4. *Wireless capability*, leaving open a future path to remote
   telemetry without additional radio hardware.
5. *Industry-grade safety primitives*, including a hardware watchdog and
   brownout detector that the safety state machine relies on.

---

## 7.9 Operational Modes

### 7.9.1 Real-time live EEG mode

In the real-time mode the implemented data path is

```
OpenBCI Cyton/Daisy  →  TLV9061 buffer  →  RC LPF
                  →  ADS1115 ADC  →  ESP32-S3
                  →  PS UART1 of Zynq UltraScale+
                  →  PL DB-ATCNet accelerator
                  →  PS UART1 return  →  ESP32-S3
                  →  PCA9685  →  Servo motors.
```

This mode supports online motor-imagery decoding of a subject who is
wearing the OpenBCI headset. The ESP32-S3 polls the ADS1115 at 250 SPS,
streams a 3 s analysis window (600 samples × 5 channels) every 250 ms (50%
overlap) and consumes the resulting class bytes to drive the servos.

### 7.9.2 Stored data mode

In the stored-data mode the implemented data path is

```
SD card (BCI Competition IV-2a recording)
       →  ESP32-S3 file system  →  PS UART1
       →  PL DB-ATCNet accelerator
       →  PS UART1 return  →  PCA9685  →  Servos.
```

Stored-data mode replays previously acquired EEG sessions to validate the
inference pipeline and the actuation safety logic deterministically, without
requiring a subject to be electrically connected. The publicly available
BCI Competition IV-2a dataset [30], [31] is the reference replay source,
which permits comparison against published baselines [10], [15], [36] and
makes the system independently reproducible. Both modes share every
post-ESP32 hardware block, including the FPGA inference engine and the
PCA9685–servo chain, which is what makes the architecture useful as a
testbed for additional EEG datasets.

---

## 7.10 FPGA Processing Platform

### 7.10.1 Component

The implemented FPGA host is the **AMD/Xilinx Zynq UltraScale+ MPSoC,
device XCZU7EV-2FFVC1156**, mounted on the **ZCU106 Evaluation Board**.
A photograph of the ZCU106 with numbered component callouts is reproduced
in **[Insert Figure 7-2 here — Photograph of the ZCU106 evaluation board
with numbered component callouts, after UG1244 Fig. 2-1]**. Detailed
discussion of every numbered component is deferred to Chapter 8, §8.2.

### 7.10.2 Architecture summary

The Zynq UltraScale+ device couples two distinct processing fabrics on the
same die:

- *Processing System (PS)*: a quad-core 64-bit ARM Cortex-A53 application
  processor with FPU/NEON SIMD extensions, a dual-core ARM Cortex-R5
  real-time processor, a Mali-400 MP2 GPU, 256 KiB of on-chip memory, a
  hard DDR4 controller, and a complete peripheral set including two UARTs,
  two I²C controllers, USB 3.0, Gigabit Ethernet and SD/eMMC.
- *Programmable Logic (PL)*: the equivalent of an UltraScale+ FPGA with
  230 400 LUTs, 460 800 flip-flops, 312 36-Kb block RAM tiles, and 1 728
  DSP48E2 slices. The PL communicates with the PS through dedicated
  cache-coherent ACE/ACP and cache-incoherent AXI4 ports.

The system-level block diagram of the Zynq UltraScale+ MPSoC is reproduced
in **[Insert Figure 7-3 here — Zynq UltraScale+ MPSoC Top-Level Block
Diagram, after UG1085/UG1244 Fig. 3-1 (`thesis/archticture`)]**.

### 7.10.3 Why ZCU106 / XCZU7EV was selected

The full DB-ATCNet accelerator requires 99.94 % of the 1 728 DSP slices,
80 BRAM tiles and approximately 85 % of the LUT budget at the chosen
operating frequency. The ZCU106 provides:

1. *Adequate DSP density.* Lower-end Zynq-7000 series devices (e.g. the
   Zynq-7030 with 400 DSPs) cannot host the full inference engine; only
   the Zynq UltraScale+ tier of the family provides the DSP density
   required for parallel Q8.8 multiply-accumulate operations.
2. *A high-bandwidth PS-to-PL path.* The HP0_FPD AXI port provides a
   128-bit cache-incoherent path that AXI-DMA uses to stream the 6 000-byte
   EEG window into the PL pipeline without involving the Cortex-A53 for
   each beat.
3. *Industry-standard tooling support.* The board is supported as a
   first-class target in Vivado Design Suite and Vitis Unified IDE
   without custom board files, which is critical for an academic
   capstone with a finite tool-debug budget.

Alternative platforms considered but not selected included the
PYNQ-Z2/Z1 (insufficient DSPs), the ZCU102 (over-provisioned and out of
budget) and the Alveo U50 (PCIe host required, not battery-friendly).

---

## 7.11 FPGA Interface Analysis

### 7.11.1 Processing System role

The PS is configured to host a bare-metal standalone application running on
Cortex-A53 core 0. The application is responsible for:

1. Initializing the AXI-DMA engine in MM2S (memory-mapped to stream) mode.
2. Configuring the PS UART1 controller (routed through EMIO to PL pins
   AL17 and AH17 on the ZCU106) at 460 800 8N1.
3. Polling the PS UART1 RX line, copying the 6 000-byte EEG window into a
   cache-line-aligned DDR4 buffer and flushing the data cache for the
   buffer range.
4. Programming the AXI-DMA to push the buffer into the PL inference
   engine's streaming input port.
5. Polling the AXI-Lite `STATUS_REG` of the `db_atcnet_axi` IP until
   the `done` bit is asserted, reading the `CLASS_REG` register and
   transmitting the single class byte back over PS UART1 to the ESP32-S3.

A representative excerpt of the PS host application is shown below.

```c
/* Zynq PS bare-metal host application (excerpt from main.c). */
#define ESP_UART_BASEADDR  XPAR_XUARTPS_1_BASEADDR     /* PS UART1 */
#define DMA_BASEADDR       XPAR_XAXIDMA_0_BASEADDR

XUartPs_Config *cfg = XUartPs_LookupConfig(ESP_UART_BASEADDR);
XUartPs_CfgInitialize(&esp_uart, cfg, cfg->BaseAddress);
XUartPs_SetBaudRate(&esp_uart, 460800);
XUartPs_SetOperMode(&esp_uart, XUARTPS_OPER_MODE_NORMAL);

Xil_DCacheFlushRange((INTPTR)eeg_buf, WIN_BYTES);
XAxiDma_SimpleTransfer(&dma, (UINTPTR)eeg_buf, WIN_BYTES,
                       XAXIDMA_DMA_TO_DEVICE);
```

### 7.11.2 Programmable Logic role

The PL implements the entire DB-ATCNet inference engine as a fixed-function
dataflow accelerator [36], [86], [87]. Its top-level wrapper, `db_atcnet_axi`,
exposes three interfaces to the rest of the system:

1. *AXI4-Stream slave* (`s_axis`): receives the 6 000-byte Q8.8 EEG window
   from the AXI-DMA engine, one 32-bit word per beat at the system clock.
2. *AXI4-Lite slave* (`s_axi`): exposes the `STATUS_REG` (offset `0xF000`)
   and the `CLASS_REG` (offset `0xF004`) for the PS to poll.
3. *Interrupt request* (`irq_done`): pulses when the classifier completes
   an inference; not used in the implemented build because the PS polls,
   but available for a future interrupt-driven host.

The pipeline runs on `pl_clk0`, which is set by the PSU to 50 MHz. The
accelerator design and the rationale for choosing 50 MHz over the
initially planned 100 MHz are detailed in Chapter 8.

### 7.11.3 UART communication

The PS exposes UART1 through EMIO and routes it to PL pins AL17 (`TX`)
and AH17 (`RX`), which on the ZCU106 are wired to the on-board
SiliconLabs CP2108 quad USB-UART bridge. The CP2108 makes this PL UART
visible on the host laptop as `/dev/ttyUSB1`. The PCB pin assignment is
enforced by the constraint file:

```tcl
# constraints/uart1_emio_zcu106.xdc — PS UART1 → PL → CP2108 channel 2
set_property PACKAGE_PIN AL17     [get_ports UART_1_0_txd]
set_property PACKAGE_PIN AH17     [get_ports UART_1_0_rxd]
set_property IOSTANDARD LVCMOS12  [get_ports UART_1_0_txd]
set_property IOSTANDARD LVCMOS12  [get_ports UART_1_0_rxd]
```

---

## 7.12 PWM Generation and Servo Interface (PCA9685)

### 7.12.1 Component

NXP **PCA9685** — a 16-channel, 12-bit-resolution I²C-controlled PWM
generator with an integrated 25 MHz internal oscillator and an
output-enable pin, in a 28-pin TSSOP package.

### 7.12.2 Implemented configuration

The PCA9685 is implemented at I²C address `0x40` on the ESP32-S3's
shared I²C bus. The PWM frequency is configured to 50 Hz (corresponding
to a 20 ms period, which is the standard pulse-train period for analog
hobby servos) using the on-die prescaler:

```
PRESCALE = round(25 MHz / (4096 × f_pwm)) − 1
        = round(25 × 10⁶ / (4096 × 50)) − 1 ≈ 121.
```

Only channels 0 and 1 are populated; the remaining channels are
disabled by the chip default register state. Each channel sources up to
25 mA from the internal driver but ultimately delivers servo current
from the dedicated 6 V buck-converter rail (`V+`).

### 7.12.3 Operating principle

Each output channel has two 12-bit registers — the `ON` count and the
`OFF` count — that specify when, within the 4 096-step period defined
by the prescaler, the channel transitions high and low. The output is
therefore a digital PWM whose duty cycle has 12-bit resolution. A
typical hobby servo expects a 1 ms pulse for one end of travel and a
2 ms pulse for the other end; at 50 Hz a 1 ms pulse corresponds to a
`OFF = 4096 / 20 = 204.8` count, and a 2 ms pulse to `OFF = 409.6`,
giving roughly 200 counts of usable resolution across the ±60°
mechanical range typical of an SG90.

### 7.12.4 Servo control methodology

The ESP32-S3 firmware converts each class byte received from the FPGA
into a target angle and writes the corresponding PCA9685 register value
through the `Adafruit_PWMServoDriver` library. Two safety mechanisms
operate inside the firmware before the register write reaches the
PCA9685:

- *Per-servo angle clamps* prevent the firmware from commanding angles
  outside the mechanical safe range of the specific actuator.
- *Per-servo rate limiter* limits the maximum commanded angular velocity,
  preventing destructive accelerations under classification glitches.

### 7.12.5 Why PCA9685 was selected

1. *Off-loading PWM generation* from the ESP32-S3 frees the
   microcontroller for I²C/UART traffic and safety logic, eliminating
   timing pressure on the main CPU.
2. *Sixteen channels* leave headroom for additional joints (a future
   exoskeleton extension).
3. *I²C interface compatibility* with the existing ADS1115 bus.
4. *Independent V+ rail* for the actuators, isolating the noisy servo
   current path from the logic supply (§7.14).

---

## 7.13 Actuation System

### 7.13.1 Components

Two analog hobby-grade servomotors are implemented as the system's
end-effectors:

- *Servo #1 (ankle).* Drives a mechanical link that produces ankle
  dorsiflexion/plantarflexion. Targeted at applications such as
  drop-foot rehabilitation [16], [19].
- *Servo #2 (hand-finger gripper).* Drives a tendon-routed gripper that
  opens and closes the user's fingers. Targeted at hand-grasp
  rehabilitation [17], [23].

Each servo is connected to one PCA9685 channel: `CH0 → ankle`,
`CH1 → hand-finger gripper`. Each channel header carries the PWM
signal, the `V+` servo supply (6 V) and a shared ground.

### 7.13.2 Functional role

The actuators are the user-facing output of the BCI loop. By design,
the binary classifier emits one of two motor-imagery intent classes
(`0x00` → hand grip, `0x01` → ankle motion); the corresponding servo
executes a clamped, rate-limited motion toward the commanded angle.
The mechanical range of each actuator is firmware-clamped to ±60° to
prevent damage in the event of an inference glitch [16], [17].

### 7.13.3 PWM requirements

Both servos are standard 50 Hz, 1–2 ms pulse-width analog devices. The
PCA9685's 12-bit resolution provides better than 0.3° quantization,
which is well below the mechanical backlash of typical hobby gearing,
so quantization is not the dominant source of mechanical error.

---

## 7.14 Protection Circuit Analysis

The schematic in **[Insert Figure 7-1]** shows three categories of
protection components placed around each servo output and around the
analog inputs.

### 7.14.1 Series resistors

A small-value (≈ 100 Ω) series resistor is placed inline with each PWM
signal between the PCA9685 output and the servo header. This resistor
serves two purposes: it limits short-circuit current to a safe value
should the servo signal pin be shorted to ground, and it forms a
low-pass network with the parasitic capacitance of the servo input
that suppresses transient ringing on the PWM edges.

### 7.14.2 Pull-down resistors

A 10 kΩ pull-down to ground is placed on each PWM signal between the
PCA9685 and the series resistor. The pull-down guarantees a defined
low state on the servo signal during the brief window between
power-on and the first PCA9685 register write — a critical safety
property because an undriven CMOS input near 1.5 V can result in the
servo executing an arbitrary motion at boot.

### 7.14.3 Zener clamps

A 5.5 V Zener diode is placed across each servo's V+ rail to ground.
The Zener clamps any inductive kick from the servo motor at a safe
threshold, protecting the buck-converter output from the back-EMF
that occurs when the servo decelerates abruptly under load.

### 7.14.4 ESD and reverse-bias diodes

A standard small-signal ESD diode is placed across each analog input
that is exposed at a connector pin (the OpenBCI expansion header
inputs in particular) clamping any ESD event to the 3.3 V supply and
ground. Schottky reverse-bias diodes are placed across each buck
converter output to protect against transient reverse currents during
shutdown.

### 7.14.5 Summary of protection rationale

The protection components are sized to be invisible to the system in
normal operation — they neither attenuate the signal nor draw
quiescent current — but to act decisively under fault conditions.
This conservative philosophy mirrors recommended practice for
clinical-environment electronics where occasional human electrical
contact is expected [11].

---

## 7.15 Power System Engineering Analysis

### 7.15.1 Topology

The implemented power tree is depicted in **[Insert Figure 7-1, Block
8]**. From source to load:

1. **Battery.** A 3-cell lithium-polymer (LiPo) pack with a nominal
   terminal voltage of 11.1 V and a capacity of 2 200 mAh.
2. **Protection fuse.** An 8 A automotive-style blade fuse between the
   battery and the system bus. Sized to protect the wiring and the
   buck converters against a worst-case stall current of the actuators
   plus the FPGA's peak inrush.
3. **Buck Converter #1.** A switch-mode step-down regulator that
   produces 6 V / 6 A for the actuator rail (PCA9685 `V+` and both
   servos).
4. **Buck Converter #2.** A switch-mode step-down regulator that
   produces 5 V / 3 A for the digital logic rail (ZCU106 5 V input,
   ESP32-S3 USB-equivalent 5 V).
5. **Low-noise LDO.** A 3.3 V / 1 A low-noise linear-dropout regulator
   that produces the analog rail from the 5 V buck output and supplies
   the TLV9061, the ADS1115 analog domain and the OpenBCI buffered
   electrode output.

Bulk and decoupling capacitance at each node is sized as shown in the
schematic (input/output 25 V electrolytic caps on each buck, 10 µF
ceramic on each rail at the IC, and 100 nF ceramic at every active
device's supply pin).

### 7.15.2 Battery sizing and runtime estimate

The dominant load on the battery is the ZCU106 board itself, which in
its present configuration draws approximately 1.2 A at 12 V under
worst-case inference activity. The actuator rail draws approximately
1.0 A at 6 V under maximum motion. Allowing for the buck conversion
efficiencies (≈ 90 %), the steady-state current drawn from the LiPo
pack is

```
I_pack ≈ (1.2 A × 12 V + 1.0 A × 6 V) / (0.90 × 11.1 V)
      ≈ (14.4 + 6.0) / 9.99
      ≈ 2.04 A.
```

At 2 200 mAh capacity this yields an expected operating runtime of

```
T_run = 2200 mAh / 2040 mA ≈ 1.08 h
      ≈ 65 minutes.
```

This is sufficient for a single rehabilitation session [16], [22]
without recharging.

### 7.15.3 Why dual buck converters were used

A single buck rail would have been simpler but would have forced the
actuator and logic rails to share a single regulator. Sharing the rail
is undesirable because servo stall currents — short, large
disturbances — propagate as supply ripple onto the logic rail and
glitch the ESP32-S3 brown-out detector. Splitting the rails into
*Buck #1 (actuator)* and *Buck #2 (logic)* isolates the disturbance to
the actuator side; the logic supply sees only the smooth, slowly
varying load of the digital and analog subsystems.

### 7.15.4 Why a low-noise LDO was added

Switch-mode buck converters produce supply ripple at their switching
frequency (typically 500 kHz – 2 MHz) that, while invisible to the
digital logic, would couple directly into the µV-scale analog front-
end. The 3.3 V LDO downstream of the 5 V buck provides at least
60 dB of switching-noise rejection at the buck's fundamental frequency
and an output noise density below 10 µV RMS, which is safely below
the ADS1115's quantization floor.

### 7.15.5 Why star grounding was implemented

A single shared ground plane would permit return-current loops between
the actuator domain (high-current, fast transients), the digital
domain (medium-current, sharp edges) and the analog domain (low-
current, microvolt sensitivity). The implemented topology splits these
into AGND, DGND and a power-ground plane that are joined at exactly
one star point near the battery negative terminal. This prevents
ground-loop EMI from coupling actuator transients into the EEG
front-end and is essential to recovering the µV-scale signal of
interest [11], [54].

---

## 7.16 Grounding Analysis

The implemented system uses a tri-domain grounding scheme:

- **AGND (analog ground)** — return path for the OpenBCI buffered
  electrode output, the TLV9061 buffer, the RC filter, the ADS1115
  analog domain and the LDO output ground.
- **DGND (digital ground)** — return path for the ESP32-S3, the
  PCA9685 logic supply, the ZCU106 logic ground (where exposed) and
  the I²C pull-up references.
- **Power ground** — return path for both buck-converter outputs,
  for the servo current and for the battery negative terminal.

The three planes are joined at a single point — the *star point* —
located physically adjacent to the battery negative terminal as shown
on the schematic. Between the star point and each load there is a
single, unbroken plane of the corresponding domain.

This topology provides two engineering benefits:

1. *Return currents are confined to their own plane* until the star
   point, eliminating mutual coupling between domains that would
   otherwise share return paths.
2. *EMI radiation is suppressed* because every signal trace runs
   directly above its return plane, minimizing the loop area and
   therefore the differential-mode and common-mode radiation.

These two properties together permit the recovery of the µV-scale
EEG signal in the presence of high-current servo transients on the
same board.

---

## 7.17 Engineering Calculations

The following engineering calculations summarize the quantitative
design choices made in §7.4–§7.15. All values are derived directly
from the implemented schematic and the datasheets of the implemented
components.

### 7.17.1 Antialiasing cutoff frequency

```
f_c = 1 / (2 · π · R · C)
    = 1 / (2 · π · 1 kΩ · 330 nF)
    ≈ 482 Hz.
```

### 7.17.2 ADC voltage resolution

```
LSB = (2 · FSR) / 2^N
    = (2 · 2.048 V) / 65 536
    ≈ 62.5 µV.
```

### 7.17.3 PCA9685 prescaler

```
PRESCALE = round(25 MHz / (4096 · f_pwm)) − 1
        = round(25 × 10⁶ / (4096 · 50)) − 1 ≈ 121.
```

### 7.17.4 Battery runtime

```
I_pack ≈ (P_FPGA + P_servo) / (η · V_pack)
      ≈ (14.4 W + 6.0 W) / (0.90 · 11.1 V)
      ≈ 2.04 A.
T_run = 2200 mAh / 2040 mA
      ≈ 65 min.
```

### 7.17.5 Inference latency

Based on the 50 MHz `pl_clk0` and the cycle count reported by the
end-to-end FPGA simulation (Chapter 8, §8.16):

```
T_inf = N_cyc / f_clk
      = 115 453 / 60 × 10⁶
      ≈ 2.31 ms.
```

### 7.17.6 UART transmission time

For a 6 000-byte window over a 460 800 baud 8N1 link (1 start + 8
data + 1 stop = 10 bit-times per byte):

```
T_uart = 6000 · 10 / 460 800
       ≈ 130 ms.
```

---

## 7.18 Hardware Component List (Bill of Materials)

**Table 7-2: Bill of materials of the implemented BCI motion-control
system.**

| # | Subsystem | Designator | Part | Vendor / family | Notes |
|---|---|---|---|---|---|
| 1 | EEG acquisition | U1 | OpenBCI Cyton + Daisy biosensing board (16 ch) | OpenBCI | scalp electrodes, expansion header [9] |
| 2 | Analog buffer | U2 | TLV9061 single op-amp, SC-70 | Texas Instruments | unity-gain non-inverting |
| 3 | Antialiasing | R1, C1 | 1 kΩ 0603, 330 nF X7R 0603 | generic E96 | f_c ≈ 482 Hz |
| 4 | ADC | U3 | ADS1115 16-bit ΣΔ ADC, VSSOP-10 | Texas Instruments | I²C addr 0x48, PGA ±2.048 V |
| 5 | Microcontroller | U4 | ESP32-S3-WROOM-1 (DevKitC) | Espressif | dual-core LX7 @ 240 MHz |
| 6 | FPGA SoC | U5 | XCZU7EV-2FFVC1156 (ZCU106) | AMD/Xilinx | Zynq UltraScale+ MPSoC |
| 7 | PWM driver | U6 | PCA9685 16-ch 12-bit PWM, TSSOP-28 | NXP | I²C addr 0x40 |
| 8 | Servo 1 (ankle) | M1 | analog hobby servo, 50 Hz | generic | PWM 1–2 ms |
| 9 | Servo 2 (hand) | M2 | analog hobby servo, 50 Hz | generic | PWM 1–2 ms |
| 10 | Battery | BT1 | LiPo 3S 11.1 V, 2200 mAh | generic | 30C discharge rating |
| 11 | Fuse | F1 | 8 A automotive blade fuse | generic | between battery and bus |
| 12 | Buck #1 (actuator) | U7 | 6 V / 6 A buck module | generic | inputs ≤ 25 V |
| 13 | Buck #2 (logic) | U8 | 5 V / 3 A buck module | generic | inputs ≤ 16 V |
| 14 | LDO (analog) | U9 | 3.3 V / 1 A low-noise LDO | generic (e.g. AP2114) | 60 dB PSRR at 1 kHz |
| 15 | Bulk caps | C2…C6 | 25 V / 16 V electrolytics | generic | input/output of bucks |
| 16 | Decoupling | C7… | 100 nF X7R 0603 ceramics | generic | per supply pin |
| 17 | Protection | D1…D2 | 5.5 V Zener clamps | generic | one per servo V+ |
| 18 | Pull-downs | R2…R3 | 10 kΩ 0603 | generic | one per PWM signal |
| 19 | I²C pull-ups | R4, R5 | 4.7 kΩ 0603 | generic | 3V3 rail |
| 20 | Connectors | J1…J5 | 0.1″ headers, JST-XH | generic | electrode, ESP32-FPGA, servos |
| 21 | Status LEDs | DS1, DS2 | 0603 green LEDs | LUMEX or equiv. | heartbeat, fault |

---

## 7.19 Circuit Integration and Data Flow

This subsection traces the complete signal flow from the cortex to the
mechanical end-effector, providing the integrated view required for
reproducing the hardware without referring to the schematic.

1. **Electrodes** placed at the sensorimotor-strip locations of the
   international 10-20 system pick up the µV-scale EEG signal and
   feed the OpenBCI Cyton/Daisy headset.
2. **OpenBCI Cyton/Daisy** buffers the electrode signals and exposes
   them at its expansion header. In the implemented system this
   buffered analog output is the source for the discrete chain.
3. **TLV9061** unity-gain buffer (3.3 V supply, AGND return) presents
   an effectively infinite input impedance to the OpenBCI output and
   a low output impedance to the antialiasing filter.
4. **RC low-pass filter** (R = 1 kΩ, C = 330 nF, f_c ≈ 482 Hz)
   band-limits the buffered EEG to the spectrum that the ADS1115's
   sigma-delta filter can sample without aliasing.
5. **ADS1115** sampled at 250 SPS produces a 16-bit Q15 signed code
   per channel that the ESP32-S3 reads over I²C at 400 kHz.
6. **ESP32-S3** rescales the ADC code to Q8.8 fixed-point and
   accumulates a 600-sample × 5-channel window in on-chip SRAM. Every
   3 s a new 6 000-byte window is dispatched to the FPGA.
7. **PS UART1 of Zynq UltraScale+**, routed through PL pins AL17/AH17
   on the ZCU106 to the on-board CP2108 USB-UART bridge, delivers the
   6 000-byte window to the PS bare-metal application.
8. **PS bare-metal application** copies the window to a cache-line-
   aligned DDR4 buffer, flushes the data cache and programs the
   AXI-DMA to push the buffer into the PL DB-ATCNet accelerator.
9. **PL DB-ATCNet accelerator** consumes the streamed window
   deterministically, performs the full inference in ≈ 2.31 ms and
   raises the `done` bit in `STATUS_REG` along with the class result
   in `CLASS_REG`.
10. **PS UART1 return** transmits the single class byte back to the
    ESP32-S3.
11. **ESP32-S3 safety state machine** validates the class byte,
    clamps and rate-limits the resulting servo angle command and
    writes the corresponding `OFF` count to the PCA9685 over I²C.
12. **PCA9685** generates the corresponding 50 Hz PWM waveform on
    channel 0 (ankle) or channel 1 (hand-finger gripper).
13. **Servo motor** executes a clamped, rate-limited motion to the
    commanded angle, completing the BCI motor-imagery control loop.

The same physical chain is reused in stored-data mode by replacing
step 1–6 with an SD-card replay path inside the ESP32-S3; from step 7
onward the data path is bit-identical. This architectural property is
what makes the system suitable both for online clinical evaluation and
for repeatable offline validation against published baselines.

---

*Chapter 7 ends. Chapter 8 (FPGA Deployment and Hardware Acceleration)
continues the technical narrative on the FPGA side of the partition.*
