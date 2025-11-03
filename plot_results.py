import numpy as np
import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d import Axes3D # Required for 3D plotting
import os

# --- Configuration ---
SCALE_FACTOR = 1000.0  # Must match the value in your Python/Verilog
PROJECT_DIR = "."      # Directory where your .txt files are

# --- Helper Function ---
def load_data(filename, delimiter=' '):
    """
    Loads data from a text file, skipping the header if it exists.
    Un-scales the data back to floating-point numbers.
    """
    filepath = os.path.join(PROJECT_DIR, filename)
    if not os.path.exists(filepath):
        print(f"ERROR: File not found: {filepath}")
        return None
    
    print(f"Loading {filename}...")
    try:
        # Try to load, assuming a header (like verilog_filtered.txt)
        data = np.loadtxt(filepath, delimiter=delimiter, skiprows=1)
    except Exception:
        # If that fails, load with no header (like true_path.txt)
        data = np.loadtxt(filepath, delimiter=delimiter)
        
    # Un-scale the data from integer back to float
    return data / SCALE_FACTOR

# --- Load All Data ---
true_data = load_data("true_path.txt", delimiter=' ')
noisy_data = load_data("noisy_camera.txt", delimiter=' ')
verilog_data = load_data("verilog_filtered.txt", delimiter=',') # IMPORTANT: This file uses commas

if true_data is None or noisy_data is None or verilog_data is None:
    print("\nOne or more files failed to load. Aborting plot.")
else:
    print("\nAll data loaded. Generating 3D plot...")

    # --- Create the 3D Plot ---
    fig = plt.figure(figsize=(12, 10))
    ax = fig.add_subplot(111, projection='3d')

    # 1. Plot the "Problem" (Noisy Camera)
    # We plot this as small, scattered 'x' markers
    ax.plot(noisy_data[:, 0], noisy_data[:, 1], noisy_data[:, 2], 
            'rx', markersize=2, label='Noisy Camera')

    # 2. Plot the "Truth" (Perfect Spiral)
    # We plot this as a thin, green line
    ax.plot(true_data[:, 0], true_data[:, 1], true_data[:, 2], 
            'g-', linewidth=2, label='True Path')

    # 3. Plot "YOUR Solution" (Verilog Filtered)
    # We plot this as a bold, blue line
    ax.plot(verilog_data[:, 0], verilog_data[:, 1], verilog_data[:, 2], 
            'b-', linewidth=3, label='Verilog "Kalman Brain"')

    # --- Add Labels and Title ---
    ax.set_title('3D Robot Arm Tracker: Verilog FSM Performance', fontsize=16)
    ax.set_xlabel('X Position (m)')
    ax.set_ylabel('Y Position (m)')
    ax.set_zlabel('Z Position (m)')
    
    # Add a legend to identify the lines
    ax.legend(fontsize=12)
    
    # Set a nice viewing angle
    ax.view_init(elev=20., azim=-65)
    
    print("Showing plot. Close the plot window to finish.")
    plt.show()