/*
 * File: tb_3x3_mult.v
 * Standalone testbench for the 3x3 Matrix Multiplier.
 * Tests if (Identity * TestVector = TestVector)
 * * FIX: Converted to pure Verilog-2001 (no 'automatic')
 */
`timescale 1ns / 1ps

module tb_3x3_mult;

    // --- Parameters ---
    parameter M = 3;
    parameter N = 3;
    parameter P = 3;
    parameter DATA_WIDTH = 32;
    // This must match the FSM: (2*DATA_WIDTH) + 2
    parameter ACC_WIDTH_TB = (2*DATA_WIDTH) + 2; // 66 bits
    parameter MAT_SIZE = 9;

    // --- Wires and Regs ---
    reg clk;
    reg rst;
    reg start;
    
    reg  signed [DATA_WIDTH-1:0] a_in;
    reg  [3:0] a_addr;
    reg  a_wen;
    
    reg  signed [DATA_WIDTH-1:0] b_in;
    reg  [3:0] b_addr;
    reg  b_wen;
    
    wire signed [ACC_WIDTH_TB-1:0] c_out;
    wire c_valid;
    wire done;
    wire [1:0] row;
    wire [1:0] col;
    
    integer i;
    integer errors;
    
    // Test vector: [1000, 2000, 3000] (scaled)
    reg signed [DATA_WIDTH-1:0] test_vec [0:2];
    
    // --- FIX: Declare checker regs here (Verilog-2001 style) ---
    reg signed [DATA_WIDTH-1:0] scaled_out;
    reg signed [DATA_WIDTH-1:0] expected_val;
    
    // --- Instantiate the Multiplier ---
    matrix_mult_3x3 #(
        .M(M),
        .N(N),
        .P(P),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH_TB) // Pass the accumulator width
    ) uut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .a_in(a_in),
        .a_addr(a_addr),
        .a_wen(a_wen),
        .b_in(b_in),
        .b_addr(b_addr),
        .b_wen(b_wen),
        .c_out(c_out),
        .c_valid(c_valid),
        .done(done),
        .row(row),
        .col(col)
    );

    // --- Clock Generator ---
    always #10 clk = ~clk;

    // --- Test Procedure ---
    initial begin
        $display("--- Multiplier Testbench Started ---");
        clk = 0;
        rst = 1;
        start = 0;
        a_wen = 0;
        b_wen = 0;
        errors = 0;
        
        test_vec[0] = 1000;
        test_vec[1] = 2000;
        test_vec[2] = 3000;
        
        #20 rst = 0;
        @(posedge clk);
        
        // --- Load Matrix A (Identity * 1000) ---
        $display("Loading Matrix A (Identity)...");
        a_wen = 1;
        for (i = 0; i < MAT_SIZE; i = i + 1) begin
            a_addr = i;
            if (i == 0 || i == 4 || i == 8) begin
                a_in = 1000; // 1.0 (scaled)
            end else begin
                a_in = 0;
            end
            @(posedge clk);
        end
        a_wen = 0;

        // --- Load Matrix B (Test Vector) ---
        // B = [1000, 0, 0]
        //     [2000, 0, 0]
        //     [3000, 0, 0]
        $display("Loading Matrix B (Test Vector)...");
        b_wen = 1;
        for (i = 0; i < MAT_SIZE; i = i + 1) begin
            b_addr = i;
            if (i == 0) b_in = test_vec[0];
            else if (i == 3) b_in = test_vec[1];
            else if (i == 6) b_in = test_vec[2];
            else b_in = 0;
            @(posedge clk);
        end
        b_wen = 0;

        // --- Run the Multiplier ---
        $display("Starting multiplication...");
        @(posedge clk) start = 1;
        @(posedge clk) start = 0;
        
        // --- Wait for results ---
        wait (done == 1);
        
        $display("Multiplication complete.");
        @(posedge clk);
        
        if (errors == 0) begin
            $display("--- TEST PASSED ---");
        end else begin
            $display("--- TEST FAILED: %d errors ---", errors);
        end
        
        #100 $finish;
    end
    
    // --- Result Checker (Verilog-2001 safe) ---
    always @(posedge clk) begin
        if (c_valid) begin
            // We expect C = A * B = I * B = B
            // We only care about the first column (col == 0)
            if (col == 0) begin
                // A(1000) * B(1000) = C(1,000,000)
                // We must scale C back by 1000 (10 bits)
                
                // --- FIX: Assign to regs declared above ---
                scaled_out = c_out >>> 10;
                expected_val = test_vec[row];

                if (scaled_out == expected_val) begin
                    $display("PASS: C[%d][0] = %d (Expected %d)", row, scaled_out, expected_val);
                end else begin
                    $display("FAIL: C[%d][0] = %d (Expected %d)", row, scaled_out, expected_val);
                    errors = errors + 1;
                end
            end
        end
    end

endmodule
