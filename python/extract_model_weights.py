"""
Extract Trained Model Weights
Extracts Conv1D weights from a trained TCNet/ATCNet model for RTL verification
"""

import numpy as np
import json
import os
import sys
from pathlib import Path

# Try to import keras/tensorflow
try:
    from tensorflow import keras
    from keras.models import load_model
    KERAS_AVAILABLE = True
except ImportError:
    print("WARNING: TensorFlow/Keras not available")
    print("Install with: pip install tensorflow keras")
    KERAS_AVAILABLE = False


def float_to_fixed(val, frac_bits=8):
    """Convert float to fixed-point integer"""
    return int(round(val * (2 ** frac_bits)))


def extract_conv1d_layers(model):
    """Extract all Conv1D layers from model"""
    conv_layers = []
    
    for layer in model.layers:
        if isinstance(layer, keras.layers.Conv1D):
            weights = layer.get_weights()
            
            # Get weights and bias
            kernel = weights[0]  # Shape: (kernel_size, in_channels, out_channels)
            bias = weights[1] if len(weights) > 1 else None
            
            layer_info = {
                'name': layer.name,
                'type': 'Conv1D',
                'kernel_size': layer.kernel_size[0],
                'filters': layer.filters,
                'dilation_rate': layer.dilation_rate[0],
                'padding': layer.padding,
                'use_bias': layer.use_bias,
                'activation': layer.activation.__name__,
                'kernel_shape': list(kernel.shape),
                'kernel': kernel.tolist(),
                'bias': bias.tolist() if bias is not None else None
            }
            
            conv_layers.append(layer_info)
            
            print(f"Found {layer.name}:")
            print(f"  Kernel shape: {kernel.shape}")
            print(f"  Dilation: {layer.dilation_rate[0]}")
            print(f"  Filters: {layer.filters}")
            print()
    
    return conv_layers


def convert_to_fixed_point(conv_layers, frac_bits=8):
    """Convert all weights to fixed-point"""
    fixed_layers = []
    
    for layer in conv_layers:
        fixed_layer = layer.copy()
        
        # Convert kernel
        kernel_float = np.array(layer['kernel'])
        kernel_fixed = [[
            [float_to_fixed(kernel_float[k, i, o], frac_bits) 
             for o in range(kernel_float.shape[2])]
            for i in range(kernel_float.shape[1])]
            for k in range(kernel_float.shape[0])]
        
        fixed_layer['kernel_fixed'] = kernel_fixed
        
        # Convert bias if present
        if layer['bias'] is not None:
            bias_float = np.array(layer['bias'])
            bias_fixed = [float_to_fixed(b, frac_bits) for b in bias_float]
            fixed_layer['bias_fixed'] = bias_fixed
        
        fixed_layers.append(fixed_layer)
    
    return fixed_layers


def find_tcn_blocks(conv_layers):
    """Group Conv1D layers into TCN blocks based on dilation pattern"""
    blocks = []
    current_block = []
    current_dilation = 1
    
    for layer in conv_layers:
        dilation = layer['dilation_rate']
        
        # Start new block if dilation resets or pattern changes
        if dilation == 1 and len(current_block) > 0:
            blocks.append(current_block)
            current_block = []
        
        current_block.append(layer)
        current_dilation = dilation
    
    if len(current_block) > 0:
        blocks.append(current_block)
    
    return blocks


def generate_rtl_test_vectors(model_path, output_dir='../sim', frac_bits=8):
    """Main function to generate RTL test vectors from trained model"""
    
    if not KERAS_AVAILABLE:
        print("ERROR: Cannot load model without TensorFlow/Keras")
        return False
    
    print("="*70)
    print("Extracting Trained Model Weights for RTL Verification")
    print("="*70)
    print()
    
    # Load model
    print(f"Loading model from: {model_path}")
    try:
        model = load_model(model_path, compile=False)
        print(f"✓ Model loaded successfully")
        print(f"  Total layers: {len(model.layers)}")
        print()
    except Exception as e:
        print(f"ERROR: Failed to load model: {e}")
        return False
    
    # Extract Conv1D layers
    print("Extracting Conv1D layers...")
    conv_layers = extract_conv1d_layers(model)
    print(f"✓ Found {len(conv_layers)} Conv1D layers")
    print()
    
    # Convert to fixed-point
    print(f"Converting to Q{16-frac_bits}.{frac_bits} fixed-point...")
    fixed_layers = convert_to_fixed_point(conv_layers, frac_bits)
    print(f"✓ Conversion complete")
    print()
    
    # Identify TCN blocks
    print("Identifying TCN block structure...")
    tcn_blocks = find_tcn_blocks(conv_layers)
    print(f"✓ Found {len(tcn_blocks)} TCN blocks")
    for i, block in enumerate(tcn_blocks):
        dilations = [layer['dilation_rate'] for layer in block]
        print(f"  Block {i+1}: {len(block)} layers, dilations={dilations}")
    print()
    
    # Create output directory
    os.makedirs(output_dir, exist_ok=True)
    
    # Save all layers
    output = {
        'model_path': model_path,
        'total_conv_layers': len(conv_layers),
        'tcn_blocks': len(tcn_blocks),
        'fixed_point': {
            'total_bits': 16,
            'frac_bits': frac_bits
        },
        'layers': fixed_layers
    }
    
    output_file = os.path.join(output_dir, 'trained_model_weights.json')
    with open(output_file, 'w') as f:
        json.dump(output, f, indent=2)
    print(f"✓ Saved all weights to: {output_file}")
    
    # Save individual TCN blocks for testing
    for block_idx, block in enumerate(tcn_blocks):
        block_file = os.path.join(output_dir, f'tcn_block_{block_idx+1}.json')
        block_data = {
            'block_index': block_idx + 1,
            'num_layers': len(block),
            'layers': [fixed_layers[conv_layers.index(layer)] for layer in block]
        }
        with open(block_file, 'w') as f:
            json.dump(block_data, f, indent=2)
        print(f"✓ Saved TCN block {block_idx+1} to: {block_file}")
    
    # Generate SystemVerilog include file with weight arrays
    sv_file = os.path.join(output_dir, 'model_weights.svh')
    generate_systemverilog_weights(fixed_layers, sv_file, frac_bits)
    print(f"✓ Saved SystemVerilog weights to: {sv_file}")
    
    print()
    print("="*70)
    print("Weight Extraction Complete!")
    print("="*70)
    print()
    print("Next steps:")
    print("1. Review generated JSON files in", output_dir)
    print("2. Use these weights in your testbench")
    print("3. Run verification with real trained model weights")
    print()
    
    return True


def generate_systemverilog_weights(layers, output_file, frac_bits):
    """Generate SystemVerilog include file with weight arrays"""
    
    with open(output_file, 'w') as f:
        f.write("// Auto-generated trained model weights\n")
        f.write("// Generated by extract_model_weights.py\n")
        f.write(f"// Fixed-point format: Q{16-frac_bits}.{frac_bits}\n\n")
        
        for layer_idx, layer in enumerate(layers):
            layer_name = layer['name'].replace('/', '_')
            
            f.write(f"\n// Layer: {layer['name']}\n")
            f.write(f"// Kernel size: {layer['kernel_size']}, ")
            f.write(f"Filters: {layer['filters']}, ")
            f.write(f"Dilation: {layer['dilation_rate']}\n")
            
            # Kernel dimensions
            kernel_shape = layer['kernel_shape']
            f.write(f"parameter int {layer_name}_KERNEL_SIZE = {kernel_shape[0]};\n")
            f.write(f"parameter int {layer_name}_IN_CHANNELS = {kernel_shape[1]};\n")
            f.write(f"parameter int {layer_name}_OUT_CHANNELS = {kernel_shape[2]};\n")
            
            # Kernel weights (as packed array)
            f.write(f"\nparameter logic [15:0] {layer_name}_KERNEL")
            f.write(f"[0:{kernel_shape[0]-1}]")
            f.write(f"[0:{kernel_shape[1]-1}]")
            f.write(f"[0:{kernel_shape[2]-1}] = '{{\n")
            
            kernel_fixed = layer['kernel_fixed']
            for k in range(kernel_shape[0]):
                f.write("  {\n")
                for i in range(kernel_shape[1]):
                    f.write("    {")
                    for o in range(kernel_shape[2]):
                        val = kernel_fixed[k][i][o]
                        f.write(f"16'h{val & 0xFFFF:04x}")
                        if o < kernel_shape[2] - 1:
                            f.write(", ")
                    f.write("}")
                    if i < kernel_shape[1] - 1:
                        f.write(",")
                    f.write("\n")
                f.write("  }")
                if k < kernel_shape[0] - 1:
                    f.write(",")
                f.write("\n")
            
            f.write("};\n")
            
            # Bias if present
            if layer['bias_fixed'] is not None:
                f.write(f"\nparameter logic [15:0] {layer_name}_BIAS")
                f.write(f"[0:{len(layer['bias_fixed'])-1}] = '{{\n  ")
                
                for b_idx, b in enumerate(layer['bias_fixed']):
                    f.write(f"16'h{b & 0xFFFF:04x}")
                    if b_idx < len(layer['bias_fixed']) - 1:
                        f.write(", ")
                        if (b_idx + 1) % 8 == 0:
                            f.write("\n  ")
                
                f.write("\n};\n")


def main():
    if len(sys.argv) < 2:
        print("Usage: python extract_model_weights.py <model_path> [output_dir] [frac_bits]")
        print()
        print("Example:")
        print("  python extract_model_weights.py ./trained_model.h5 ../sim 8")
        print()
        print("Arguments:")
        print("  model_path  - Path to trained Keras/TensorFlow model (.h5 or SavedModel)")
        print("  output_dir  - Output directory (default: ../sim)")
        print("  frac_bits   - Fractional bits for fixed-point (default: 8)")
        sys.exit(1)
    
    model_path = sys.argv[1]
    output_dir = sys.argv[2] if len(sys.argv) > 2 else '../sim'
    frac_bits = int(sys.argv[3]) if len(sys.argv) > 3 else 8
    
    if not os.path.exists(model_path):
        print(f"ERROR: Model file not found: {model_path}")
        sys.exit(1)
    
    success = generate_rtl_test_vectors(model_path, output_dir, frac_bits)
    
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
