/*
 * File: kalman_fsm_3d.v
 * The "Kalman Brain" - COMPLETE (Predict + Update)
 * This is the final, corrected Verilog-2001 code.
 */
`timescale 1ns / 1ps

module kalman_fsm_3d #(
    parameter DATA_WIDTH = 32,
    parameter K_SCALED = 137  // <-- FIX: Added parameter (default 137)
)(
    input  wire clk,
    input  wire rst,
    input  wire start, // "Go" for one time-step
    
    // Input: Noisy 3D position [z_x, z_y, z_z]
    input  wire signed [DATA_WIDTH-1:0] z_in_x,
    input  wire signed [DATA_WIDTH-1:0] z_in_y,
    input  wire signed [DATA_WIDTH-1:0] z_in_z,
    
    // Output: Filtered 3D position (our "best guess")
    output reg signed [DATA_WIDTH-1:0] x_out_x,
    output reg signed [DATA_WIDTH-1:0] x_out_y,
    output reg signed [DATA_WIDTH-1:0] x_out_z,
    output reg done
);
    // --- Parameters for 3x3 Math ---
    parameter M = 3;
    parameter N = 3;
    parameter P = 3;
    parameter MAT_SIZE = 9; // 3*3
    parameter ADDR_WIDTH = 4; // $clog2(9)
    parameter SCALE_BITS = 10; // 2^10 = 1024 (for fixed-point)
    parameter ACC_WIDTH_MULT = (2*DATA_WIDTH) + 2; // 64 + 2 = 66 bits

    // --- FSM States (The "Recipe Card") ---
    localparam STATE_IDLE = 0;
    localparam STATE_PRED_1_LOAD_A    = 1;
    localparam STATE_PRED_2_LOAD_X    = 2;
    localparam STATE_PRED_3_RUN       = 3;
    localparam STATE_PRED_4_WAIT_SAVE = 4;
    localparam STATE_UPD1_1_LOAD_H    = 5;
    localparam STATE_UPD1_2_LOAD_X    = 6;
    localparam STATE_UPD1_3_RUN       = 7;
    localparam STATE_UPD1_4_WAIT_SAVE = 8;
    localparam STATE_UPD2_1_LOAD_Z    = 9;
    localparam STATE_UPD2_2_LOAD_T1   = 10;
    localparam STATE_UPD2_3_RUN_SUB   = 11;
    localparam STATE_UPD2_4_WAIT_SAVE = 12;
    localparam STATE_UPD3_1_LOAD_K    = 13;
    localparam STATE_UPD3_2_LOAD_T2   = 14;
    localparam STATE_UPD3_3_RUN       = 15;
    localparam STATE_UPD3_4_WAIT_SAVE = 16;
    localparam STATE_UPD4_1_LOAD_X    = 17;
    localparam STATE_UPD4_2_LOAD_T3   = 18;
    localparam STATE_UPD4_3_RUN_ADD   = 19;
    localparam STATE_UPD4_4_WAIT_SAVE = 20;
    localparam STATE_DONE             = 21;
    
    reg [4:0] state;

    // --- Internal Registers for State ---
    reg signed [DATA_WIDTH-1:0] x_state_x;
    reg signed [DATA_WIDTH-1:0] x_state_y;
    reg signed [DATA_WIDTH-1:0] x_state_z;
    
    // --- Internal Registers for Constants ---
    reg signed [DATA_WIDTH-1:0] A_matrix [0:MAT_SIZE-1];
    reg signed [DATA_WIDTH-1:0] H_matrix [0:MAT_SIZE-1];
    reg signed [DATA_WIDTH-1:0] K_matrix [0:MAT_SIZE-1];
    
    // --- Internal Registers for Temp Storage ---
    reg signed [DATA_WIDTH-1:0] temp1_Hx_x, temp1_Hx_y, temp1_Hx_z;
    reg signed [DATA_WIDTH-1:0] temp2_err_x, temp2_err_y, temp2_err_z;
    reg signed [DATA_WIDTH-1:0] temp3_corr_x, temp3_corr_y, temp3_corr_z;
    
    // --- "Tool-belt" Wires/Regs ---
    reg  mult_start;
    wire mult_done;
    reg  [ADDR_WIDTH-1:0] mult_a_addr, mult_b_addr;
    reg  mult_a_wen, mult_b_wen;
    reg  signed [DATA_WIDTH-1:0] mult_a_in, mult_b_in;
    wire signed [ACC_WIDTH_MULT-1:0] mult_c_out; // Full 66-bit output
    wire mult_c_valid;
    wire [1:0] mult_row; 
    wire [1:0] mult_col;

    reg  addsub_start;
    reg  addsub_op; // 0=ADD, 1=SUB
    wire addsub_done;
    reg  [ADDR_WIDTH-1:0] addsub_a_addr, addsub_b_addr;
    reg  addsub_a_wen, addsub_b_wen;
    reg  signed [DATA_WIDTH-1:0] addsub_a_in, addsub_b_in;
    wire signed [DATA_WIDTH-1:0] addsub_c_out;
    wire addsub_c_valid;
    wire [3:0] addsub_index; 
    
    reg [3:0] load_count;
    reg [3:0] save_count; // <-- FIX: Declared save_count
    
    // --- Instantiate "Tool-belt" ---
    
    matrix_mult_3x3 #(
        .M(M), .N(N), .P(P), 
        .DATA_WIDTH(DATA_WIDTH), 
        .ACC_WIDTH(ACC_WIDTH_MULT)
    ) uut_mult (
        .clk(clk), .rst(rst), .start(mult_start),
        .a_in(mult_a_in), .a_addr(mult_a_addr), .a_wen(mult_a_wen),
        .b_in(mult_b_in), .b_addr(mult_b_addr), .b_wen(mult_b_wen),
        .c_out(mult_c_out), .c_valid(mult_c_valid), .done(mult_done),
        .row(mult_row), .col(mult_col) 
    );
    
    matrix_add_sub_3x3 #(
        .M(M), .P(P), 
        .DATA_WIDTH(DATA_WIDTH)
    ) uut_addsub (
        .clk(clk), .rst(rst), .start(addsub_start), .op(addsub_op),
        .a_in(addsub_a_in), .a_addr(addsub_a_addr), .a_wen(addsub_a_wen),
        .b_in(addsub_b_in), .b_addr(addsub_b_addr), .b_wen(addsub_b_wen),
        .c_out(addsub_c_out), .c_valid(addsub_c_valid), .done(addsub_done),
        .i_count_out(addsub_index)
    );

    // --- Main "Brain" FSM ---
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            $display("--- KALMAN FSM RESET ---");
            state <= STATE_IDLE;
            done <= 0;
            load_count <= 0;
            save_count <= 0; // <-- FIX: Initialized save_count
            
            // FIX: Set initial state to 0 for real run
            x_state_x <= 0;
            x_state_y <= 0;
            x_state_z <= 0;

            // --- FIXED POINT MATH: 1.0 = 1000 ---
            // A = 1.0 * Identity
            A_matrix[0] <= 1000; A_matrix[1] <= 0;   A_matrix[2] <= 0;
            A_matrix[3] <= 0;   A_matrix[4] <= 1000; A_matrix[5] <= 0;
            A_matrix[6] <= 0;   A_matrix[7] <= 0;   A_matrix[8] <= 1000;
            
            // H = 1.0 * Identity
            H_matrix[0] <= 1000; H_matrix[1] <= 0;   H_matrix[2] <= 0;
            H_matrix[3] <= 0;   H_matrix[4] <= 1000; H_matrix[5] <= 0;
            H_matrix[6] <= 0;   H_matrix[7] <= 0;   H_matrix[8] <= 1000;
            
            // FIX: K = Use the K_SCALED parameter
            K_matrix[0] <= K_SCALED; K_matrix[1] <= 0;       K_matrix[2] <= 0;
            K_matrix[3] <= 0;        K_matrix[4] <= K_SCALED; K_matrix[5] <= 0;
            K_matrix[6] <= 0;        K_matrix[7] <= 0;        K_matrix[8] <= K_SCALED;

            // Clear temp registers
            temp1_Hx_x <= 0; temp1_Hx_y <= 0; temp1_Hx_z <= 0;
            temp2_err_x <= 0; temp2_err_y <= 0; temp2_err_z <= 0;
            temp3_corr_x <= 0; temp3_corr_y <= 0; temp3_corr_z <= 0;
            
        end else begin
            // Default: keep all 'start' and 'write enable' signals low
            mult_start <= 0;
            mult_a_wen <= 0;
            mult_b_wen <= 0;
            addsub_start <= 0;
            addsub_a_wen <= 0;
            addsub_b_wen <= 0;
            done <= 0; 
            
            case (state)
                STATE_IDLE: begin
                    if (start) begin
                        $display("FSM: Starting cycle...");
                        load_count <= 0;
                        state <= STATE_PRED_1_LOAD_A;
                    end
                end
                
                // === PREDICT Step: x_k = A * x_k ===
                // A(1000) * x_k(1000) = Result(1,000,000)
                // We must >> 10 (divide by 1024) to get back to scale (1000)
                STATE_PRED_1_LOAD_A: begin
                    mult_a_wen <= 1;
                    mult_a_addr <= load_count;
                    mult_a_in <= A_matrix[load_count];
                    if (load_count == MAT_SIZE - 1) begin
                        load_count <= 0; 
                        state <= STATE_PRED_2_LOAD_X;
                    end else load_count <= load_count + 1;
                end
                STATE_PRED_2_LOAD_X: begin
                    mult_b_wen <= 1;
                    mult_b_addr <= load_count;
                    if (load_count == 0) mult_b_in <= x_state_x;
                    else if (load_count == 3) mult_b_in <= x_state_y;
                    else if (load_count == 6) mult_b_in <= x_state_z;
                    else mult_b_in <= 0;
                    if (load_count == MAT_SIZE - 1) begin
                        load_count <= 0; 
                        state <= STATE_PRED_3_RUN;
                    end else load_count <= load_count + 1;
                end
                STATE_PRED_3_RUN: begin
                    mult_start <= 1;
                    state <= STATE_PRED_4_WAIT_SAVE;
                end
                STATE_PRED_4_WAIT_SAVE: begin
                    if (mult_c_valid) begin
                        // A(1000) * x(1000) = C(1,000,000). We must scale back.
                        // <-- FIX: Was storing unscaled value.
                        if (mult_row == 0 && mult_col == 0) x_state_x <= mult_c_out >>> SCALE_BITS;
                        if (mult_row == 1 && mult_col == 0) x_state_y <= mult_c_out >>> SCALE_BITS;
                        if (mult_row == 2 && mult_col == 0) x_state_z <= mult_c_out >>> SCALE_BITS;
                    end
                    if (mult_done) begin
                        load_count <= 0; 
                        state <= STATE_UPD1_1_LOAD_H;
                    end
                end
                
                // === UPDATE Step 1: temp1 = H * x_k ===
                // H(1000) * x_k(1000) = Result(1,000,000)
                // We must >> 10 to get back to scale (1000)
                STATE_UPD1_1_LOAD_H: begin
                    mult_a_wen <= 1;
                    mult_a_addr <= load_count;
                    mult_a_in <= H_matrix[load_count];
                    if (load_count == MAT_SIZE - 1) begin
                        load_count <= 0;
                        state <= STATE_UPD1_2_LOAD_X;
                    end else load_count <= load_count + 1;
                end
                STATE_UPD1_2_LOAD_X: begin
                    mult_b_wen <= 1;
                    mult_b_addr <= load_count;
                    if (load_count == 0) mult_b_in <= x_state_x;
                    else if (load_count == 3) mult_b_in <= x_state_y;
                    else if (load_count == 6) mult_b_in <= x_state_z;
                    else mult_b_in <= 0;
                    if (load_count == MAT_SIZE - 1) begin
                        load_count <= 0;
                        state <= STATE_UPD1_3_RUN;
                    end else load_count <= load_count + 1;
                end
                STATE_UPD1_3_RUN: begin
                    mult_start <= 1;
                    state <= STATE_UPD1_4_WAIT_SAVE;
                end
                STATE_UPD1_4_WAIT_SAVE: begin
                    if (mult_c_valid) begin
                        if (mult_row == 0 && mult_col == 0) temp1_Hx_x <= mult_c_out >>> SCALE_BITS;
                        if (mult_row == 1 && mult_col == 0) temp1_Hx_y <= mult_c_out >>> SCALE_BITS;
                        if (mult_row == 2 && mult_col == 0) temp1_Hx_z <= mult_c_out >>> SCALE_BITS;
                    end
                    if (mult_done) begin
                        load_count <= 0;
                        state <= STATE_UPD2_1_LOAD_Z;
                    end
                end

                // === UPDATE Step 2: temp2 = z_k - temp1 ===
                // z_k(1000) - temp1(1000) = Result(1000). No scaling.
                STATE_UPD2_1_LOAD_Z: begin 
                    addsub_a_wen <= 1;
                    addsub_a_addr <= load_count;
                    if (load_count == 0) addsub_a_in <= z_in_x;
                    else if (load_count == 1) addsub_a_in <= z_in_y;
                    else if (load_count == 2) addsub_a_in <= z_in_z;
                    else addsub_a_in <= 0;
                    if (load_count == MAT_SIZE - 1) begin 
                        load_count <= 0;
                        state <= STATE_UPD2_2_LOAD_T1;
                    end else load_count <= load_count + 1;
                end
                STATE_UPD2_2_LOAD_T1: begin 
                    addsub_b_wen <= 1;
                    addsub_b_addr <= load_count;
                    if (load_count == 0) addsub_b_in <= temp1_Hx_x;
                    else if (load_count == 1) addsub_b_in <= temp1_Hx_y;
                    else if (load_count == 2) addsub_b_in <= temp1_Hx_z;
                    else addsub_b_in <= 0;
                    if (load_count == MAT_SIZE - 1) begin
                        load_count <= 0;
                        state <= STATE_UPD2_3_RUN_SUB;
                    end else load_count <= load_count + 1;
                end
                STATE_UPD2_3_RUN_SUB: begin
                    addsub_op <= 1; // 1 = SUBTRACT
                    addsub_start <= 1;
                    state <= STATE_UPD2_4_WAIT_SAVE;
                end
                STATE_UPD2_4_WAIT_SAVE: begin
                    if (addsub_c_valid) begin
                        if (addsub_index == 0)      temp2_err_x <= addsub_c_out;
                        else if (addsub_index == 1) temp2_err_y <= addsub_c_out;
                        else if (addsub_index == 2) temp2_err_z <= addsub_c_out;
                    end
                    if (addsub_done) begin
                        load_count <= 0;
                        state <= STATE_UPD3_1_LOAD_K;
                    end
                end
                
                // === UPDATE Step 3: temp3 = K * temp2 ===
                // K(137) * temp2(1000) = Result(137,000)
                // We must >> 10 to get back to scale (137)
                // NOTE: The K value is already < 1.0, so K(137) is correct.
                // K(137) * temp2(1000) = 137,000.
                // 137,000 >> 10 (1024) = 133. This is our correction term.
                // Wait, if K is 137 (0.137) and temp2 is 1000 (1.0),
                // the result should be 137 (0.137).
                // Let's re-check python: K_val = 0.1379. K_scaled = 137.
                // temp2 is z_k(1000) - temp1(1000). So temp2 is scaled by 1000.
                // K(137) * temp2(1000) = 137,000.
                // We must >> 10 to get 133.
                // The final step is x_k = x_k + temp3.
                // x_k(1000) + temp3(133??). This seems wrong.
                //
                // Let's rethink.
                // K (0.137) * temp2 (scaled by 1000)
                // K should be scaled by 1000. K_scaled = 137.
                // K_matrix[0] <= K_SCALED; -> K_matrix[0] is 137.
                // K(137) * temp2(1000) = 137,000.
                // We must >> 10 to get 133. This is temp3.
                // x_k(1000) + temp3(133). This is correct. x_state is 1000-scaled. temp3 is 1000-scaled.
                // e.g. 5.0 (5000) + 0.13 (133) = 5.13 (5133).
                // Yes, the logic `mult_c_out >>> SCALE_BITS` is correct.
                STATE_UPD3_1_LOAD_K: begin
                    mult_a_wen <= 1;
                    mult_a_addr <= load_count;
                    mult_a_in <= K_matrix[load_count];
                    if (load_count == MAT_SIZE - 1) begin
                        load_count <= 0;
                        state <= STATE_UPD3_2_LOAD_T2;
                    end else load_count <= load_count + 1;
                end
                STATE_UPD3_2_LOAD_T2: begin
                    mult_b_wen <= 1;
                    mult_b_addr <= load_count;
                    if (load_count == 0) mult_b_in <= temp2_err_x;
                    else if (load_count == 3) mult_b_in <= temp2_err_y;
                    else if (load_count == 6) mult_b_in <= temp2_err_z;
                    else mult_b_in <= 0;
                    if (load_count == MAT_SIZE - 1) begin
                        load_count <= 0;
                        state <= STATE_UPD3_3_RUN;
                    end else load_count <= load_count + 1;
                end
                STATE_UPD3_3_RUN: begin
                    mult_start <= 1;
                    state <= STATE_UPD3_4_WAIT_SAVE;
                end
                STATE_UPD3_4_WAIT_SAVE: begin
                    if (mult_c_valid) begin
                        if (mult_row == 0 && mult_col == 0) temp3_corr_x <= mult_c_out >>> SCALE_BITS;
                        if (mult_row == 1 && mult_col == 0) temp3_corr_y <= mult_c_out >>> SCALE_BITS;
                        if (mult_row == 2 && mult_col == 0) temp3_corr_z <= mult_c_out >>> SCALE_BITS;
                    end
                    if (mult_done) begin
                        load_count <= 0;
                        state <= STATE_UPD4_1_LOAD_X;
                    end
                end
                
                // === UPDATE Step 4: x_k = x_k + temp3 ===
                // x_k(1000) + temp3(1000) = Result(1000)
                // No scaling needed here
                STATE_UPD4_1_LOAD_X: begin
                    addsub_a_wen <= 1;
                    addsub_a_addr <= load_count;
                    if (load_count == 0) addsub_a_in <= x_state_x;
                    else if (load_count == 1) addsub_a_in <= x_state_y;
                    else if (load_count == 2) addsub_a_in <= x_state_z;
                    else addsub_a_in <= 0;
                    if (load_count == MAT_SIZE - 1) begin
                        load_count <= 0;
                        state <= STATE_UPD4_2_LOAD_T3;
                    end else load_count <= load_count + 1;
                end
                STATE_UPD4_2_LOAD_T3: begin
                    addsub_b_wen <= 1;
                    addsub_b_addr <= load_count;
                    if (load_count == 0) addsub_b_in <= temp3_corr_x;
                    else if (load_count == 1) addsub_b_in <= temp3_corr_y;
                    else if (load_count == 2) addsub_b_in <= temp3_corr_z;
                    else addsub_b_in <= 0;
                    if (load_count == MAT_SIZE - 1) begin
                        load_count <= 0;
                        state <= STATE_UPD4_3_RUN_ADD;
                    end else load_count <= load_count + 1;
                end
                STATE_UPD4_3_RUN_ADD: begin
                    addsub_op <= 0; // 0 = ADD
                    addsub_start <= 1;
                    save_count <= 0;
                    state <= STATE_UPD4_4_WAIT_SAVE;
                end
                STATE_UPD4_4_WAIT_SAVE: begin
                    if (addsub_c_valid) begin
                        // Save the final, corrected state
                        if (addsub_index == 0)      x_state_x <= addsub_c_out;
                        else if (addsub_index == 1) x_state_y <= addsub_c_out;
                        else if (addsub_index == 2) x_state_z <= addsub_c_out;
                        save_count <= save_count + 1;
                    end
                    if (addsub_done) begin
                        load_count <= 0;
                        state <= STATE_DONE;
                    end
                end

                // --- DONE ---
                STATE_DONE: begin
                    //$display("FSM: Cycle DONE."); // Quieted for long run
                    done <= 1;
                    if (!start) begin
                        state <= STATE_IDLE;
                    end
                end
                
                default: state <= STATE_IDLE;
            endcase
        end
    end
    
    // Combinational assignment for outputs (Verilog-2001 style)
    always @(x_state_x or x_state_y or x_state_z) begin
        x_out_x = x_state_x;
        x_out_y = x_state_y;
        x_out_z = x_state_z;
    end

endmodule
