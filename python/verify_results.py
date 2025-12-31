"""
Verification Result Checker
Compares RTL simulation results with Python golden reference
"""

import json
import numpy as np
import sys
from pathlib import Path


class VerificationChecker:
    """Compare hardware simulation results with golden reference"""
    
    def __init__(self, tolerance_lsb=2, frac_bits=8):
        self.tolerance_lsb = tolerance_lsb
        self.frac_bits = frac_bits
        self.errors = []
        self.warnings = []
        
    def fixed_to_float(self, value, is_signed=True):
        """Convert fixed-point to float"""
        if is_signed:
            # Handle sign extension for negative numbers
            if isinstance(value, int):
                if value & (1 << 15):  # Check sign bit for 16-bit
                    value = value - (1 << 16)
        return value / (2 ** self.frac_bits)
    
    def compare_values(self, rtl_value, golden_value, channel_idx=None, sample_idx=None):
        """Compare single value with tolerance"""
        rtl_float = self.fixed_to_float(rtl_value)
        golden_float = self.fixed_to_float(golden_value)
        
        diff = abs(rtl_float - golden_float)
        lsb_value = 1.0 / (2 ** self.frac_bits)
        diff_lsb = diff / lsb_value
        
        passed = diff_lsb <= self.tolerance_lsb
        
        error_info = {
            'passed': passed,
            'channel': channel_idx,
            'sample': sample_idx,
            'rtl_fixed': rtl_value,
            'golden_fixed': golden_value,
            'rtl_float': rtl_float,
            'golden_float': golden_float,
            'diff_float': diff,
            'diff_lsb': diff_lsb
        }
        
        if not passed:
            self.errors.append(error_info)
        
        return error_info
    
    def compare_vectors(self, rtl_vector, golden_vector, sample_idx=None):
        """Compare full output vectors"""
        if len(rtl_vector) != len(golden_vector):
            error = {
                'type': 'dimension_mismatch',
                'rtl_length': len(rtl_vector),
                'golden_length': len(golden_vector)
            }
            self.errors.append(error)
            return False
        
        results = []
        for ch_idx, (rtl_val, golden_val) in enumerate(zip(rtl_vector, golden_vector)):
            result = self.compare_values(rtl_val, golden_val, ch_idx, sample_idx)
            results.append(result)
        
        return all(r['passed'] for r in results)
    
    def load_rtl_results(self, filepath):
        """Load RTL simulation results from file"""
        if not Path(filepath).exists():
            print(f"ERROR: RTL results file not found: {filepath}")
            return None
        
        # Try different formats
        if filepath.endswith('.json'):
            with open(filepath, 'r') as f:
                return json.load(f)
        elif filepath.endswith('.txt'):
            return self.parse_rtl_text_output(filepath)
        elif filepath.endswith('.vcd'):
            print("VCD parsing not implemented - please convert to JSON or text format")
            return None
        else:
            print(f"Unknown file format: {filepath}")
            return None
    
    def parse_rtl_text_output(self, filepath):
        """Parse simple text format RTL output"""
        results = {
            'test_name': '',
            'samples': []
        }
        
        with open(filepath, 'r') as f:
            for line in f:
                line = line.strip()
                
                # Parse output lines (format: "CYCLE: 10 VALID: 1 OUTPUT: 1234,5678,...")
                if 'OUTPUT:' in line:
                    parts = line.split()
                    cycle = None
                    valid = False
                    output = []
                    
                    for i, part in enumerate(parts):
                        if part == 'CYCLE:' and i+1 < len(parts):
                            cycle = int(parts[i+1])
                        elif part == 'VALID:' and i+1 < len(parts):
                            valid = int(parts[i+1]) == 1
                        elif part == 'OUTPUT:' and i+1 < len(parts):
                            # Parse comma-separated hex values
                            output_str = parts[i+1]
                            output = [int(x, 16) if x.startswith('0x') else int(x) 
                                     for x in output_str.split(',')]
                    
                    if valid:
                        results['samples'].append({
                            'cycle': cycle,
                            'output': output
                        })
        
        return results
    
    def compare_test_case(self, rtl_results, golden_data):
        """Compare full test case"""
        print("\n" + "="*70)
        print(f"Comparing test case: {golden_data.get('name', 'unknown')}")
        print("="*70)
        
        golden_samples = []
        test_type = golden_data.get('name', '')
        
        # Extract golden reference based on test type
        if 'streaming_samples' in golden_data:
            # Streaming test format
            golden_samples = golden_data['streaming_samples']
        elif 'output_fixed' in golden_data:
            # Simple test format
            output = golden_data['output_fixed']
            for idx, sample_output in enumerate(output):
                golden_samples.append({
                    'cycle': idx,
                    'expected_output_fixed': sample_output,
                    'valid': True
                })
        else:
            print("WARNING: Unknown golden data format")
            return False
        
        rtl_samples = rtl_results.get('samples', [])
        
        print(f"Golden samples: {len(golden_samples)}")
        print(f"RTL samples: {len(rtl_samples)}")
        
        if len(rtl_samples) == 0:
            print("ERROR: No RTL samples found!")
            return False
        
        # Compare sample by sample
        sample_errors = 0
        samples_compared = 0
        
        for rtl_sample in rtl_samples:
            rtl_cycle = rtl_sample.get('cycle', -1)
            rtl_output = rtl_sample.get('output', [])
            
            # Find matching golden sample
            golden_sample = None
            for gs in golden_samples:
                if gs.get('cycle') == rtl_cycle or samples_compared == len(golden_samples):
                    golden_sample = gs
                    break
            
            if golden_sample is None and samples_compared < len(golden_samples):
                golden_sample = golden_samples[samples_compared]
            
            if golden_sample is None:
                print(f"WARNING: No golden sample for RTL cycle {rtl_cycle}")
                continue
            
            golden_output = golden_sample.get('expected_output_fixed', 
                                             golden_sample.get('output_fixed', []))
            
            # Compare
            match = self.compare_vectors(rtl_output, golden_output, samples_compared)
            samples_compared += 1
            
            if not match:
                sample_errors += 1
                print(f"  Sample {samples_compared} (Cycle {rtl_cycle}): MISMATCH")
                if sample_errors <= 5:  # Show first few errors
                    for err in self.errors[-len(rtl_output):]:
                        if err.get('sample') == samples_compared - 1:
                            print(f"    Channel {err['channel']}: "
                                  f"RTL={err['rtl_float']:.4f} "
                                  f"Golden={err['golden_float']:.4f} "
                                  f"Diff={err['diff_lsb']:.2f} LSB")
            else:
                if samples_compared <= 5 or samples_compared % 10 == 0:
                    print(f"  Sample {samples_compared} (Cycle {rtl_cycle}): PASS")
        
        # Summary
        print("\n" + "-"*70)
        print(f"Samples compared: {samples_compared}")
        print(f"Sample mismatches: {sample_errors}")
        print(f"Total value errors: {len(self.errors)}")
        print(f"Pass rate: {100*(samples_compared-sample_errors)/max(samples_compared,1):.2f}%")
        
        return sample_errors == 0
    
    def generate_report(self, output_file='verification_report.txt'):
        """Generate detailed verification report"""
        with open(output_file, 'w') as f:
            f.write("="*70 + "\n")
            f.write("VERIFICATION REPORT\n")
            f.write("="*70 + "\n\n")
            
            f.write(f"Total errors: {len(self.errors)}\n")
            f.write(f"Total warnings: {len(self.warnings)}\n")
            f.write(f"Tolerance: {self.tolerance_lsb} LSB\n\n")
            
            if len(self.errors) > 0:
                f.write("-"*70 + "\n")
                f.write("ERROR DETAILS:\n")
                f.write("-"*70 + "\n")
                
                for idx, err in enumerate(self.errors[:100], 1):  # Limit to 100 errors
                    if 'type' in err:
                        f.write(f"\n{idx}. {err['type']}: {err}\n")
                    else:
                        f.write(f"\n{idx}. Sample {err.get('sample', '?')}, "
                               f"Channel {err.get('channel', '?')}:\n")
                        f.write(f"   RTL:    {err['rtl_float']:.6f} ({err['rtl_fixed']:#06x})\n")
                        f.write(f"   Golden: {err['golden_float']:.6f} ({err['golden_fixed']:#06x})\n")
                        f.write(f"   Diff:   {err['diff_float']:.6f} ({err['diff_lsb']:.2f} LSB)\n")
                
                if len(self.errors) > 100:
                    f.write(f"\n... and {len(self.errors)-100} more errors\n")
            
            if len(self.warnings) > 0:
                f.write("\n" + "-"*70 + "\n")
                f.write("WARNINGS:\n")
                f.write("-"*70 + "\n")
                for idx, warn in enumerate(self.warnings, 1):
                    f.write(f"{idx}. {warn}\n")
        
        print(f"\nDetailed report written to: {output_file}")


def main():
    """Main verification flow"""
    print("\n" + "="*70)
    print("RTL VERIFICATION CHECKER")
    print("="*70 + "\n")
    
    # Parse command line arguments
    if len(sys.argv) < 3:
        print("Usage: python verify_results.py <rtl_output_file> <golden_reference_file>")
        print("\nExample:")
        print("  python verify_results.py ../sim/rtl_output.txt ../sim/simple_case.json")
        sys.exit(1)
    
    rtl_file = sys.argv[1]
    golden_file = sys.argv[2]
    
    # Optional: tolerance in LSB
    tolerance = int(sys.argv[3]) if len(sys.argv) > 3 else 2
    
    print(f"RTL output file: {rtl_file}")
    print(f"Golden reference file: {golden_file}")
    print(f"Tolerance: {tolerance} LSB\n")
    
    # Create checker
    checker = VerificationChecker(tolerance_lsb=tolerance)
    
    # Load files
    print("Loading RTL results...")
    rtl_results = checker.load_rtl_results(rtl_file)
    if rtl_results is None:
        print("ERROR: Failed to load RTL results")
        sys.exit(1)
    
    print("Loading golden reference...")
    with open(golden_file, 'r') as f:
        golden_data = json.load(f)
    
    # Compare
    passed = checker.compare_test_case(rtl_results, golden_data)
    
    # Generate report
    checker.generate_report('verification_report.txt')
    
    # Exit status
    if passed:
        print("\n" + "="*70)
        print("✓ VERIFICATION PASSED")
        print("="*70 + "\n")
        sys.exit(0)
    else:
        print("\n" + "="*70)
        print("✗ VERIFICATION FAILED")
        print("="*70 + "\n")
        sys.exit(1)


if __name__ == "__main__":
    main()
