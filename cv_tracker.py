import cv2
import numpy as np
# import serial  <-- Removed
# import struct  <-- Removed
import time
import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d import Axes3D

# --- 1. User Configuration ---
# SERIAL_PORT = "COM3"  <-- Removed
# BAUD_RATE = 115200    <-- Removed
SCALE_FACTOR = 1000.0 # Must match the "1000" scale in your Verilog
HISTORY_LEN = 100     # How many points to show on the plot

# --- 2. Color Tracking Configuration (Example: Bright Red) ---
# Use an "HSV Color Picker" online to find these values for your object
COLOR_LOWER = np.array([0, 150, 150])
COLOR_UPPER = np.array([10, 255, 255])
# --- (End Configuration) ---


# --- 3. "Virtual FPGA" - Software Kalman Filter ---
# We re-create the FSM's math in Python.

# Get the K-value from your Python data generator (137 / 1000)
K_val = 0.137
K_matrix = np.diag([K_val, K_val, K_val])
A_matrix = np.identity(3)
H_matrix = np.identity(3)

# This is our persistent "x_state_x/y/z" registers
x_state = np.array([0, 0, 0], dtype=float).reshape(3, 1)

def run_software_kalman_filter(noisy_z_tuple):
    """
    This function *is* your Verilog FSM, but written in Python.
    It takes the noisy (x,y,z) and returns the clean (x,y,z).
    """
    global x_state # Use the persistent state registers
    
    # Convert noisy tuple (x,y,z) to a 3x1 vector
    z_k = np.array(noisy_z_tuple, dtype=float).reshape(3, 1)
    
    # --- This is the FSM logic ---
    
    # 1. PREDICT Step (x = A*x)
    # (Our A is Identity, so x_state = x_state)
    x_state = A_matrix @ x_state
    
    # 2. UPDATE Step (The 4 math steps from the FSM)
    # temp1 = H * x_state
    temp1_Hx = H_matrix @ x_state
    
    # temp2 = z_k - temp1 (The error)
    temp2_err = z_k - temp1_Hx
    
    # temp3 = K * temp2 (The correction)
    temp3_corr = K_matrix @ temp2_err
    
    # x_state = x_state + temp3 (The new, clean state)
    x_state = x_state + temp3_corr
    
    # Return the clean (x, y, z) as a tuple
    return (x_state[0, 0], x_state[1, 0], x_state[2, 0])
# --- (End of Virtual FPGA) ---


# def setup_serial():  <-- Removed
# ...
# def send_to_fpga(ser, x, y, z): <-- Removed
# ...
# def receive_from_fpga(ser): <-- Removed
# ...

def find_object(frame):
    """ Finds the largest colored object in the frame. """
    # Blur, convert to HSV
    blurred = cv2.GaussianBlur(frame, (11, 11), 0)
    hsv = cv2.cvtColor(blurred, cv2.COLOR_BGR2HSV)

    # Create a mask for the color, then clean it up
    mask = cv2.inRange(hsv, COLOR_LOWER, COLOR_UPPER)
    mask = cv2.erode(mask, None, iterations=2)
    mask = cv2.dilate(mask, None, iterations=2)

    # Find contours
    contours, _ = cv2.findContours(mask.copy(), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    
    if len(contours) > 0:
        # Find the largest contour
        c = max(contours, key=cv2.contourArea)
        ((x, y), radius) = cv2.minEnclosingCircle(c)
        
        if radius > 10: # Only track if it's a decent size
            # Draw the circle on the frame
            cv2.circle(frame, (int(x), int(y)), int(radius), (0, 255, 255), 2)
            cv2.circle(frame, (int(x), int(y)), 5, (0, 0, 255), -1)
            
            # --- Generate Noisy (x, y, z) ---
            # Center X/Y. Frame is (480, 640)
            noisy_x = (x - 320) / 320.0  # Range -1.0 to 1.0
            noisy_y = (240 - y) / 240.0  # Range -1.0 to 1.0
            
            # Estimate Z based on radius. This is VERY noisy.
            # (This 3000.0 is a "magic number", tune it for your camera/object)
            noisy_z = (3000.0 / radius) / 100.0 # Arbitrary Z scale
            
            return frame, (noisy_x, noisy_y, noisy_z)
            
    return frame, None

def main():
    # ser = setup_serial()  <-- Removed
    # if ser is None:       <-- Removed
    #     return            <-- Removed

    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("Error: Cannot open webcam.")
        # ser.close()       <-- Removed
        return
        
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)

    # --- Setup Live 3D Plot ---
    plt.ion() # Turn on interactive mode
    fig = plt.figure(figsize=(10, 8))
    ax = fig.add_subplot(111, projection='3d')
    ax.set_title("Real-Time 3D Kalman Filter (Software Sim)")
    ax.set_xlabel("X Position")
    ax.set_ylabel("Y Position")
    ax.set_zlabel("Z Position (Estimated)")
    
    noisy_history = []
    clean_history = []

    # --- Main Loop ---
    while True:
        ret, frame = cap.read()
        if not ret:
            break
        
        frame = cv2.flip(frame, 1) # Flip horizontally
        frame, noisy_coords = find_object(frame)
        
        clean_coords = None
        
        if noisy_coords:
            # --- This block is now much simpler ---
            
            # 1. Run the filter in software
            clean_coords = run_software_kalman_filter(noisy_coords)

            # 2. Update histories
            noisy_history.append(noisy_coords)
            clean_history.append(clean_coords)

            # 3. Trim history
            if len(noisy_history) > HISTORY_LEN:
                noisy_history.pop(0)
            if len(clean_history) > HISTORY_LEN:
                clean_history.pop(0)

        # --- Update Plot ---
        if len(noisy_history) > 1:
            ax.clear()
            ax.set_title("Real-Time 3D Kalman Filter (Software Sim)")
            ax.set_xlabel("X Position")
            ax.set_ylabel("Y Position")
            ax.set_zlabel("Z Position (Estimated)")
            
            # Plot noisy data (red dots)
            n_data = np.array(noisy_history)
            ax.plot(n_data[:,0], n_data[:,1], n_data[:,2], 'r.', label="Noisy Camera (CV)")
            
            # Plot filtered data (blue line)
            if len(clean_history) > 1:
                 c_data = np.array(clean_history)
                 ax.plot(c_data[:,0], c_data[:,1], c_data[:,2], 'b-', linewidth=3, label="Software Kalman Brain")

            ax.legend()
            plt.pause(0.001) # Update the plot

        # Show the camera feed
        cv2.imshow("FPGA Object Tracker", frame)

        # Quit on 'q'
        if cv2.waitKey(1) & 0xFF == ord('q'):
            break

    # --- Cleanup ---
    cap.release()
    cv2.destroyAllWindows()
    # ser.close()  <-- Removed
    plt.ioff()
    plt.show() # Show final plot
    print("Simulation finished. Exiting.")

if __name__ == "__main__":
    main()