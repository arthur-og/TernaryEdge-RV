`timescale 1ns / 1ps

/* One multiplierless ternary processing element.
 *
 * 00 = 0, 01 = +1, 11 = -1 and 10 is reserved.  The product is widened to
 * nine bits for INT8 input so that negating -128 produces +128 correctly.
 */
module ternary_mac #(
    parameter ACT_WIDTH  = 8,
    parameter PROD_WIDTH = ACT_WIDTH + 1
) (
    input  wire signed [ACT_WIDTH-1:0] act_in,
    input  wire        [1:0]            weight,
    output reg  signed [PROD_WIDTH-1:0] product,
    output wire                          invalid_weight
);
    reg signed [PROD_WIDTH-1:0] act_ext;

    assign invalid_weight = (weight == 2'b10);

    always @* begin
        act_ext = {{(PROD_WIDTH-ACT_WIDTH){act_in[ACT_WIDTH-1]}}, act_in};
        case (weight)
            2'b01:   product = act_ext;
            2'b11:   product = -act_ext;
            default: product = {PROD_WIDTH{1'b0}};
        endcase
    end
endmodule
