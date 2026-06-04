# Wearable LiPo 3S Power Tree — Build & Bring-up Guide

Concrete BOM, wiring, safety procedure and verification steps for assembling
the power tree described in Chapter 7 §7.15 of the thesis.

> **Purpose.** Move the project from the bench rig (12 V wall adapter +
> separate servo bench supply) to the actual wearable supply documented in
> the thesis: 3-cell LiPo battery → 8 A fuse → dual buck converters
> (6 V/6 A for servos, 5 V/3 A for logic) → 3.3 V low-noise LDO for analog.

> **Safety first.** LiPo batteries store enough energy to start a fire if
> shorted or over-discharged. Read §0 in full before touching any cells.

---

## 0. Safety prerequisites (read first)

| Risk | Mitigation |
|---|---|
| LiPo cell puncture / fire | Build inside a LiPo-safe bag; never bend the pack; never pierce the foil |
| Reverse polarity at battery | XT60 connector is keyed; do NOT bypass |
| Over-discharge ( < 3.0 V/cell ) | Run a low-voltage cutoff or stop the demo when pack reads ≤ 10.5 V |
| Charging fire | Charge **only** with a balance charger on a non-flammable surface, monitored |
| Buck reverse current at shutdown | Schottky diode at each buck output (see §3) |
| Servo stall current | 8 A primary fuse + per-rail Zener clamp (see §3) |

Required PPE on the bench: safety glasses, side cutters with insulated
handles, multimeter rated for ≥ 20 A on the current scale, no rings or
metal jewellery on the working hand.

---

## 1. Bill of Materials

**Table P-1: Wearable power tree BOM (LiPo + bucks + LDO).**

| Ref | Qty | Part | Vendor / model | Notes |
|---|---|---|---|---|
| BT1 | 1 | LiPo 3S 11.1 V, 2200 mAh, ≥ 30C discharge | Tattu R-Line, ZIPPY Flightmax, Turnigy | XT60 connector pre-terminated |
| C1 | 1 | LiPo balance charger | iSDT D2, SkyRC iMAX B6AC | for off-bench charging only |
| C2 | 1 | LiPo voltage alarm / cell monitor | HobbyKing 1S–8S | beeps at < 3.3 V/cell |
| F1 | 1 | 8 A automotive blade fuse + inline holder | Littelfuse FKS/ATO | between BT1 (+) and bus |
| SW1 | 1 | DPDT slide switch ≥ 10 A | C&K 7000 series, NKK M2T | master enable |
| U1 | 1 | Buck #1 — 6 V / 6 A adjustable buck | Pololu D24V90F6, DROK 180023, generic XL4015 6 A | "actuator rail" |
| U2 | 1 | Buck #2 — 5 V / 3 A adjustable buck | Pololu D36V28F5, generic MP1584 | "logic rail" |
| U3 | 1 | LDO — 3.3 V / 1 A low-noise | Texas Instruments LP5907MFX-3.3, Analog Devices ADP7142 | "analog rail" (≥ 60 dB PSRR @ 1 kHz) |
| C3 | 2 | Input cap — 470 µF / 25 V electrolytic, low-ESR | Panasonic FR-A, Nichicon UWX | one per buck input |
| C4 | 2 | Output cap — 220 µF / 16 V electrolytic, low-ESR | as above | one per buck output |
| C5 | 1 | LDO input/output cap — 10 µF / 10 V ceramic X5R 1206 | Murata, Samsung | per LDO datasheet |
| C6 | 1 | LDO bypass — 10 nF + 100 nF / 25 V ceramic X7R | generic | between LDO output and AGND |
| D1 | 2 | Schottky 3 A / 60 V | SS36, SS54 | reverse-current protection at each buck output |
| D2 | 1 | Zener 5.6 V, 1 W | 1N4734A | clamp on actuator rail (V+ at PCA9685) |
| R1 | — | Voltage-divider resistors for buck Vout setting | 0805 1 % E96 | per buck module — read datasheet |
| W1 | ~1 m | 12 AWG silicone wire (red/black) | Generic LiPo grade | between BT1 and bus / Buck #1 |
| W2 | ~2 m | 20 AWG silicone wire (red/black) | Generic | between rails and loads |
| W3 | ~50 cm | 24 AWG ribbon / jumper | Generic | low-current sense / monitoring |
| J1 | 1 | XT60 female panel-mount | Generic LiPo grade | enclosure inlet |
| J2 | 2 | Barrel jack 5.5 × 2.1 mm panel-mount + plug | Generic | to ZCU104 (5 V) and to servo bus (6 V) |
| J3 | 1 | 2-pin JST-XH header | Generic | to LDO analog rail (3.3 V) |
| TP | 5 | Test points / standoffs | Keystone 5000-series | for multimeter probes |
| ENCL | 1 | Plastic / 3D-printed enclosure with LiPo bay | custom | ventilation slots for bucks |

Estimated parts cost: USD 60–90 depending on sourcing.

---

## 2. Power tree topology

```
                                       +-- Buck #1 (6 V / 6 A) --+-- D1a -- V+ rail -- PCA9685 V+ -- servos
                                       |                         |
                                       |                         +-- D2 (Zener 5.6 V) -- GND  (clamp)
                                       |
[BT1 11.1 V]--[F1 8 A]--[SW1]--+-- BUS --+-- Buck #2 (5 V / 3 A) --+-- D1b -- 5 V rail -- ZCU104 J52, ESP32-S3 USB-5 V (optional)
                                       |                          |
                                       |                          +-- U3 LDO (3.3 V / 1 A) -- 3V3 (analog) -- TLV9061, ADS1115 AVDD
                                       |
                                       +-- C2 cell-voltage alarm
```

Three load rails are produced from one battery:

- **6 V rail** — actuator servos + PCA9685 V+
- **5 V rail** — ZCU104 main barrel input + (optional) ESP32-S3 5 V pin
- **3.3 V analog rail** — analog front-end (TLV9061, ADS1115 AVDD, OpenBCI
  buffered output supply if not otherwise powered)

All rails share a single **star ground** as described in Ch.7 §7.16.

---

## 3. Bench assembly procedure

### 3.1 Pre-assembly checks

1. With a multimeter, verify the LiPo terminal voltage is **between 11.4 V
   and 12.6 V**. If lower than 11.1 V, charge before proceeding. If higher
   than 12.6 V, the pack is dangerously overcharged — do not use.
2. Verify the XT60 connector polarity matches the wiring colours (red →
   `+`, black → `−`). On counterfeit packs this is sometimes reversed.
3. Confirm the LiPo voltage alarm reports each cell separately and
   reaches the 3.3 V/cell warning threshold within audible range.

### 3.2 Adjust Buck output voltages (no battery yet)

Adjustable bucks come from the factory at the lowest output setting.

1. Connect a bench power supply set to 11.1 V / 1 A current-limited to
   the buck input.
2. Turn the trim pot until the output reads **6.00 V ± 0.05 V** (for
   Buck #1) or **5.00 V ± 0.05 V** (for Buck #2).
3. Disconnect the bench supply and let the buck capacitors discharge
   (≥ 30 s).
4. Repeat for the other buck.

### 3.3 Wire the input chain

Order matters — wire from the load side back to the battery, so the
last thing you connect is the live cell.

1. Strip and crimp the BT1 wire ends. **Do not** connect the XT60 yet.
2. Wire `BT1(+) → F1 → SW1 → BUS+`. Verify SW1 is OFF.
3. Connect `BUS+` to Buck #1 input (+) and Buck #2 input (+).
4. Connect `BT1(−) → BUS−` and `BUS− →` both buck inputs (−).
5. Connect each buck output through its Schottky diode (D1a, D1b) to
   the corresponding rail node.
6. Connect Buck #2 output → LDO input.
7. Connect LDO output → 3V3 analog rail.
8. Wire the 5.6 V Zener clamp (D2) between V+ rail and GND, **cathode to V+**.

### 3.4 First power-on

1. With SW1 still OFF, set every load output JX to a dummy resistor or
   open-circuit (do NOT connect to the ZCU104 yet).
2. Insert F1.
3. Plug in the XT60 (now the system is hot up to SW1).
4. Verify with multimeter that the bus past F1 reads 11.1 V and past
   SW1 reads 0 V.
5. Turn SW1 ON.
6. Verify every output rail with multimeter:
   - 6 V rail = 6.00 V ± 0.05 V
   - 5 V rail = 5.00 V ± 0.05 V
   - 3.3 V rail = 3.30 V ± 0.05 V
7. With SW1 ON, listen for buck whining (a sign of unstable feedback).
   If whining is present, add 100 µF electrolytic at the buck output
   and re-test.
8. Turn SW1 OFF and disconnect XT60.

### 3.5 Connect the loads (one at a time)

Always connect to the rails **with SW1 OFF**. Then turn SW1 ON and
verify behavior before adding the next load.

1. **5 V rail → ZCU104 barrel jack J52.** Power up the board; verify
   the ZCU104 DONE LED and PS UART0 console come up as on the bench
   rig.
2. **3.3 V rail → ESP32-S3 + ADS1115 + TLV9061.** Verify the ESP32-S3
   USB-serial heartbeat is normal and that the I²C bus enumerates both
   peripherals.
3. **6 V rail → PCA9685 V+.** Verify the PCA9685 channel-status LEDs
   come up and that the servo channels are in their rest positions
   (the firmware's `STATE_HOMING` should already have run).

If at any stage the LiPo alarm beeps, turn SW1 OFF immediately and
investigate the load (most likely a short).

---

## 4. Verification and characterization

### 4.1 Static current draw at idle

With everything powered and the system in `STATE_IDLE`, measure the
pack current using a clamp meter on the battery (+) wire:

- Target: **≤ 1.5 A**
- Investigate higher draws as potential short.

### 4.2 Inference-active current draw

Stream a continuous EEG window into the FPGA (see PHASE_B_BRINGUP.md
§B6). Re-measure the pack current.

- Target: **2.0 ± 0.5 A** (matches the §7.17.4 calc)

### 4.3 Servo motion current spike

Issue a `T1\n` test command on the ESP32-S3 USB-serial. The hand servo
will move from rest to grip. Watch the multimeter on the 6 V rail:

- Steady state idle ≤ 100 mA
- Movement transient peak typically 0.6–1.5 A for ≤ 100 ms
- Stall current (if servo binds) ≤ 2.0 A — the 8 A primary fuse
  protects the pack

### 4.4 Battery runtime measurement

Cycle the system in `STATE_RUNNING` continuously and stop when the
LiPo alarm beeps. Measure elapsed time.

- Target: **≥ 60 minutes** (matches the §7.17.4 calc)
- Less than 45 minutes → investigate buck efficiency or wiring losses

### 4.5 Noise floor on the analog rail

Connect an oscilloscope (AC-coupled, 50 mV/div, 100 µs/div) at the
ADS1115 AVDD pin. Measure the supply ripple.

- Target: **≤ 50 µV RMS** (well below the ADS1115 LSB of 62.5 µV)
- Ripple > 100 µV → LDO is underspec'd or input cap is missing

---

## 5. Operating procedure

### 5.1 Pre-flight checklist (every demo)

- [ ] LiPo pack voltage ≥ 11.1 V (multimeter check)
- [ ] LiPo alarm connected and audible
- [ ] All three rails verified by multimeter before connecting loads
- [ ] No exposed conductors on the bus side of SW1
- [ ] ZCU104, ESP32-S3, servos, PCA9685 grounds all at the star point
- [ ] Servo travel range cleared of obstructions

### 5.2 Power-on sequence

1. Turn SW1 OFF.
2. Plug in the LiPo (XT60).
3. Verify LiPo alarm chirp.
4. Turn SW1 ON.
5. Wait 3 seconds for ESP32-S3 `STATE_HOMING` to complete.
6. Begin EEG streaming / demo.

### 5.3 Power-off sequence

1. Stop EEG streaming so the servos return to `STATE_IDLE` rest.
2. Turn SW1 OFF.
3. Unplug XT60 (system is now fully de-energized).
4. Place LiPo in the LiPo-safe bag before storing.

### 5.4 Charging

Charge only on a non-flammable surface, in a LiPo-safe bag if
available, with the balance charger configured for 3S Li-ion at the
appropriate charge current (≤ 1C = 2.2 A for the 2200 mAh pack).
**Never leave the charger unattended.**

---

## 6. Migration from the bench rig

The bench rig today uses:

- 12 V wall adapter → ZCU104 J52
- Bench supply at 5 V → PCA9685 V+ and servos
- ESP32-S3 powered from laptop USB

To migrate to the wearable supply:

1. Build the power tree per §3 above.
2. Connect rails to loads per §3.5.
3. Disconnect the wall adapter and the bench supply.
4. Optionally disconnect the ESP32-S3 from the laptop USB (only needed
   during firmware development) — the 5 V rail powers it through its
   5 V pin instead.
5. Update `PHASE_B_BRINGUP.md` to reference §3 of this document for
   any new bench setup.

The system on the LiPo supply behaves identically to the bench rig
provided the rails are within ± 5 % of nominal — there are no
firmware or bitstream changes required.

---

## 7. Cross-references to the thesis

- **Ch.7 §7.15** — describes this exact topology as implemented.
- **Ch.7 §7.16** — describes the star-ground rationale.
- **Ch.7 §7.17.4** — provides the battery-runtime calculation that this
  document realizes.

If any of the values in this document change (for example, a different
buck module is sourced and produces 6.2 V instead of 6.0 V), update
Ch.7 §7.15 / Table 7-2 accordingly to keep the thesis and the as-built
system consistent.

---

*End of LiPo power tree build guide.*
