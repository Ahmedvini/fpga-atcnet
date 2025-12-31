"""
Test Vector Generator for Temporal Convolution Verification
Extracts weights and generates golden reference outputs from TCNet model
"""

import numpy as np
import tensorflow as tf
from tensorflow import keras
from keras.models import Model
import json
import os

# Fixed-point configuration
FIXED_POINT_BITS = 16
FIXED_POINT_FRAC = 8  # Q8.8 format


def float_to_fixed(val, frac_bits=FIXED_POINT_FRAC):
    """Convert float to fixed-point integer representation"""
    return int(round(val * (2 ** frac_bits)))


def fixed_to_float(val, frac_bits=FIXED_POINT_FRAC):
    """Convert fixed-point integer back to float"""
    return val / (2 ** frac_bits)


class TemporalConvTestGenerator:
    """Generate test vectors for temporal convolution verification"""
    
    def __init__(self, model_path=None):
        self.model = None
        self.conv_layers = []
        self.test_vectors = {}
        
        if model_path and os.path.exists(model_path):
            self.load_model(model_path)
    
    def load_model(self, model_path):
        """Load trained model"""
        print(f"Loading model from {model_path}")
        self.model = keras.models.load_model(model_path)
        self.extract_conv_layers()
    
    def extract_conv_layers(self):
        """Extract Conv1D layers from the model"""
        if self.model is None:
            print("No model loaded")
            return
        
        for layer in self.model.layers:
            if isinstance(layer, keras.layers.Conv1D):
                weights, bias = layer.get_weights() if layer.use_bias else (layer.get_weights()[0], None)
                self.conv_layers.append({
                    'name': layer.name,
                    'weights': weights,
                    'bias': bias,
                    'kernel_size': layer.kernel_size[0],
                    'filters': layer.filters,
                    'dilation_rate': layer.dilation_rate[0],
                    'padding': layer.padding,
                    'activation': layer.activation.__name__
                })
                print(f"Found Conv1D: {layer.name}, kernel_size={layer.kernel_size[0]}, "
                      f"filters={layer.filters}, dilation={layer.dilation_rate[0]}")
    
    def generate_simple_test_case(self, seq_length=16, input_channels=32, 
                                 kernel_size=4, output_channels=32, dilation=1):
        """
        Generate a simple test case with known inputs
        This creates a minimal 1D temporal convolution test
        """
        print(f"\nGenerating simple test case:")
        print(f"  Input: [{seq_length}, {input_channels}]")
        print(f"  Kernel: [{kernel_size}, {input_channels}, {output_channels}]")
        print(f"  Dilation: {dilation}")
        
        # Create simple input sequence (ramp pattern for easy verification)
        input_seq = np.zeros((1, seq_length, input_channels), dtype=np.float32)
        for t in range(seq_length):
            for c in range(input_channels):
                input_seq[0, t, c] = (t * input_channels + c) * 0.01
        
        # Create simple kernel (identity-like pattern)
        kernel = np.zeros((kernel_size, input_channels, output_channels), dtype=np.float32)
        for k in range(kernel_size):
            for i in range(min(input_channels, output_channels)):
                kernel[k, i, i] = 1.0 / kernel_size  # Averaging kernel
        
        # Bias
        bias = np.zeros(output_channels, dtype=np.float32)
        
        # Compute expected output using manual convolution
        output_seq = self.compute_conv1d_manual(input_seq[0], kernel, bias, dilation, 'causal')
        
        # Convert to fixed-point
        input_fixed = np.vectorize(float_to_fixed)(input_seq[0])
        kernel_fixed = np.vectorize(float_to_fixed)(kernel)
        bias_fixed = np.vectorize(float_to_fixed)(bias)
        output_fixed = np.vectorize(float_to_fixed)(output_seq)
        
        test_case = {
            'name': 'simple_temporal_conv',
            'config': {
                'seq_length': seq_length,
                'input_channels': input_channels,
                'output_channels': output_channels,
                'kernel_size': kernel_size,
                'dilation_rate': dilation,
                'padding': 'causal'
            },
            'input_float': input_seq[0].tolist(),
            'kernel_float': kernel.tolist(),
            'bias_float': bias.tolist(),
            'output_float': output_seq.tolist(),
            'input_fixed': input_fixed.tolist(),
            'kernel_fixed': kernel_fixed.tolist(),
            'bias_fixed': bias_fixed.tolist(),
            'output_fixed': output_fixed.tolist(),
            'fixed_point_config': {
                'total_bits': FIXED_POINT_BITS,
                'frac_bits': FIXED_POINT_FRAC
            }
        }
        
        self.test_vectors['simple_case'] = test_case
        return test_case
    
    def compute_conv1d_manual(self, input_seq, kernel, bias, dilation, padding):
        """
        Manually compute 1D convolution with dilation for verification
        
        Args:
            input_seq: [seq_length, input_channels]
            kernel: [kernel_size, input_channels, output_channels]
            bias: [output_channels]
            dilation: int
            padding: 'causal' or 'valid'
        
        Returns:
            output: [output_seq_length, output_channels]
        """
        seq_length, input_channels = input_seq.shape
        kernel_size, _, output_channels = kernel.shape
        
        # Calculate effective kernel size with dilation
        effective_kernel_size = (kernel_size - 1) * dilation + 1
        
        if padding == 'causal':
            # For causal padding, output length = input length
            output_length = seq_length
            # Pad the input at the beginning
            pad_amount = effective_kernel_size - 1
            padded_input = np.pad(input_seq, ((pad_amount, 0), (0, 0)), mode='constant')
        elif padding == 'valid':
            output_length = seq_length - effective_kernel_size + 1
            padded_input = input_seq
        else:
            output_length = seq_length
            padded_input = input_seq
        
        output = np.zeros((output_length, output_channels), dtype=np.float32)
        
        # Perform convolution
        for t in range(output_length):
            for out_c in range(output_channels):
                acc = bias[out_c] if bias is not None else 0.0
                
                for k in range(kernel_size):
                    # Calculate dilated position
                    pos = t + k * dilation
                    if pos < padded_input.shape[0]:
                        for in_c in range(input_channels):
                            acc += padded_input[pos, in_c] * kernel[k, in_c, out_c]
                
                output[t, out_c] = acc
        
        return output
    
    def generate_tcn_block_test(self, depth=2, kernel_size=4, filters=32, 
                                input_dimension=32, seq_length=32):
        """
        Generate test case for a full TCN block (multiple dilated convolutions)
        Simulates the TCFN structure from the model
        """
        print(f"\nGenerating TCN block test case:")
        print(f"  Depth: {depth}, Kernel size: {kernel_size}, Filters: {filters}")
        
        # Input sequence
        input_seq = np.random.randn(1, seq_length, input_dimension).astype(np.float32) * 0.1
        
        test_case = {
            'name': 'tcn_block',
            'config': {
                'depth': depth,
                'kernel_size': kernel_size,
                'filters': filters,
                'input_dimension': input_dimension,
                'seq_length': seq_length
            },
            'layers': []
        }
        
        current_output = input_seq[0]
        
        # First conv block (dilation = 1)
        for conv_idx in range(2):  # Two convs per block
            kernel = np.random.randn(kernel_size, current_output.shape[1], filters).astype(np.float32) * 0.1
            bias = np.random.randn(filters).astype(np.float32) * 0.01
            
            output = self.compute_conv1d_manual(current_output, kernel, bias, dilation=1, padding='causal')
            
            # Apply ELU activation (simplified)
            output = np.where(output > 0, output, np.exp(output) - 1)
            
            test_case['layers'].append({
                'conv_idx': conv_idx,
                'dilation': 1,
                'input_shape': list(current_output.shape),
                'kernel_fixed': np.vectorize(float_to_fixed)(kernel).tolist(),
                'bias_fixed': np.vectorize(float_to_fixed)(bias).tolist(),
                'output_fixed': np.vectorize(float_to_fixed)(output).tolist()
            })
            
            current_output = output
        
        # Residual connection
        if input_dimension == filters:
            current_output = current_output + input_seq[0]
        
        # Subsequent blocks with increasing dilation
        for depth_idx in range(1, depth):
            dilation = 2 ** depth_idx
            
            for conv_idx in range(2):
                kernel = np.random.randn(kernel_size, current_output.shape[1], filters).astype(np.float32) * 0.1
                bias = np.random.randn(filters).astype(np.float32) * 0.01
                
                output = self.compute_conv1d_manual(current_output, kernel, bias, dilation=dilation, padding='causal')
                output = np.where(output > 0, output, np.exp(output) - 1)
                
                test_case['layers'].append({
                    'conv_idx': conv_idx,
                    'dilation': dilation,
                    'input_shape': list(current_output.shape),
                    'kernel_fixed': np.vectorize(float_to_fixed)(kernel).tolist(),
                    'bias_fixed': np.vectorize(float_to_fixed)(bias).tolist(),
                    'output_fixed': np.vectorize(float_to_fixed)(output).tolist()
                })
                
                current_output = output
        
        test_case['final_output_fixed'] = np.vectorize(float_to_fixed)(current_output).tolist()
        test_case['input_fixed'] = np.vectorize(float_to_fixed)(input_seq[0]).tolist()
        
        self.test_vectors['tcn_block'] = test_case
        return test_case
    
    def generate_streaming_test(self, seq_length=64, input_channels=32, 
                               kernel_size=4, output_channels=32):
        """
        Generate streaming test case - one sample at a time
        This tests the shift register behavior
        """
        print(f"\nGenerating streaming test case:")
        print(f"  Sequence length: {seq_length}")
        
        # Create input sequence
        input_seq = np.random.randn(seq_length, input_channels).astype(np.float32) * 0.1
        
        # Simple kernel
        kernel = np.random.randn(kernel_size, input_channels, output_channels).astype(np.float32) * 0.1
        bias = np.zeros(output_channels, dtype=np.float32)
        
        # Compute full output
        full_output = self.compute_conv1d_manual(input_seq, kernel, bias, dilation=1, padding='causal')
        
        test_case = {
            'name': 'streaming_test',
            'config': {
                'seq_length': seq_length,
                'input_channels': input_channels,
                'output_channels': output_channels,
                'kernel_size': kernel_size
            },
            'kernel_fixed': np.vectorize(float_to_fixed)(kernel).tolist(),
            'bias_fixed': np.vectorize(float_to_fixed)(bias).tolist(),
            'streaming_samples': []
        }
        
        # Generate per-cycle expectations
        for t in range(seq_length):
            sample = {
                'cycle': t,
                'input_fixed': np.vectorize(float_to_fixed)(input_seq[t]).tolist(),
                'expected_output_fixed': np.vectorize(float_to_fixed)(full_output[t]).tolist(),
                'valid': t >= (kernel_size - 1)  # Valid after kernel fills
            }
            test_case['streaming_samples'].append(sample)
        
        self.test_vectors['streaming_test'] = test_case
        return test_case
    
    def save_test_vectors(self, output_dir='../sim'):
        """Save test vectors to JSON files"""
        if not os.path.exists(output_dir):
            os.makedirs(output_dir)
        
        for test_name, test_data in self.test_vectors.items():
            filepath = os.path.join(output_dir, f'{test_name}.json')
            with open(filepath, 'w') as f:
                json.dump(test_data, f, indent=2)
            print(f"Saved test vectors to {filepath}")
        
        # Save configuration
        config = {
            'fixed_point': {
                'total_bits': FIXED_POINT_BITS,
                'frac_bits': FIXED_POINT_FRAC
            },
            'test_cases': list(self.test_vectors.keys())
        }
        
        config_path = os.path.join(output_dir, 'test_config.json')
        with open(config_path, 'w') as f:
            json.dump(config, f, indent=2)
        print(f"Saved configuration to {config_path}")
    
    def generate_systemverilog_header(self, output_dir='../sim'):
        """Generate SystemVerilog header with test parameters"""
        if not os.path.exists(output_dir):
            os.makedirs(output_dir)
        
        header_content = f"""// Auto-generated test vector parameters
// Generated by generate_test_vectors.py

`ifndef TEST_PARAMS_SVH
`define TEST_PARAMS_SVH

// Fixed-point configuration
parameter int FIXED_TOTAL_BITS = {FIXED_POINT_BITS};
parameter int FIXED_FRAC_BITS = {FIXED_POINT_FRAC};

// Test case counts
"""
        
        for test_name, test_data in self.test_vectors.items():
            if 'config' in test_data:
                config = test_data['config']
                header_content += f"\n// {test_name.upper()} parameters\n"
                for key, value in config.items():
                    param_name = f"{test_name.upper()}_{key.upper()}"
                    header_content += f"parameter int {param_name} = {value};\n"
        
        header_content += "\n`endif // TEST_PARAMS_SVH\n"
        
        filepath = os.path.join(output_dir, 'test_params.svh')
        with open(filepath, 'w') as f:
            f.write(header_content)
        print(f"Saved SystemVerilog header to {filepath}")


def main():
    """Main test vector generation"""
    print("=" * 60)
    print("Temporal Convolution Test Vector Generator")
    print("=" * 60)
    
    generator = TemporalConvTestGenerator()
    
    # Generate different test cases
    print("\n[1/4] Generating simple test case...")
    generator.generate_simple_test_case(
        seq_length=16,
        input_channels=32,
        kernel_size=4,
        output_channels=32,
        dilation=1
    )
    
    print("\n[2/4] Generating streaming test case...")
    generator.generate_streaming_test(
        seq_length=32,
        input_channels=32,
        kernel_size=4,
        output_channels=32
    )
    
    print("\n[3/4] Generating TCN block test case...")
    generator.generate_tcn_block_test(
        depth=2,
        kernel_size=4,
        filters=32,
        input_dimension=32,
        seq_length=32
    )
    
    print("\n[4/4] Saving test vectors...")
    generator.save_test_vectors()
    generator.generate_systemverilog_header()
    
    print("\n" + "=" * 60)
    print("Test vector generation complete!")
    print("=" * 60)
    print(f"\nGenerated {len(generator.test_vectors)} test cases:")
    for test_name in generator.test_vectors.keys():
        print(f"  - {test_name}")
    print("\nFiles saved to ../sim/")


if __name__ == "__main__":
    main()
