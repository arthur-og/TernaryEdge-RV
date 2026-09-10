`timescale 1ns / 1ps

/* Registered balanced reduction tree for a power-of-two PE count. */
module adder_tree_power_of_two #(
    parameter integer NUM_INPUTS = 64,
    parameter integer IN_WIDTH   = 9,
    parameter integer STAGES     = $clog2(NUM_INPUTS),
    parameter integer SUM_WIDTH  = IN_WIDTH + STAGES
) (
    input  wire                              clk,
    input  wire                              rst,
    input  wire                              en,
    input  wire signed [IN_WIDTH*NUM_INPUTS-1:0] values_in,
    output reg  signed [SUM_WIDTH-1:0]       sum_out,
    output reg                               output_valid
);
    reg signed [SUM_WIDTH-1:0] stage_reg [0:STAGES*NUM_INPUTS-1];
    wire signed [SUM_WIDTH-1:0] stage_value [0:STAGES*NUM_INPUTS-1];
    reg [STAGES-1:0] valid_pipe;

    initial begin
        if ((NUM_INPUTS < 2) || ((NUM_INPUTS & (NUM_INPUTS - 1)) != 0))
            $fatal(1, "adder_tree_power_of_two requires a power-of-two input count");
    end

    genvar level;
    genvar node;
    generate
        for (node = 0; node < NUM_INPUTS / 2; node = node + 1) begin : gen_input_sum
            assign stage_value[node] =
                {{(SUM_WIDTH-IN_WIDTH){values_in[(2*node)*IN_WIDTH+IN_WIDTH-1]}},
                 values_in[(2*node)*IN_WIDTH +: IN_WIDTH]} +
                {{(SUM_WIDTH-IN_WIDTH){values_in[(2*node+1)*IN_WIDTH+IN_WIDTH-1]}},
                 values_in[(2*node+1)*IN_WIDTH +: IN_WIDTH]};
        end
        for (level = 1; level < STAGES; level = level + 1) begin : gen_tree_level
            for (node = 0; node < (NUM_INPUTS >> (level + 1)); node = node + 1) begin : gen_node_sum
                assign stage_value[level*NUM_INPUTS+node] =
                    stage_reg[(level-1)*NUM_INPUTS+2*node] +
                    stage_reg[(level-1)*NUM_INPUTS+2*node+1];
            end
        end
    endgenerate

    integer i;
    integer level_index;
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < STAGES*NUM_INPUTS; i = i + 1)
                stage_reg[i] <= 0;
            sum_out <= 0;
            valid_pipe <= 0;
            output_valid <= 1'b0;
        end else begin
            valid_pipe <= {valid_pipe[STAGES-2:0], en};
            output_valid <= valid_pipe[STAGES-1];
            if (en) begin
                for (i = 0; i < NUM_INPUTS / 2; i = i + 1)
                    stage_reg[i] <= stage_value[i];
            end
            for (level_index = 1; level_index < STAGES; level_index = level_index + 1)
                for (i = 0; i < (NUM_INPUTS >> (level_index + 1)); i = i + 1)
                    stage_reg[level_index*NUM_INPUTS+i] <= stage_value[level_index*NUM_INPUTS+i];
            sum_out <= stage_reg[(STAGES-1)*NUM_INPUTS];
        end
    end
endmodule

/* Six-stage 64-input compatibility wrapper. */
module adder_tree_64 #(
    parameter IN_WIDTH = 9
) (
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         en,
    input  wire signed [IN_WIDTH*64-1:0] values_in,
    output wire signed [IN_WIDTH+6-1:0] sum_out,
    output wire                         output_valid
);
    adder_tree_power_of_two #(
        .NUM_INPUTS(64),
        .IN_WIDTH  (IN_WIDTH)
    ) u_generic_tree (
        .clk         (clk),
        .rst         (rst),
        .en          (en),
        .values_in   (values_in),
        .sum_out     (sum_out),
        .output_valid(output_valid)
    );
endmodule
