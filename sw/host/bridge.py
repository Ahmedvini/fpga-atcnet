#!/usr/bin/env python3
"""
bridge.py — Path A USB ↔ USB bridge for the db_atcnet bench setup.

Two USB cables on the laptop:
  • ZCU104 USB cable -> CP2108 quad-UART -> /dev/ttyUSB{0..3}
    One of those virtual TTYs is the PL UART (the EMIO UART_1 we routed to
    C19/A20 in the BD). That's where the Zynq PS sends classification bytes.
  • ESP32 USB cable -> CP210x/CH340 -> /dev/ttyUSB{N}
    This is the ESP32's USB-Serial that runs the sketch's text command
    parser (T0, T1, STATUS, etc.).

This script:
  1. Reads class bytes (0x00 or 0x01) from the Zynq's PL UART.
  2. Translates each into the ESP32's text-command equivalent ("T0\\n" /
     "T1\\n") and writes to the ESP32's USB-Serial.
  3. Optionally also streams a 6000-byte EEG window FILE to the Zynq first
     (to kick off inference) so you can do an end-to-end test from one
     command.

Use --list to discover the devices on your laptop, then pass --zynq and
--esp explicitly.

Tested on Linux. On macOS the device names look like /dev/cu.usbserial-*.
"""

import argparse
import sys
import time
from serial import Serial
from serial.tools.list_ports import comports


def list_serials():
    print("Available serial devices:")
    ports = list(comports())
    if not ports:
        print("  (none — check that both USB cables are plugged in)")
        return
    for p in ports:
        vid_pid = f"{p.vid:04x}:{p.pid:04x}" if p.vid else "?:?"
        print(f"  {p.device:<16s}  {vid_pid:<10s}  {p.description}")
    print()
    print("Heuristic: ZCU104 CP2108 enumerates 4 ports with VID 10c4 PID ea71/ea7x;")
    print("the PL UART is usually the 2nd or 3rd. ESP32 CP2102 has PID ea60 (one port).")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--zynq", default="/dev/ttyUSB1",
                    help="ZCU104 PL UART device (default: %(default)s)")
    ap.add_argument("--esp", default="/dev/ttyUSB0",
                    help="ESP32 USB-Serial device (default: %(default)s)")
    ap.add_argument("--zynq-baud", type=int, default=460800,
                    help="ZCU104 PL UART baud (default: %(default)s)")
    ap.add_argument("--esp-baud", type=int, default=115200,
                    help="ESP32 USB-Serial baud (default: %(default)s)")
    ap.add_argument("--stream", metavar="FILE",
                    help="Path to a 6000-byte raw EEG window to stream to the "
                         "Zynq once before entering the forwarder loop")
    ap.add_argument("--list", action="store_true",
                    help="List available serial ports and exit")
    ap.add_argument("--quiet", action="store_true",
                    help="Don't echo ESP32 debug output to stdout")
    args = ap.parse_args()

    if args.list:
        list_serials()
        return

    print(f"[bridge] Zynq:   {args.zynq}  @ {args.zynq_baud} 8N1")
    print(f"[bridge] ESP32:  {args.esp}   @ {args.esp_baud} 8N1")

    try:
        zynq = Serial(args.zynq, args.zynq_baud, timeout=0.05)
        esp = Serial(args.esp, args.esp_baud, timeout=0.05)
    except Exception as e:
        print(f"[bridge] ERROR opening serial: {e}", file=sys.stderr)
        print("       Try `--list` to see what's connected.", file=sys.stderr)
        sys.exit(1)

    # Drain any stale bytes
    zynq.reset_input_buffer()
    esp.reset_input_buffer()
    time.sleep(0.2)

    # Optional one-shot EEG stream to Zynq
    if args.stream:
        try:
            with open(args.stream, "rb") as f:
                data = f.read()
        except Exception as e:
            print(f"[bridge] ERROR reading {args.stream}: {e}", file=sys.stderr)
            sys.exit(1)
        if len(data) != 6000:
            print(f"[bridge] WARNING: expected 6000 bytes, got {len(data)} — sending anyway")
        print(f"[bridge] streaming {len(data)} bytes to Zynq...")
        zynq.write(data)
        zynq.flush()
        time.sleep(0.1)  # give the PS a moment to start its DMA

    print("[bridge] forwarding (Ctrl+C to stop)")
    n_class0 = 0
    n_class1 = 0
    n_bad = 0
    try:
        while True:
            # Z -> E: classifications
            b = zynq.read(1)
            if b:
                cls = b[0]
                if cls == 0:
                    esp.write(b"T0\n")
                    n_class0 += 1
                    print(f"[Z->E] class=0  (total c0={n_class0} c1={n_class1})")
                elif cls == 1:
                    esp.write(b"T1\n")
                    n_class1 += 1
                    print(f"[Z->E] class=1  (total c0={n_class0} c1={n_class1})")
                else:
                    n_bad += 1
                    print(f"[Z   ] dropped non-class byte 0x{cls:02x}  (bad={n_bad})")

            # ESP32 debug -> console
            if not args.quiet:
                b = esp.read(256)
                if b:
                    try:
                        sys.stdout.write(b.decode("utf-8", errors="replace"))
                        sys.stdout.flush()
                    except Exception:
                        pass
    except KeyboardInterrupt:
        print("\n[bridge] stopped by user")
    finally:
        zynq.close()
        esp.close()


if __name__ == "__main__":
    main()
