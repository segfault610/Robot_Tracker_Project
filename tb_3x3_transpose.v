`timescale 1ns / 1ps

module tb_3x3_transpose;

    // --- Parameters ---
    parameter M = 3;
    parameter P = 3;
    parameter DATA_WIDTH = 32;

    // --- Wires and Regs ---
    reg clk;
    reg rst;
    reg start;
    
    reg signed [DATA_WIDTH-1:0] a_in;
    reg [3:0] a_addr;
    reg a_wen;

    wire signed [DATA_WIDTH-1:0] c_out;
    wire c_valid, done;
    wire [3:0] uut_index; // The current index (0-8) from the module
    
    integer i, r, c, errors;
    
    // Testbench memory
    reg signed [DATA_WIDTH-1:0] A_input [0:M*P-1];
    reg signed [DATA_WIDTH-1:0] c_expected [0:M*P-1];
    reg signed [DATA_WIDTH-1:0] c_actual [0:M*P-1];

    // --- Instantiate the "Calculator" ---
    matrix_transpose_3x3 #( 
        .M(M),
        .P(P),
        .DATA_WIDTH(DATA_WIDTH)
    ) uut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .a_in(a_in), .a_addr(a_addr), .a_wen(a_wen),
        .c_out(c_out), .c_valid(c_valid), .done(done),
        .i_count_out(uut_index)
    );

    // --- Clock Generator ---
    always #10 clk = ~clk;

    // --- Test Procedure ---
    initial begin
        $display("--- 3x3 Transpose Testbench Started ---");
        clk = 0; rst = 1; start = 0;
        a_wen = 0; errors = 0;

        #20 rst = 0; // Release reset
        @(posedge clk);
        
        // --- LOAD MATRIX A ---
        $display("Loading Matrix A = [1,2,3...9]");
        // A = | 1  2  3 |
        //     | 4  5  6 |
        //     | 7  8  9 |
        for (i = 0; i < M*P; i = i + 1) begin
            A_input[i] = i + 1;
            a_wen = 1; a_addr = i; a_in = A_input[i];
            @(posedge clk);
        end
        a_wen = 0;

        // --- Calculate Expected Transpose ---
        // C_exp = | 1  4  7 |
        //         | 2  5  8 |
        //         | 3  6  9 |
        for (r = 0; r < M; r = r + 1) begin
            for (c = 0; c < P; c = c + 1) begin
                // C[r][c] = A[c][r]
                c_expected[r*P + c] = A_input[c*M + r];
            end
        end

        // ***************
        // --- TEST: TRANSPOSE ---
        // ***************
        $display("--- Test: TRANSPOSE Operation ---");
        @(posedge clk) start = 1;
        @(posedge clk) start = 0;
        
        wait (done == 1);
        @(posedge clk); // Settle
        $display("--- TRANSPOSE complete ---");

        // Check TRANSPOSE results
        for (i = 0; i < M*P; i = i + 1) begin
            if (c_actual[i] != c_expected[i]) begin
                errors = errors + 1;
                $display("TRANSPOSE ERROR @ C[%d]: Exp %d, Got %d", i, c_expected[i], c_actual[i]);
            end
        end
        
        // --- FINAL VERDICT ---
        if (errors == 0) begin
            $display("--- TEST PASSED: 3x3 Transpose is correct! ---");
        end else begin
            $display("--- TEST FAILED: %d errors found ---", errors);
        end

        #100 $finish;
    end
    
    // This "receiver" loop watches for c_valid
    // and stores the result from c_out.
    always @(posedge clk) begin
        if (c_valid) begin
            c_actual[uut.i_count_out] <= c_out;
        end
    end

endmodule
