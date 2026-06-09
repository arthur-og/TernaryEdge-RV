/*
 * ternary_mac_array.v — 64× Parallel Multiplierless MAC Array
 * Ternary Edge-RV Project
 *
 * Instantiates 64 ternary_mac units operating in parallel.
 * Each MAC computes: partial[k] = act[k] × weight[k]
 *   weight=01 (+1): partial = +act
 *   weight=11 (-1): partial = -act
 *   weight=00 ( 0): partial = 0
 *
 * All 64 MACs fire simultaneously on the same clock cycle.
 * The partial results feed into an adder tree for summation.
 *
 * 0 DSPs used — purely adders, subtracters, and multiplexers.
 */

module ternary_mac_array #(
    parameter NUM_MACS     = 64,
    parameter ACT_WIDTH    = 8,
    parameter ACC_WIDTH    = 32
)(
    input  wire                        clk,
    input  wire                        rst,
    input  wire                        en,         // Enable all MACs
    input  wire                        clear,      // Clear all accumulators
    input  wire [NUM_MACS*ACT_WIDTH-1:0] acts,     // 64 × INT8 activations
    input  wire [NUM_MACS*2-1:0]        weights,   // 64 × 2-bit ternary weights
    output wire [NUM_MACS*ACC_WIDTH-1:0] acc_outs  // 64 × 32-bit accumulated results
);

    genvar k;
    generate
        for (k = 0; k < NUM_MACS; k = k + 1) begin : gen_mac
            ternary_mac #(
                .ACT_WIDTH(ACT_WIDTH),
                .ACC_WIDTH(ACC_WIDTH)
            ) u_mac (
                .clk     (clk),
                .rst     (rst),
                .en      (en),
                .clear   (clear),
                .act_in  (acts[k*ACT_WIDTH +: ACT_WIDTH]),
                .weight  (weights[k*2 +: 2]),
                .acc_out (acc_outs[k*ACC_WIDTH +: ACC_WIDTH])
            );
        end
    endgenerate

endmodule
