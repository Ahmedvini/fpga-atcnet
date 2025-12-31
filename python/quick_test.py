"""
Quick Test - Minimal verification to check if everything is working
Run this first before the full test suite
"""

import numpy as np
import json
import os

def float_to_fixed(val, frac_bits=8):
    """Convert float to fixed-point"""
    return int(round(val * (2 ** frac_bits)))

def fixed_to_float(val, frac_bits=8):
    """Convert fixed-point to float"""
    if val & (1 << 15):  # Sign bit
        val = val - (1 << 16)
    return val / (2 ** frac_bits)

def quick_test():
    """Generate minimal test case for quick verification"""
    print("Generating quick test case...")
    
    # Minimal parameters
    seq_length = 8
    in_channels = 4
    out_channels = 4
    kernel_size = 3
    
    # Simple input (counting pattern)
    input_seq = np.zeros((seq_length, in_channels), dtype=np.float32)
    for t in range(seq_length):
        for c in range(in_channels):
            input_seq[t, c] = (t + c) * 0.1
    
    # Simple kernel (identity)
    kernel = np.zeros((kernel_size, in_channels, out_channels), dtype=np.float32)
    for i in range(min(in_channels, out_channels)):
        kernel[0, i, i] = 1.0  # Only first tap
    
    # Compute expected output manually
    output_seq = np.zeros((seq_length, out_channels), dtype=np.float32)
    for t in range(seq_length):
        for o in range(out_channels):
            acc = 0.0
            for k in range(kernel_size):
                if t >= k:  # Causal
                    for i in range(in_channels):
                        acc += input_seq[t-k, i] * kernel[k, i, o]
            output_seq[t, o] = acc
    
    # Convert to fixed-point
    input_fixed = [[float_to_fixed(input_seq[t, c]) for c in range(in_channels)] 
                   for t in range(seq_length)]
    kernel_fixed = [[[float_to_fixed(kernel[k, i, o]) 
                      for o in range(out_channels)] 
                     for i in range(in_channels)] 
                    for k in range(kernel_size)]
    output_fixed = [[float_to_fixed(output_seq[t, o]) for o in range(out_channels)]
                    for t in range(seq_length)]
    
    test_case = {
        'name': 'quick_test',
        'config': {
            'seq_length': seq_length,
            'input_channels': in_channels,
            'output_channels': out_channels,
            'kernel_size': kernel_size
        },
        'input_fixed': input_fixed,
        'kernel_fixed': kernel_fixed,
        'output_fixed': output_fixed,
        'fixed_point_config': {
            'total_bits': 16,
            'frac_bits': 8
        }
    }
    
    # Save
    output_dir = '../sim'
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)
    
    filepath = os.path.join(output_dir, 'quick_test.json')
    with open(filepath, 'w') as f:
        json.dump(test_case, f, indent=2)
    
    print(f"Saved to {filepath}")
    
    # Print summary
    print("\nTest Summary:")
    print(f"  Input:  [{seq_length}, {in_channels}]")
    print(f"  Kernel: [{kernel_size}, {in_channels}, {out_channels}]")
    print(f"  Output: [{seq_length}, {out_channels}]")
    print("\nFirst 3 input samples:")
    for t in range(min(3, seq_length)):
        print(f"  t={t}: {input_seq[t, :].tolist()}")
    print("\nExpected first 3 outputs:")
    for t in range(min(3, seq_length)):
        print(f"  t={t}: {output_seq[t, :].tolist()}")
    
    # Manual verification example
    print("\n--- Manual Verification Example ---")
    print("For t=0, channel 0:")
    print(f"  Input[0,0] = {input_seq[0,0]:.3f}")
    print(f"  Kernel[0,0,0] = {kernel[0,0,0]:.3f}")
    print(f"  Expected output = {output_seq[0,0]:.3f}")
    print(f"  Fixed-point output = {output_fixed[0][0]} (0x{output_fixed[0][0]:04x})")
    print(f"  Back to float = {fixed_to_float(output_fixed[0][0]):.3f}")
    
    return test_case

if __name__ == "__main__":
    print("="*60)
    print("Quick Test Generator")
    print("="*60)
    print()
    
    test_case = quick_test()
    
    print()
    print("="*60)
    print("Quick test case generated!")
    print("Run the RTL simulation with this test case to verify basic functionality.")
    print("="*60)
