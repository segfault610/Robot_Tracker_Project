`timescale 1ns / 1ps

module tb_3x3_add_sub;

    // --- Parameters ---
    parameter M = 3;
    parameter P = 3;
    parameter DATA_WIDTH = 32;

    // --- Wires and Regs ---
    reg clk;
    reg rst;
    reg start;
    reg op; // 0=ADD, 1=SUB
    
    reg signed [DATA_WIDTH-1:0] a_in, b_in;
    reg [3:0] a_addr, b_addr; // $clog2(3*3) = 4 bits
    reg a_wen, b_wen;

    wire signed [DATA_WIDTH-1:0] c_out;
    wire c_valid, done;
    wire [3:0] addsub_index; 
    
    integer i, errors;
    
    // Testbench memory
    reg signed [DATA_WIDTH-1:0] c_expected [0:M*P-1];
    reg signed [DATA_WIDTH-1:0] c_actual [0:M*P-1];

    // --- Instantiate the "Calculator" ---
    matrix_add_sub_3x3 #( 
        .M(M),
        .P(P),
        .DATA_WIDTH(DATA_WIDTH)
    ) uut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .op(op),
        .a_in(a_in), .a_addr(a_addr), .a_wen(a_wen),
        .b_in(b_in), .b_addr(b_addr), .b_wen(b_wen),
        .c_out(c_out), .c_valid(c_valid), .done(addsub_done),
        .i_count_out(addsub_index)
    );

    // --- Clock Generator ---
    always #10 clk = ~clk;

    // --- Test Procedure ---
    initial begin
        $display("--- 3x3 Add/Sub Testbench Started ---");
        clk = 0; rst = 1; start = 0; op = 0;
        a_wen = 0; b_wen = 0; errors = 0;

        #20 rst = 0; // Release reset
        @(posedge clk);
        
        // --- LOAD MATRICES ---
        $display("Loading Matrix A = [1,2,3...9]");
        for (i = 0; i < M*P; i = i + 1) begin
            a_wen = 1; a_addr = i; a_in = i + 1;
            @(posedge clk);
        end
        a_wen = 0;

        $display("Loading Matrix B = [10,10...10]");
        for (i = 0; i < M*P; i = i + 1) begin
            b_wen = 1; b_addr = i; b_in = 10;
            @(posedge clk);
        end
        b_wen = 0;

        // ***************
        // --- TEST 1: ADD ---
        // ***************
        $display("--- Test 1: ADD Operation ---");
        op = 0; // Set op to ADD
        
        // C_expected = A + B = [11, 12, 13 ... 19]
        for (i = 0; i < M*P; i = i + 1) begin
            c_expected[i] = (i + 1) + 10;
        end

        @(posedge clk) start = 1;
        @(posedge clk) start = 0;
        wait (addsub_done == 1);
        @(posedge clk); // Settle
        
        $display("--- ADD complete ---");

        // Check ADD results
        for (i = 0; i < M*P; i = i + 1) begin
            if (c_actual[i] != c_expected[i]) begin
                errors = errors + 1;
                $display("ADD ERROR @ C[%d]: Expected %d, Got %d", i, c_expected[i], c_actual[i]);
            end
        end
        
        #50; // Wait a bit
        
        // ***************
        // --- TEST 2: SUBTRACT ---
        // ***************
        $display("--- Test 2: SUBTRACT Operation ---");
        op = 1; // Set op to SUBTRACT
        
        // C_expected = A - B = [-9, -8, -7 ... -1]
        for (i = 0; i < M*P; i = i + 1) begin
            c_expected[i] = (i + 1) - 10;
        end

        @(posedge clk) start = 1;
        @(posedge clk) start = 0;
        wait (addsub_done == 1);
        @(posedge clk); // Settle

        $display("--- SUBTRACT complete ---");

        // Check SUBTRACT results
        for (i = 0; i < M*P; i = i + 1) begin
            if (c_actual[i] != c_expected[i]) begin
                errors = errors + 1;
                $display("SUB ERROR @ C[%d]: Expected %d, Got %d", i, c_expected[i], c_actual[i]);
            end
        end

        // --- FINAL VERDICT ---
        if (errors == 0) begin
            $display("--- TEST PASSED: 3x3 Add/Sub is correct! ---");
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
