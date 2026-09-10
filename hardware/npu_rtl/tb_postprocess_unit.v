`timescale 1ns / 1ps

module tb_postprocess_unit;
    reg clk;
    reg rst_n;
    reg start;
    reg signed [31:0] accumulator;
    reg signed [31:0] bias;
    reg signed [31:0] multiplier;
    reg [5:0] shift;
    reg relu;
    wire signed [31:0] value_out;
    wire signed [7:0] activation_out;
    wire output_valid;
    integer errors;
    integer wait_cycles;
    localparam integer EXPECTED_LATENCY = 6;
    localparam integer MAX_LATENCY = 8;

    postprocess_unit dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .accumulator(accumulator),
        .bias(bias),
        .multiplier(multiplier),
        .shift(shift),
        .relu(relu),
        .value_out(value_out),
        .activation_out(activation_out),
        .output_valid(output_valid)
    );

    always #5 clk = ~clk;

    task check_case;
        input [255:0] case_name;
        input signed [31:0] accumulator_value;
        input signed [31:0] bias_value;
        input signed [31:0] multiplier_value;
        input [5:0] shift_value;
        input relu_value;
        input signed [31:0] expected_value;
        input signed [7:0] expected_activation;
        integer observed_latency;
        reg previous_output_valid;
        begin
            @(negedge clk);
            accumulator = accumulator_value;
            bias = bias_value;
            multiplier = multiplier_value;
            shift = shift_value;
            relu = relu_value;
            start = 1'b1;
            @(posedge clk);
            @(negedge clk);
            start = 1'b0;

            observed_latency = 0;
            previous_output_valid = 1'b0;
            for (wait_cycles = 1; wait_cycles <= MAX_LATENCY;
                 wait_cycles = wait_cycles + 1) begin
                @(posedge clk);
                @(negedge clk);
                if (output_valid) begin
                    if (observed_latency == 0) begin
                        observed_latency = wait_cycles;
                        if (observed_latency != EXPECTED_LATENCY) begin
                            $display("FAIL %0s: observed latency=%0d edges expected latency=%0d edges",
                                     case_name, observed_latency, EXPECTED_LATENCY);
                            errors = errors + 1;
                        end
                    end else begin
                        $display("FAIL %0s: output_valid asserted again at latency=%0d edges; expected one pulse at latency=%0d edges",
                                 case_name, wait_cycles, EXPECTED_LATENCY);
                        errors = errors + 1;
                    end

                    if (wait_cycles == EXPECTED_LATENCY &&
                        (value_out !== expected_value ||
                         activation_out !== expected_activation)) begin
                        $display("FAIL %0s: value=%0d expected_value=%0d activation=%0d expected_activation=%0d",
                                 case_name, $signed(value_out), $signed(expected_value),
                                 $signed(activation_out), $signed(expected_activation));
                        errors = errors + 1;
                    end
                end

                if (previous_output_valid && output_valid) begin
                    $display("FAIL %0s: output_valid did not pulse; observed latency=%0d edges expected one-cycle pulse after latency=%0d edges",
                             case_name, observed_latency, EXPECTED_LATENCY);
                    errors = errors + 1;
                end
                previous_output_valid = output_valid;
            end

            if (observed_latency == 0) begin
                $display("FAIL %0s: timeout through %0d edges; observed latency=none expected latency=%0d edges",
                         case_name, MAX_LATENCY, EXPECTED_LATENCY);
                errors = errors + 1;
            end
        end
    endtask

    task check_back_to_back;
        integer observed_output_count;
        integer first_observed_latency;
        integer second_observed_latency;
        begin
            @(negedge clk);
            accumulator = 32'sd32;
            bias = 32'sd3;
            multiplier = 32'sd2;
            shift = 6'd1;
            relu = 1'b0;
            start = 1'b1;
            @(posedge clk);

            @(negedge clk);
            accumulator = -32'sd48;
            bias = 32'sd5;
            multiplier = 32'sd1;
            shift = 6'd0;
            relu = 1'b1;
            @(posedge clk);
            @(negedge clk);
            start = 1'b0;

            observed_output_count = 0;
            first_observed_latency = 0;
            second_observed_latency = 0;
            if (output_valid) begin
                observed_output_count = 1;
                first_observed_latency = 1;
                $display("FAIL back-to-back first output: observed latency=%0d edges expected latency=%0d edges",
                         first_observed_latency, EXPECTED_LATENCY);
                errors = errors + 1;
            end
            for (wait_cycles = 2; wait_cycles <= MAX_LATENCY;
                 wait_cycles = wait_cycles + 1) begin
                @(posedge clk);
                @(negedge clk);
                if (output_valid) begin
                    observed_output_count = observed_output_count + 1;
                    case (observed_output_count)
                        1: begin
                            first_observed_latency = wait_cycles;
                            if (first_observed_latency != EXPECTED_LATENCY) begin
                                $display("FAIL back-to-back first output: observed latency=%0d edges expected latency=%0d edges",
                                         first_observed_latency, EXPECTED_LATENCY);
                                errors = errors + 1;
                            end
                            if (wait_cycles == EXPECTED_LATENCY &&
                                (value_out !== 32'sd35 || activation_out !== 8'sd35)) begin
                                $display("FAIL back-to-back first output: value=%0d expected_value=35 activation=%0d expected_activation=35",
                                         $signed(value_out), $signed(activation_out));
                                errors = errors + 1;
                            end
                        end
                        2: begin
                            second_observed_latency = wait_cycles;
                            if (second_observed_latency != EXPECTED_LATENCY + 1) begin
                                $display("FAIL back-to-back second output: observed latency=%0d edges expected latency=%0d edges",
                                         second_observed_latency, EXPECTED_LATENCY + 1);
                                errors = errors + 1;
                            end
                            if (wait_cycles == EXPECTED_LATENCY + 1 &&
                                (value_out !== -32'sd43 || activation_out !== 8'sd0)) begin
                                $display("FAIL back-to-back second output: value=%0d expected_value=-43 activation=%0d expected_activation=0",
                                         $signed(value_out), $signed(activation_out));
                                errors = errors + 1;
                            end
                        end
                        default: begin
                            $display("FAIL back-to-back: extra output_valid at latency=%0d edges; expected outputs at latencies=%0d and %0d edges",
                                     wait_cycles, EXPECTED_LATENCY, EXPECTED_LATENCY + 1);
                            errors = errors + 1;
                        end
                    endcase
                end
            end

            if (first_observed_latency == 0) begin
                $display("FAIL back-to-back first output: timeout through %0d edges; observed latency=none expected latency=%0d edges",
                         MAX_LATENCY, EXPECTED_LATENCY);
                errors = errors + 1;
            end
            if (second_observed_latency == 0) begin
                $display("FAIL back-to-back second output: timeout through %0d edges; observed latency=none expected latency=%0d edges",
                         MAX_LATENCY, EXPECTED_LATENCY + 1);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        accumulator = 0;
        bias = 0;
        multiplier = 0;
        shift = 0;
        relu = 0;
        errors = 0;

        repeat (2) @(posedge clk);
        @(negedge clk);
        if (output_valid !== 1'b0 || value_out !== 32'sd0 ||
            activation_out !== 8'sd0) begin
            $display("FAIL reset: output_valid=%b value=%0d activation=%0d expected output_valid=0 value=0 activation=0",
                     output_valid, $signed(value_out), $signed(activation_out));
            errors = errors + 1;
        end
        rst_n = 1'b1;

        check_case("identity positive", 32'sd37, -32'sd5, 32'sd1, 6'd0,
                   1'b0, 32'sd32, 8'sd32);
        check_case("identity negative", -32'sd37, 32'sd5, 32'sd1, 6'd0,
                   1'b0, -32'sd32, -8'sd32);

        check_case("positive 2 shift 1 exact", 32'sd2, 32'sd0, 32'sd1, 6'd1,
                   1'b0, 32'sd1, 8'sd1);
        check_case("positive 3 shift 1 tie", 32'sd3, 32'sd0, 32'sd1, 6'd1,
                   1'b0, 32'sd2, 8'sd2);
        check_case("positive 4 shift 2 exact", 32'sd4, 32'sd0, 32'sd1, 6'd2,
                   1'b0, 32'sd1, 8'sd1);
        check_case("positive 5 shift 2 non-tie", 32'sd5, 32'sd0, 32'sd1, 6'd2,
                   1'b0, 32'sd1, 8'sd1);
        check_case("positive 6 shift 2 tie", 32'sd6, 32'sd0, 32'sd1, 6'd2,
                   1'b0, 32'sd2, 8'sd2);
        check_case("positive 7 shift 2 non-tie", 32'sd7, 32'sd0, 32'sd1, 6'd2,
                   1'b0, 32'sd2, 8'sd2);

        check_case("negative 2 shift 1 exact", -32'sd2, 32'sd0, 32'sd1, 6'd1,
                   1'b0, -32'sd1, -8'sd1);
        check_case("negative 4 shift 2 exact", -32'sd4, 32'sd0, 32'sd1, 6'd2,
                   1'b0, -32'sd1, -8'sd1);
        check_case("negative 5 shift 2 non-tie", -32'sd5, 32'sd0, 32'sd1, 6'd2,
                   1'b0, -32'sd1, -8'sd1);
        check_case("negative 6 shift 2 tie", -32'sd6, 32'sd0, 32'sd1, 6'd2,
                   1'b0, -32'sd2, -8'sd2);
        check_case("negative 7 shift 2 non-tie", -32'sd7, 32'sd0, 32'sd1, 6'd2,
                   1'b0, -32'sd2, -8'sd2);

        check_case("INT32 positive saturation", 32'sh7fffffff, 32'sd0, 32'sd2, 6'd0,
                   1'b0, 32'sh7fffffff, 8'sh7f);
        check_case("INT32 negative saturation", 32'sh80000000, 32'sd0, 32'sd2, 6'd0,
                   1'b0, 32'sh80000000, 8'sh80);
        check_case("INT8 positive saturation", 32'sd200, 32'sd0, 32'sd1, 6'd0,
                   1'b0, 32'sd200, 8'sh7f);
        check_case("INT8 negative saturation", -32'sd200, 32'sd0, 32'sd1, 6'd0,
                   1'b0, -32'sd200, 8'sh80);

        check_case("ReLU clamps negative activation", -32'sd7, 32'sd0, 32'sd1, 6'd0,
                   1'b1, -32'sd7, 8'sd0);
        check_case("ReLU preserves positive activation", 32'sd7, 32'sd0, 32'sd1, 6'd0,
                   1'b1, 32'sd7, 8'sd7);

        check_back_to_back;

        if (errors == 0) begin
            $display("PASS: postprocess arithmetic contract");
            $finish;
        end
        $fatal(1, "FAIL: %0d postprocess case(s)", errors);
    end
endmodule
