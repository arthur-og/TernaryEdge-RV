`timescale 1ns / 1ps

module tb_ternary_primitives;
    reg signed [7:0] act;
    reg [1:0] weight;
    wire signed [8:0] product;
    wire invalid_weight;
    reg clk, rst, en;
    reg signed [575:0] values;
    wire signed [14:0] sum_out;
    wire output_valid;
    integer i;
    integer expected;
    integer errors;

    ternary_mac pe (
        .act_in(act), .weight(weight), .product(product),
        .invalid_weight(invalid_weight)
    );
    adder_tree_64 tree (
        .clk(clk), .rst(rst), .en(en), .values_in(values),
        .sum_out(sum_out), .output_valid(output_valid)
    );

    always #5 clk = ~clk;

    task check_pe;
        input signed [7:0] a;
        input [1:0] w;
        input signed [8:0] expected_product;
        input expected_invalid;
        begin
            act = a;
            weight = w;
            #1;
            if (product !== expected_product || invalid_weight !== expected_invalid) begin
                $display("FAIL PE act=%0d weight=%b product=%0d invalid=%b",
                         a, w, product, invalid_weight);
                errors = errors + 1;
            end
        end
    endtask

    task check_tree;
        input integer value;
        integer t;
        reg seen_valid;
        begin
            for (i = 0; i < 64; i = i + 1)
                values[i*9 +: 9] = value;
            expected = value * 64;
            @(negedge clk);
            en = 1'b1;
            @(posedge clk);
            @(negedge clk);
            en = 1'b0;
            seen_valid = 1'b0;
            for (t = 0; t < 16; t = t + 1) begin
                @(posedge clk);
                #1;
                if (output_valid === 1'b1)
                    seen_valid = 1'b1;
            end
            if (!seen_valid || $signed(sum_out) !== expected) begin
                $display("FAIL tree value=%0d sum=%0d expected=%0d valid=%b",
                         value, $signed(sum_out), expected, seen_valid);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        clk = 0;
        rst = 1;
        en = 0;
        values = 0;
        act = 0;
        weight = 0;
        errors = 0;
        #12 rst = 0;

        check_pe(8'sd127, 2'b01, 9'sd127, 1'b0);
        check_pe(-8'sd128, 2'b11, 9'sd128, 1'b0);
        check_pe(-8'sd128, 2'b01, -9'sd128, 1'b0);
        check_pe(8'sd7, 2'b00, 9'sd0, 1'b0);
        check_pe(8'sd7, 2'b10, 9'sd0, 1'b1);
        check_tree(9'sd0);
        check_tree(9'sd127);
        check_tree(-9'sd128);

        if (errors == 0)
            $display("PASS: ternary PE encodings and balanced 64-value tree");
        else
            $fatal(1, "FAIL: %0d primitive error(s)", errors);
        $finish;
    end
endmodule
