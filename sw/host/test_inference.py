#!/usr/bin/env python3
"""
test_inference.py — Stream a 6000-byte EEG window to the Zynq PS UART1 and
read the 1-byte classification reply. Use this to verify the FPGA inference
pipeline end-to-end without involving the ESP32.

Usage:
    python3 sw/host/test_inference.py \
        --window build/test_window.bin \
        --port /dev/ttyUSB3 \
        --baud 460800

Default port is /dev/ttyUSB3 (CP2108 channel 2 = PS UART1 EMIO route on the
ZCU106 with the current udev mapping). Adjust if your enumeration differs.
"""
import argparse
import sys
import time
from serial import Serial


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--window", default="build/test_window.bin",
                    help="Path to the 6000-byte EEG window binary (default %(default)s)")
    ap.add_argument("--port", default="/dev/ttyUSB3",
                    help="Zynq PS UART1 serial port (default %(default)s)")
    ap.add_argument("--baud", type=int, default=460800,
                    help="Baud rate (default %(default)s)")
    ap.add_argument("--n", type=int, default=1,
                    help="Number of consecutive inferences to run (default 1)")
    args = ap.parse_args()

    # Load the window
    try:
        with open(args.window, "rb") as f:
            data = f.read()
    except Exception as e:
        print(f"[test] ERROR reading {args.window}: {e}", file=sys.stderr)
        sys.exit(1)
    if len(data) != 6000:
        print(f"[test] WARN: expected 6000 bytes, got {len(data)} — sending anyway",
              file=sys.stderr)

    # Open the serial port
    try:
        ser = Serial(args.port, args.baud, timeout=2.0)
    except Exception as e:
        print(f"[test] ERROR opening {args.port}: {e}", file=sys.stderr)
        sys.exit(1)
    print(f"[test] Opened {args.port} @ {args.baud} 8N1")

    # Drain any pending bytes
    ser.reset_input_buffer()
    ser.reset_output_buffer()
    time.sleep(0.2)

    for i in range(args.n):
        t0 = time.monotonic()
        ser.write(data)
        ser.flush()
        write_dt = time.monotonic() - t0
        print(f"[test] #{i+1}: sent 6000 bytes in {write_dt*1000:.1f} ms,"
              f" waiting for class byte (2s timeout)...")
        reply = ser.read(1)
        dt = time.monotonic() - t0
        if len(reply) != 1:
            print(f"[test] #{i+1}: TIMEOUT — no class byte received after"
                  f" {dt*1000:.0f} ms")
            sys.exit(2)
        cls = reply[0]
        print(f"[test] #{i+1}: got class={cls} (0x{cls:02x}) in {dt*1000:.1f} ms"
              f" total round-trip")

    print("[test] all inferences completed cleanly")
    ser.close()


if __name__ == "__main__":
    main()
