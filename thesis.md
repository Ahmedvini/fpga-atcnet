# Thesis Writing Task

You are an expert academic thesis writer specializing in:

- Embedded Systems
- FPGA Design
- SystemVerilog-Based Digital Design
- Artificial Intelligence
- Biomedical Signal Processing
- Brain-Computer Interfaces (BCI)
- Rehabilitation Engineering

---

# Project Information

**Project Title**

> Design and Development of Brain Computer Interface for Assistive Motion Control Rehabilitation and Mobility Applications

This is an undergraduate graduation project.

The thesis follows **IEEE citation style**.

---

# Available Resources

A directory named **thesis/** contains all project materials.

You must thoroughly inspect the entire directory before writing.

The directory may contain:

- Previous thesis chapters
- References list
- Figures and diagrams
- Hardware architecture diagrams
- Circuit diagrams
- FPGA deployment documentation
- Vivado projects
- Vitis projects
- Source code
- SystemVerilog files
- Experimental results
- Performance reports
- Resource utilization reports
- Timing reports
- Power reports
- Tables
- Screenshots
- Images
- Supporting documents

You must use these files as the primary source of information.

---

# Additional FPGA Documentation

The thesis directory also contains a PDF that includes:

1. A real photograph of the ZCU104 FPGA board.
2. Numbered labels placed on the FPGA board image.
3. A corresponding table explaining each numbered component.

You must thoroughly analyze this PDF and use it as an official source when writing Chapter 8.

---

# Important Rules

1. Do NOT rewrite previous chapters.
2. Write only Chapter 7 and Chapter 8.
3. The directory contains an old FPGA deployment chapter.
4. Treat the old FPGA deployment chapter as a baseline reference.
5. Do NOT simply copy it.
6. Refine the writing quality where necessary.
7. Preserve all technically correct content.
8. Extend it using all final project updates and implementations.
9. Maintain IEEE in-text citations using the provided references.
10. Reference all available figures.
11. If a figure is missing, insert a placeholder:

```text
[Insert Figure X.X here – Description]
```

12. Write in formal undergraduate thesis style.
13. Produce highly detailed technical content.
14. Explain engineering decisions and design tradeoffs.
15. Explain implementation details.
16. Explain testing methodology.
17. Include equations where appropriate.
18. Include code snippets where useful.
19. Avoid generic textbook explanations.
20. Every section must be based on actual project materials.
21. The output must be ready to paste directly into Microsoft Word.
22. Keep formatting simple and copy-friendly.
23. Use proper heading hierarchy.
24. If information is missing, infer only when strongly supported by available project documents.
25. Do not invent experimental results.
26. Do not invent performance metrics.
27. Clearly indicate any assumptions.

---

# IMPORTANT WRITING PHILOSOPHY

When writing Chapter 7 and Chapter 8, prioritize documentation of the actual implemented system over textbook explanations.

The thesis should read as an engineering report of what was built, tested, integrated, validated, and deployed.

Every major section should reference actual project files, figures, source code, hardware diagrams, reports, measurements, and implementation artifacts found in the thesis directory.

Avoid unnecessary theoretical discussions unless they directly support understanding the implemented system.

---

# CHAPTER 7

# Hardware Design and Circuit Implementation

Write a complete and highly detailed chapter describing the final hardware implementation.

Use the circuit architecture and supporting figures from the thesis directory.

---

## System Hardware Overview

Begin with a high-level overview of the complete hardware architecture.

Introduce:

- EEG acquisition subsystem
- Signal conditioning subsystem
- Data acquisition subsystem
- Communication subsystem
- FPGA processing subsystem
- Servo control subsystem
- Power subsystem

Include a figure reference to the overall hardware architecture.

---

## Deep Circuit-Level Analysis

Chapter 7 must not be limited to a system overview.

Perform a detailed engineering analysis of the actual circuit.

Treat the chapter as a hardware design chapter rather than a component description chapter.

For every subsystem explain:

- Why the component was selected
- How it works internally
- Why it is connected in the shown configuration
- Electrical design considerations
- Advantages and limitations
- Design tradeoffs

---

## Signal Path Analysis

Trace the EEG signal step-by-step from the electrodes to the final servo output.

For each stage explain:

- Input signal characteristics
- Output signal characteristics
- Voltage levels
- Data format
- Noise considerations
- Latency introduced

The explanation should follow the exact signal path through the circuit.

---

## EEG Acquisition System

### Component

OpenBCI Cyton/Daisy Headset

Describe:

- EEG signal acquisition
- Electrode placement concepts
- Channel configuration
- Data output mechanism
- Signal characteristics
- Sampling considerations
- Signal quality considerations
- Advantages of OpenBCI

Explain why this platform was selected.

---

## Analog Front-End Design

### Components

- TLV9061 Low Noise Operational Amplifier
- RC Filter Network

Provide circuit-level analysis of:

- TLV9061 configuration
- Input and output behavior
- Gain characteristics
- Noise performance
- Bandwidth considerations
- Signal integrity

Explain exactly why TLV9061 was selected.

If resistor values indicate gain configuration, derive the gain mathematically.

---

## RC Filter Analysis

Analyze the RC network in detail.

Include:

- Transfer function
- Cutoff frequency derivation
- Frequency response
- EEG frequency preservation
- Noise attenuation

Use actual component values from the schematic.

Include:

\[
f_c=\frac{1}{2\pi RC}
\]

Discuss why the selected cutoff frequency is suitable for EEG signals.

---

## Analog-to-Digital Conversion Stage

### Component

ADS1115 (16-Bit ADC)

Provide detailed analysis of:

- ADC architecture
- Quantization
- Resolution
- LSB calculation
- Sampling process
- I2C transactions
- Voltage range

If voltage ranges are available, calculate the effective voltage resolution.

Discuss why ADS1115 was selected.

---

## ESP32-S3 Processing and Communication Stage

### Component

ESP32-S3 Development Board

Explain:

- Data reception
- Data buffering
- Data formatting
- Packet generation
- UART transmission
- Interrupt handling (if implemented)
- Communication management
- Real-time operation

Include code references where available.

---

## Operational Modes

### Real-Time EEG Mode

Explain the complete data path:

OpenBCI → Filter → ADS1115 → ESP32-S3 → Zynq UltraScale+ → PCA9685 → Servo Motors

Provide a detailed signal-flow discussion.

---

### Stored Data Mode

Explain:

Dataset → ESP32-S3 → Zynq UltraScale+ → PCA9685 → Servo Motors

Discuss:

- Offline testing
- Model validation
- Repeatability
- Development advantages

---

## FPGA Processing Platform

### FPGA Device

Zynq UltraScale+ MPSoC XCZU7EV

### Development Board

ZCU104 Evaluation Board

Explain:

- Device architecture
- Processing System (PS)
- Programmable Logic (PL)
- AI acceleration
- Parallel processing
- Real-time inference

Discuss why this platform was selected.

Compare briefly with alternative solutions.

---

## FPGA Interface Analysis

Provide a detailed explanation of:

- UART reception mechanism
- Data parsing
- Buffer management
- Processing pipeline
- AI inference pipeline
- Communication with PWM controller

Explain the exact role of:

- Processing System (PS)
- Programmable Logic (PL)

---

## PWM Generation and Servo Interface

### Component

PCA9685 PWM Driver

Provide detailed analysis of:

- PWM generation mechanism
- Internal timing operation
- Frequency configuration
- Duty-cycle generation
- Servo control methodology

Explain how FPGA commands are converted into servo motion.

---

## Actuation System

### Components

- Servo Motor #1 (Ankle)
- Servo Motor #2 (Wrist)

Explain:

- Functional role
- Motion generation
- Rehabilitation applications
- PWM requirements

---

## Protection Circuit Analysis

Analyze all protection circuitry shown in the schematic including:

- Series resistors
- Pull-down resistors
- Zener diodes
- Protection diodes

Explain:

- Purpose of each component
- Voltage protection mechanism
- Noise suppression role
- Reliability improvements

Use actual values shown in the circuit.

---

## Power System Engineering Analysis

### Components

- 3S LiPo Battery (11.1V)
- 8A Fuse
- Buck Converter #1 (6V)
- Buck Converter #2 (5V)
- Low Noise 3.3V LDO

Provide complete engineering analysis of:

### LiPo Battery

- Capacity
- Expected runtime
- Current capability

### 6V Buck Converter

Explain why servos are powered from a dedicated high-current rail.

### 5V Buck Converter

Explain logic supply generation.

### 3.3V Low-Noise LDO

Explain:

- Noise reduction
- Ripple suppression
- Analog supply requirements

---

## Grounding Analysis

Provide an in-depth discussion of:

- AGND
- DGND
- Star Ground implementation

Explain:

- Return current paths
- Ground loop prevention
- EMI reduction
- EEG noise sensitivity

---

## Design Decisions and Tradeoffs

Discuss:

- Why OpenBCI was selected
- Why ADS1115 was selected
- Why ESP32-S3 was selected
- Why Zynq UltraScale+ was selected
- Why PCA9685 was selected
- Why dual buck converters were used
- Why a low-noise LDO was added
- Why star grounding was implemented

Compare alternatives and justify final choices.

---

## Engineering Calculations

Whenever component values are available in the schematic, include calculations for:

- Cutoff frequency
- ADC resolution
- Power consumption
- Voltage regulation
- Current requirements
- Battery runtime estimation
- Servo current demand

Use actual schematic values whenever possible.

---

## Hardware Component List (Bill of Materials)

Create a detailed BOM table.

At minimum include:

1. OpenBCI Cyton/Daisy Headset
2. TLV9061
3. ADS1115
4. ESP32-S3 Development Board
5. Zynq UltraScale+ XCZU7EV
6. ZCU104 Evaluation Board
7. PCA9685
8. Servo Motors
9. 3S LiPo Battery
10. Buck Converter (6V)
11. Buck Converter (5V)
12. Low Noise LDO

Inspect figures and add:

- Capacitors
- Resistors
- Connectors
- Protection devices
- Headers
- Supporting circuitry

Provide exact part numbers whenever possible.

---

## Circuit Integration and Data Flow

Provide a complete end-to-end explanation of:

- Signal flow
- Data flow
- Power flow

from EEG acquisition to final servo actuation.

The goal is that a reader could rebuild and understand the complete hardware system solely from Chapter 7 without looking at the schematic.

---

# CHAPTER 8

# FPGA Deployment and Hardware Acceleration

Use the old FPGA deployment chapter as the foundation.

Do not remove valid technical content.

Improve and extend it using all available project materials.

---

## FPGA Source Code Analysis

Before writing Chapter 8, inspect and analyze:

- .sv files (primary source)
- .v files (if present)
- .bd block designs
- .xdc constraint files
- .xpr project files
- .xsa hardware platform files
- Synthesis reports
- Implementation reports
- Timing reports
- Power reports

Use these files as authoritative sources.

The chapter should document the actual implementation rather than generic FPGA theory.

---

## Introduction

Provide a deployment overview.

---

## ZCU104 Hardware Platform Overview

Use the provided ZCU104 PDF.

Create a dedicated section:

### Board Overview Figure

Reference the provided board image.

### ZCU104 Component Mapping Table

Create:

| Number | Component Name | Function | Role in This Project |
|----------|----------|----------|----------|

Use the numbering exactly as shown in the PDF.

---

## Hardware Resource Description

Explain all major board resources including:

- Zynq UltraScale+ MPSoC
- DDR Memory
- QSPI Flash
- SD Card Interface
- UART Interfaces
- USB Interfaces
- Ethernet Interface
- FMC Connectors
- Clock Sources
- JTAG Interface
- Power Management Circuits
- Additional numbered peripherals

For each component explain:

1. General purpose.
2. Whether it is used in this project.
3. Contribution to deployment workflow.

---

## FPGA Deployment Workflow

Describe:

- Model preparation
- FPGA integration
- Deployment sequence
- Validation process

---

## Vivado Design Flow

Explain:

- Project creation
- Block design
- IP integration
- Synthesis
- Implementation
- Bitstream generation

Include screenshots where available.

---

## Hardware Architecture

Describe the final FPGA architecture.

Include figures.

---

## Processing System Configuration

Explain:

- ARM subsystem
- Peripheral configuration
- Memory mapping
- UART configuration

---

## Programmable Logic Configuration

Explain:

- Logic blocks
- Accelerators
- Data paths

Include diagrams where available.

---

## AI Model Deployment

Describe the deployed model.

Explain:

- Preprocessing
- Model conversion
- Deployment strategy
- Optimization techniques

---

## Data Transfer Mechanisms

Explain:

- UART communication
- Internal transfers
- Buffering

---

## AXI Interconnect Architecture

Describe:

- AXI interfaces
- Data movement
- Communication flow

Include diagrams where available.

---

## Memory Architecture

Explain:

- DDR usage
- Buffer allocation
- Data storage

---

## UART Communication with ESP32

Describe:

- Protocol
- Packet structure
- Synchronization
- Error handling

Include code snippets when available.

---

## Real-Time Inference Pipeline

Explain:

EEG Input → Processing → Inference → Decision → Servo Control

Provide a detailed walkthrough.

---

## Hardware Acceleration Strategy

Discuss:

- Parallelism
- Throughput improvements
- Latency reduction
- FPGA advantages

---

## Resource Utilization

Create utilization tables if reports exist.

Include:

- LUTs
- FFs
- BRAM
- DSPs

Provide analysis.

---

## Timing Analysis

Use timing reports if available.

Discuss:

- Critical paths
- Timing closure
- Achieved frequency

---

## Power Analysis

Use available reports.

Discuss:

- Static power
- Dynamic power
- Optimization methods

---

## Software Stack

Explain:

- Vivado
- Vitis
- Embedded Linux
- Drivers
- Communication software

---

## FPGA Development Language Requirement

The FPGA implementation was developed using **SystemVerilog (.sv)**.

Do NOT generate VHDL examples.

Do NOT describe the implementation as VHDL-based.

Use actual SystemVerilog modules from the thesis directory whenever available.

---

## Code Listings

Include meaningful code snippets from:

- SystemVerilog (.sv)
- C
- C++
- Python
- Vitis Applications
- Driver Code

For FPGA sections prioritize:

- UART Receiver
- UART Transmitter
- FSMs
- Data Buffers
- AXI Interfaces
- PWM Controllers
- Servo Control Modules
- Custom Processing Blocks

For each snippet explain:

1. Purpose.
2. Inputs and outputs.
3. Internal operation.
4. Integration into the system.
5. Design rationale.

Avoid long code dumps.

---

## SystemVerilog Architecture Analysis

Analyze the actual SystemVerilog hierarchy.

Explain:

- Module hierarchy
- FSM designs
- Clock domains
- Reset architecture
- Data flow
- Pipeline stages
- Resource implications
- Communication interfaces

The explanation must be based on the actual implementation rather than generic FPGA concepts.

---

## Performance Evaluation

Include available metrics:

- Latency
- Throughput
- Inference speed
- Real-time performance

Analyze results.

---

## Deployment Challenges

Discuss:

- Communication bottlenecks
- Resource limitations
- Timing closure issues
- Debugging process
- Optimization techniques

---

## Final FPGA Architecture

Provide a complete end-to-end explanation showing how EEG data travels through the deployed FPGA-based AI system and ultimately controls the servo motors.

---

# Output Requirements

Generate:

- Complete Chapter 7
- Complete Chapter 8

Both chapters must be fully written.

Maintain IEEE citation style.

Reference all available figures.

Insert placeholders where figures are missing.

Use the provided references.

The output must be thesis-ready, technically accurate, highly detailed, and directly pasteable into Microsoft Word.