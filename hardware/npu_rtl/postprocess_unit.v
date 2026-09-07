`timescale 1ns / 1ps

/* Fixed-point post-processing shared by every neuron.  `multiplier` is a
 * signed integer and the effective scale is multiplier / 2**shift. */
module postprocess_unit (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               start,
    input  wire signed [31:0] accumulator,
    input  wire signed [31:0] bias,
    input  wire signed [31:0] multiplier,
    input  wire        [5:0]  shift,
    input  wire               relu,
    output reg  signed [31:0] value_out,
    output reg  signed [7:0]  activation_out,
    output reg                output_valid
);
    reg signed [32:0] biased_stage1;
    reg signed [31:0] multiplier_stage1;
    reg        [5:0]  shift_stage1;
    reg               relu_stage1;
    reg               stage1_valid;

    reg signed [64:0] product_stage2;
    reg        [5:0]  shift_stage2;
    reg               relu_stage2;
    reg               stage2_valid;

    reg signed [64:0] magnitude_stage3;
    reg               product_negative_stage3;
    reg        [5:0]  shift_stage3;
    reg               relu_stage3;
    reg               stage3_valid;

    reg signed [64:0] rounded_magnitude_stage4;
    reg               product_negative_stage4;
    reg        [5:0]  shift_stage4;
    reg               relu_stage4;
    reg               stage4_valid;

    reg signed [64:0] shifted_magnitude_stage5;
    reg               product_negative_stage5;
    reg               relu_stage5;
    reg               stage5_valid;

    reg signed [64:0] scaled_value_stage6;
    reg               relu_stage6;
    reg               stage6_valid;

    wire signed [32:0] accumulator_ext = {{1{accumulator[31]}}, accumulator};
    wire signed [32:0] bias_ext = {{1{bias[31]}}, bias};
    wire signed [32:0] biased_next = accumulator_ext + bias_ext;
    wire signed [64:0] biased_stage1_ext =
        {{32{biased_stage1[32]}}, biased_stage1};
    wire signed [64:0] multiplier_stage1_ext =
        {{33{multiplier_stage1[31]}}, multiplier_stage1};
    wire signed [64:0] product_next = biased_stage1_ext * multiplier_stage1_ext;

    /* Round the non-negative magnitude, then restore the product sign. */
    wire signed [64:0] product_magnitude =
        product_stage2[64] ? -product_stage2 : product_stage2;
    wire signed [64:0] rounding_increment_stage3 =
        (shift_stage3 == 0) ? 65'sd0 : (65'sd1 <<< (shift_stage3 - 1));
    wire signed [64:0] rounded_magnitude_next =
        magnitude_stage3 + rounding_increment_stage3;
    wire signed [64:0] shifted_magnitude_next =
        rounded_magnitude_stage4 >>> shift_stage4;
    wire signed [64:0] scaled_value = scaled_value_stage6;

    wire signed [31:0] saturated_value =
        (scaled_value > 65'sd2147483647) ? 32'sh7fffffff :
        (scaled_value < -65'sd2147483648) ? 32'sh80000000 :
                                               scaled_value[31:0];
    wire signed [7:0] saturated_activation =
        (relu_stage6 && (saturated_value < 0)) ? 8'sd0 :
        (saturated_value > 32'sd127) ? 8'sd127 :
        (saturated_value < -32'sd128) ? -8'sd128 :
                                         saturated_value[7:0];

    always @(posedge clk) begin
        if (!rst_n) begin
            biased_stage1  <= 33'sd0;
            multiplier_stage1 <= 32'sd0;
            shift_stage1   <= 6'd0;
            relu_stage1    <= 1'b0;
            stage1_valid   <= 1'b0;
            product_stage2 <= 65'sd0;
            shift_stage2   <= 6'd0;
            relu_stage2    <= 1'b0;
            stage2_valid   <= 1'b0;
            magnitude_stage3 <= 65'sd0;
            product_negative_stage3 <= 1'b0;
            shift_stage3   <= 6'd0;
            relu_stage3    <= 1'b0;
            stage3_valid   <= 1'b0;
            rounded_magnitude_stage4 <= 65'sd0;
            product_negative_stage4 <= 1'b0;
            shift_stage4   <= 6'd0;
            relu_stage4    <= 1'b0;
            stage4_valid   <= 1'b0;
            shifted_magnitude_stage5 <= 65'sd0;
            product_negative_stage5 <= 1'b0;
            relu_stage5    <= 1'b0;
            stage5_valid   <= 1'b0;
            scaled_value_stage6 <= 65'sd0;
            relu_stage6    <= 1'b0;
            stage6_valid   <= 1'b0;
            value_out      <= 32'sd0;
            activation_out <= 8'sd0;
            output_valid   <= 1'b0;
        end else begin
            stage1_valid <= start;
            stage2_valid <= stage1_valid;
            stage3_valid <= stage2_valid;
            stage4_valid <= stage3_valid;
            stage5_valid <= stage4_valid;
            stage6_valid <= stage5_valid;
            output_valid <= stage6_valid;

            if (start) begin
                biased_stage1    <= biased_next;
                multiplier_stage1 <= multiplier;
                shift_stage1     <= shift;
                relu_stage1      <= relu;
            end

            if (stage1_valid) begin
                product_stage2 <= product_next;
                shift_stage2   <= shift_stage1;
                relu_stage2    <= relu_stage1;
            end

            if (stage2_valid) begin
                magnitude_stage3 <= product_magnitude;
                product_negative_stage3 <= product_stage2[64];
                shift_stage3   <= shift_stage2;
                relu_stage3    <= relu_stage2;
            end

            if (stage3_valid) begin
                rounded_magnitude_stage4 <= rounded_magnitude_next;
                product_negative_stage4 <= product_negative_stage3;
                shift_stage4   <= shift_stage3;
                relu_stage4    <= relu_stage3;
            end

            if (stage4_valid) begin
                shifted_magnitude_stage5 <= shifted_magnitude_next;
                product_negative_stage5 <= product_negative_stage4;
                relu_stage5    <= relu_stage4;
            end

            if (stage5_valid) begin
                scaled_value_stage6 <= product_negative_stage5 ?
                    -shifted_magnitude_stage5 : shifted_magnitude_stage5;
                relu_stage6 <= relu_stage5;
            end

            if (stage6_valid) begin
                value_out      <= saturated_value;
                activation_out <= saturated_activation;
            end
        end
    end
endmodule
