`timescale 1ns / 1ps

/* Explicit 64-wide PE array.  Accumulation belongs after this array. */
module ternary_mac_array #(
    parameter NUM_MACS  = 64,
    parameter ACT_WIDTH = 8,
    parameter PROD_WIDTH = ACT_WIDTH + 1
) (
    input  wire [NUM_MACS*ACT_WIDTH-1:0]  acts,
    input  wire [NUM_MACS*2-1:0]           weights,
    output wire [NUM_MACS*PROD_WIDTH-1:0] products,
    output wire [NUM_MACS-1:0]             invalid_weights
);
    genvar lane;
    generate
        for (lane = 0; lane < NUM_MACS; lane = lane + 1) begin : gen_pe
            ternary_mac #(
                .ACT_WIDTH(ACT_WIDTH),
                .PROD_WIDTH(PROD_WIDTH)
            ) u_pe (
                .act_in        (acts[lane*ACT_WIDTH +: ACT_WIDTH]),
                .weight        (weights[lane*2 +: 2]),
                .product       (products[lane*PROD_WIDTH +: PROD_WIDTH]),
                .invalid_weight(invalid_weights[lane])
            );
        end
    endgenerate
endmodule
