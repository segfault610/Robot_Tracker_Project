import numpy as np
import os

print("--- Python Data Generator Started ---")

# --- 1. Simulation Parameters ---
N_STEPS = 200        # Run the simulation for 200 time steps
DT = 0.1             # Time step in seconds
# IMPORTANT: This controls the Verilog fixed-point precision.
# We will treat 1000 as "1.0" in Verilog.
SCALE_FACTOR = 1000  

# --- 2. Define the "Truth" (a 3D spiral path) ---
time = np.linspace(0, N_STEPS * DT, N_STEPS)
true_x = 5 * np.cos(time)
true_y = 5 * np.sin(time)
true_z = 0.5 * time  # Rises slowly

# --- 3. Define the "Noise" Models ---

# "Drifty Motors" (Process Noise)
# Our physics model (A=Identity) is simple, it thinks the robot isn't moving.
# This noise represents the robot's *actual* un-modelled drift.
drift_noise_std = 0.2  # <--- Tunable
drift_x = np.cumsum(np.random.randn(N_STEPS) * drift_noise_std)
drift_y = np.cumsum(np.random.randn(N_STEPS) * drift_noise_std)
drift_z = np.cumsum(np.random.randn(N_STEPS) * drift_noise_std)

drifty_path_x = true_x + drift_x
drifty_path_y = true_y + drift_y
drifty_path_z = true_z + drift_z

# "Noisy Camera" (Measurement Noise)
# This is the "junky" data we will feed to the FSM
meas_noise_std = 0.5 # <--- Tunable
noisy_x = true_x + np.random.randn(N_STEPS) * meas_noise_std
noisy_y = true_y + np.random.randn(N_STEPS) * meas_noise_std
noisy_z = true_z + np.random.randn(N_STEPS) * meas_noise_std

# --- 4. Calculate our "Magic Number" (Kalman Gain) ---
# This is a simplified 1D Kalman gain calculation.
# K = ProcessError / (ProcessError + MeasurementError)
Q_val = drift_noise_std**2  
R_val = meas_noise_std**2   
K_val = Q_val / (Q_val + R_val) # This is the "steady-state" gain

# We scale it to an integer for Verilog
K_scaled = int(K_val * 1000) 

print(f"Calculated K value (float): {K_val:.4f}")
print(f"Scaled K value (for Verilog): {K_scaled}") # This is the number we need!

# --- 5. Write to Text Files ---
# We write the files that our Verilog testbench will read.
# We only need to write the "noisy camera" data.
output_dir = "." # Put files in the current directory

def write_to_file(filename, x, y, z):
    with open(os.path.join(output_dir, filename), 'w') as f:
        for i in range(N_STEPS):
            # Format: "x y z" on each line, scaled to integer
            # We use %d to format as integer
            f.write("%d %d %d\n" % (
                int(x[i] * SCALE_FACTOR), 
                int(y[i] * SCALE_FACTOR), 
                int(z[i] * SCALE_FACTOR)
            ))
    print(f"Successfully wrote {filename}")

# Create the file for our Verilog simulation
write_to_file("noisy_camera.txt", noisy_x, noisy_y, noisy_z)

# Create the files for our final Python plot
write_to_file("true_path.txt", true_x, true_y, true_z)
write_to_file("drifty_motors.txt", drifty_path_x, drifty_path_y, drifty_path_z)

print("--- Python Data Generation Complete! ---")