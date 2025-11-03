/*
 * File: matrix_mult_3x3.v
 * Tool-belt module: Multiplies two 3x3 matrices (A * B = C)
 * * FIX: Added the 'ACC_WIDTH' parameter to match the FSM.
 */
`timescale 1ns / 1ps

module matrix_mult_3x3 #(
    parameter M = 3,
    parameter N = 3,
    parameter P = 3,
    parameter DATA_WIDTH = 32,
    // --- FIX: Added this parameter ---
    parameter ACC_WIDTH = 66 // (2*DATA_WIDTH) + 2
)(
    input  wire clk,
    input  wire rst,
    input  wire start,
    
    // Matrix A inputs
    input  wire signed [DATA_WIDTH-1:0] a_in,
    input  wire [3:0] a_addr,
    input  wire a_wen,
    
    // Matrix B inputs
    input  wire signed [DATA_WIDTH-1:0] b_in,
    input  wire [3:0] b_addr,
    input  wire b_wen,
    
    // Matrix C outputs
    // --- FIX: Use ACC_WIDTH parameter ---
    output reg signed [ACC_WIDTH-1:0] c_out,
    output reg c_valid,
    output reg done,
    
    // Output helpers to know which element is valid
    output reg [1:0] row,
    output reg [1:0] col
);

    // Internal BRAMs for matrices
    reg signed [DATA_WIDTH-1:0] a_ram [0:M*N-1];
    reg signed [DATA_WIDTH-1:0] b_ram [0:N*P-1];

    // Internal accumulator
    // --- FIX: Use ACC_WIDTH parameter ---
    reg signed [ACC_WIDTH-1:0] c_acc;

    // FSM States
    localparam STATE_IDLE = 0;
    localparam STATE_RUN  = 1;
    localparam STATE_DONE = 2;
    
    reg [1:0] state;
    
    // Loop counters
    reg [1:0] i_row; // M (rows in A/C)
    reg [1:0] j_col; // P (cols in B/C)
    reg [1:0] k_sum; // N (cols in A / rows in B)

    // Handle BRAM writes
    always @(posedge clk) begin
        if (a_wen) a_ram[a_addr] <= a_in;
        if (b_wen) b_ram[b_addr] <= b_in;
    end
    
    // Main FSM
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= STATE_IDLE;
            done <= 0;
            c_valid <= 0;
            c_out <= 0;
            c_acc <= 0;
            i_row <= 0;
            j_col <= 0;
            k_sum <= 0;
            row <= 0;
            col <= 0;
        end else begin
            // Defaults
            c_valid <= 0;
            done <= 0;
            
            case (state)
                STATE_IDLE: begin
                    if (start) begin
                        i_row <= 0;
                        j_col <= 0;
                        k_sum <= 0;
                        c_acc <= 0; // Clear accumulator for first element
                        state <= STATE_RUN;
                    end
                end
                
                STATE_RUN: begin
                    // This state calculates one element C[i,j]
                    // C[i,j] = sum(A[i,k] * B[k,j]) for k=0 to N-1
                    
                    // Perform one multiply-accumulate step
                    c_acc <= c_acc + (a_ram[i_row*N + k_sum] * b_ram[k_sum*P + j_col]);
                    
                    if (k_sum == N-1) begin
                        // This is the last summation step
                        c_valid <= 1; // The output is valid on this cycle
                        c_out <= c_acc + (a_ram[i_row*N + k_sum] * b_ram[k_sum*P + j_col]);
                        row <= i_row;
                        col <= j_col;
                        c_acc <= 0; // Clear acc for next element
                        
                        // Move to next element
                        if (j_col == P-1) begin
                            if (i_row == M-1) begin
                                state <= STATE_DONE; // Finished all elements
                            end else begin
                                i_row <= i_row + 1; // Next row
                                j_col <= 0;
                                k_sum <= 0;
                            end
                        end else begin
                            j_col <= j_col + 1; // Next col
                            k_sum <= 0;
                        end
                        
                    end else begin
                        // Next summation step
                        k_sum <= k_sum + 1;
                    end
                end
                
                STATE_DONE: begin
                    done <= 1;
                    if (!start) begin
                        state <= STATE_IDLE;
                    end
                end
                
                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
