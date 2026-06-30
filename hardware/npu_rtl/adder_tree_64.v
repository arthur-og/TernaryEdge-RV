`timescale 1ns / 1ps

/*
 * adder_tree_64.v — 6-Stage Pipelined Adder Tree (64 → 1)
 * Ternary Edge-RV Project
 *
 * Sums 64 signed values using a binary tree with 6 pipeline stages.
 * Stage 1: 64→32  (32 adders,  2→1 each)
 * Stage 2: 32→16  (16 adders)
 * Stage 3: 16→8   ( 8 adders)
 * Stage 4: 8→4    ( 4 adders)
 * Stage 5: 4→2    ( 2 adders)
 * Stage 6: 2→1    ( 1 adder)
 *
 * Total: 63 adders, 6-cycle latency, fully pipelined.
 *
 * Input width:  IN_WIDTH bits per value (9 bits recommended for INT8×ternary)
 * Output width: IN_WIDTH + 6 bits (15 bits for IN_WIDTH=9, sufficient for 64 values)
 */

module adder_tree_64 #(
    parameter IN_WIDTH = 9  // Width of each input value (signed)
)(
    input  wire                    clk,
    input  wire                    rst,
    input  wire                    en,     // Pipeline enable
    input  wire signed [IN_WIDTH*64-1:0] values_in,  // 64 packed signed values
    output reg  signed [IN_WIDTH+6-1:0] sum_out       // Sum of all 64 values
);

    // =========================================================================
    // Internal pipeline registers
    // =========================================================================
    // Stage 1: 64 → 32
    reg signed [IN_WIDTH:0]   st1 [0:31];   // 32 sums of 2 values each
    
    // Stage 2: 32 → 16
    reg signed [IN_WIDTH+1:0] st2 [0:15];
    
    // Stage 3: 16 → 8
    reg signed [IN_WIDTH+2:0] st3 [0:7];
    
    // Stage 4: 8 → 4
    reg signed [IN_WIDTH+3:0] st4 [0:3];
    
    // Stage 5: 4 → 2
    reg signed [IN_WIDTH+4:0] st5 [0:1];
    
    // Stage 6: 2 → 1 (output)
    reg signed [IN_WIDTH+5:0] st6;

    // =========================================================================
    // Combinational wires for each stage
    // =========================================================================
    genvar i;
    
    // Stage 1: Pairwise add 64 → 32
    wire signed [IN_WIDTH:0] s1 [0:31];
    generate
        for (i = 0; i < 32; i = i + 1) begin : gen_s1
            assign s1[i] = $signed(values_in[i*2*IN_WIDTH +: IN_WIDTH]) + 
                           $signed(values_in[(i*2+1)*IN_WIDTH +: IN_WIDTH]);
        end
    endgenerate

    // Stage 2: 32 → 16
    wire signed [IN_WIDTH+1:0] s2 [0:15];
    generate
        for (i = 0; i < 16; i = i + 1) begin : gen_s2
            assign s2[i] = st1[i*2] + st1[i*2+1];
        end
    endgenerate

    // Stage 3: 16 → 8
    wire signed [IN_WIDTH+2:0] s3 [0:7];
    generate
        for (i = 0; i < 8; i = i + 1) begin : gen_s3
            assign s3[i] = st2[i*2] + st2[i*2+1];
        end
    endgenerate

    // Stage 4: 8 → 4
    wire signed [IN_WIDTH+3:0] s4 [0:3];
    generate
        for (i = 0; i < 4; i = i + 1) begin : gen_s4
            assign s4[i] = st3[i*2] + st3[i*2+1];
        end
    endgenerate

    // Stage 5: 4 → 2
    wire signed [IN_WIDTH+4:0] s5 [0:1];
    generate
        for (i = 0; i < 2; i = i + 1) begin : gen_s5
            assign s5[i] = st4[i*2] + st4[i*2+1];
        end
    endgenerate

    // Stage 6: 2 → 1
    wire signed [IN_WIDTH+5:0] s6;
    assign s6 = st5[0] + st5[1];

    // =========================================================================
    // Pipeline Registers
    // =========================================================================
    integer j;
    always @(posedge clk) begin
        if (rst) begin
            for (j = 0; j < 32; j = j + 1) st1[j] <= 0;
            for (j = 0; j < 16; j = j + 1) st2[j] <= 0;
            for (j = 0; j < 8;  j = j + 1) st3[j] <= 0;
            for (j = 0; j < 4;  j = j + 1) st4[j] <= 0;
            for (j = 0; j < 2;  j = j + 1) st5[j] <= 0;
            st6 <= 0;
            sum_out <= 0;
        end else if (en) begin
            // Stage 1 pipeline register
            for (j = 0; j < 32; j = j + 1) st1[j] <= s1[j];
            // Stage 2
            for (j = 0; j < 16; j = j + 1) st2[j] <= s2[j];
            // Stage 3
            for (j = 0; j < 8;  j = j + 1) st3[j] <= s3[j];
            // Stage 4
            for (j = 0; j < 4;  j = j + 1) st4[j] <= s4[j];
            // Stage 5
            for (j = 0; j < 2;  j = j + 1) st5[j] <= s5[j];
            // Stage 6
            st6 <= s6;
            // Output
            sum_out <= st6;
        end
    end

endmodule
