`timescale 1ns / 1ps
`include "npu_v2_pkg.v"

/*
 * Canonical autonomous NPU v2.
 *
 * The CPU writes one input address, one output address and a table of layer
 * descriptors, then writes START once.  Only the first input is fetched from
 * external RAM.  Hidden-layer results alternate between the two local INT8
 * buffers; the CPU is not involved at layer boundaries.
 */
module npu_ternaria_top_v2 #(
    parameter integer NUM_PES          = `NPU_NUM_PES,
    parameter integer ACT_BUFFER_SIZE  = `NPU_ACT_BUFFER_SIZE,
    parameter integer MAX_LAYERS       = `NPU_MAX_LAYERS
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [31:0] wb_s_adr_i,
    input  wire [31:0] wb_s_dat_i,
    input  wire [3:0]  wb_s_sel_i,
    input  wire        wb_s_we_i,
    input  wire        wb_s_cyc_i,
    input  wire        wb_s_stb_i,
    output reg  [31:0] wb_s_dat_o,
    output reg         wb_s_ack_o,
    output reg         wb_s_err_o,

    output wire [31:0] wb_m_adr_o,
    output wire [31:0] wb_m_dat_o,
    output wire [3:0]  wb_m_sel_o,
    output wire        wb_m_we_o,
    output wire        wb_m_cyc_o,
    output wire        wb_m_stb_o,
    output wire [2:0]  wb_m_cti_o,
    output wire [1:0]  wb_m_bte_o,
    input  wire [31:0] wb_m_dat_i,
    input  wire        wb_m_ack_i,
    input  wire        wb_m_err_i,

    output reg         irq_out
);
    localparam integer WEIGHTS_PER_WORD = 16;
    localparam integer BYTES_PER_WORD = 4;
    localparam integer ACTS_PER_WORD = 4;
    localparam integer PE_COUNT_WIDTH = $clog2(NUM_PES + 1);
    localparam integer WORDS_PER_TILE = NUM_PES / WEIGHTS_PER_WORD;
    localparam integer TILE_BYTES = WORDS_PER_TILE * BYTES_PER_WORD;
    localparam integer TREE_STAGES = $clog2(NUM_PES);
    localparam integer TREE_SUM_WIDTH = `NPU_PROD_WIDTH + TREE_STAGES;
    localparam integer ZERO_TREE_SUM_WIDTH = 2 + TREE_STAGES;
    localparam integer TILE_INDEX_WIDTH = (WORDS_PER_TILE <= 1) ? 1 : $clog2(WORDS_PER_TILE);
    localparam integer ACT_BANK_DEPTH = (ACT_BUFFER_SIZE + NUM_PES - 1) / NUM_PES;
    localparam integer PE_BANK_INDEX_WIDTH = (NUM_PES <= 1) ? 1 : $clog2(NUM_PES);
    localparam integer ACT_BANK_INDEX_WIDTH = (ACT_BANK_DEPTH <= 1) ? 1 : $clog2(ACT_BANK_DEPTH);
    localparam integer LAYER_INDEX_WIDTH = (MAX_LAYERS <= 1) ? 1 : $clog2(MAX_LAYERS);
    localparam [10:0] RESULT_WINDOW_SIZE_VALUE = 11'd8;
    localparam [10:0] NUM_PES_VALUE = NUM_PES[10:0];
    localparam [10:0] ACT_BUFFER_SIZE_VALUE = ACT_BUFFER_SIZE[10:0];
    localparam [10:0] WEIGHTS_PER_WORD_VALUE = WEIGHTS_PER_WORD[10:0];
    localparam [10:0] ACTS_PER_WORD_VALUE = ACTS_PER_WORD[10:0];
    localparam [10:0] WORDS_PER_TILE_VALUE = WORDS_PER_TILE[10:0];
    localparam [2:0] TILE_WORD_COUNT = WORDS_PER_TILE[2:0];
    localparam [PE_COUNT_WIDTH-1:0] NUM_PES_COUNT = NUM_PES[PE_COUNT_WIDTH-1:0];
    localparam [31:0] CAPABILITY_VALUE = 32'h0008_0400 | NUM_PES;

    initial begin
        if ((NUM_PES != 16) && (NUM_PES != 32) && (NUM_PES != 64))
            $fatal(1, "npu_ternaria_top_v2 NUM_PES must be 16, 32, or 64");
        if ((ACT_BUFFER_SIZE < 1) || (ACT_BUFFER_SIZE > `NPU_ACT_BUFFER_SIZE))
            $fatal(1, "npu_ternaria_top_v2 ACT_BUFFER_SIZE must be 1..1024");
        if ((MAX_LAYERS < 1) || (MAX_LAYERS > `NPU_MAX_LAYERS))
            $fatal(1, "npu_ternaria_top_v2 MAX_LAYERS must be 1..8");
    end

    localparam [31:0] ERR_NONE       = 32'd0;
    localparam [31:0] ERR_BUSY       = 32'h0000_0001;
    localparam [31:0] ERR_CONFIG     = 32'h0000_0002;
    localparam [31:0] ERR_DMA        = 32'h0000_0003;
    localparam [31:0] ERR_WEIGHT     = 32'h0000_0004;

    reg [4:0] state;
    reg [LAYER_INDEX_WIDTH-1:0] cur_layer;
    reg [10:0] cur_output;
    reg [10:0] cur_batch;
    reg [2:0] tile_word;
    reg [2:0] tile_words;
    reg [10:0] input_word;
    reg active_buffer;

    reg [31:0] weight_row_stride_bytes;
    reg [31:0] weight_row_base_addr;
    reg [31:0] weight_batch_base_addr;

    reg [31:0] cfg_input_addr;
    reg [31:0] cfg_output_addr;
    reg [31:0] cfg_layer_count;
    reg [31:0] cfg_layer_index;
    reg [31:0] cfg_mac_cfg;
    reg [31:0] cfg_result;
    reg [31:0] error_info;
    reg [15:0] zero_counter;
    reg done_flag;
    reg error_flag;
    reg irq_pending;

    reg [10:0] layer_inputs [0:MAX_LAYERS-1];
    reg [10:0] layer_outputs[0:MAX_LAYERS-1];
    reg [31:0] layer_quant  [0:MAX_LAYERS-1];
    reg [31:0] layer_weights[0:MAX_LAYERS-1];
    reg [31:0] layer_bias   [0:MAX_LAYERS-1];
    reg [31:0] layer_scale  [0:MAX_LAYERS-1];

    reg signed [7:0] act_buffer_a[0:NUM_PES-1][0:ACT_BANK_DEPTH-1];
    reg signed [7:0] act_buffer_b[0:NUM_PES-1][0:ACT_BANK_DEPTH-1];
    reg signed [31:0] acc_reg;
    reg signed [31:0] result_window_shadow[0:7];
    reg [31:0] weight_tile[0:WORDS_PER_TILE-1];

    reg signed [31:0] bias_value;
    reg signed [31:0] scale_value;
    reg signed [31:0] final_value;

    localparam [1:0] SLAVE_IDLE = 2'd0;
    localparam [1:0] SLAVE_RESPONSE = 2'd1;
    localparam [1:0] SLAVE_WAIT_RELEASE = 2'd2;

    reg [1:0] slave_state;
    reg [15:0] slave_req_offset;
    reg [31:0] slave_req_wdata;
    reg [3:0] slave_req_sel;
    reg slave_req_we;

    wire [15:0] local_offset = slave_req_offset;
    wire address_in_window = (wb_s_adr_i[31:16] == 16'd0);
    wire slave_valid = wb_s_cyc_i && wb_s_stb_i && address_in_window;
    wire slave_accept = (slave_state == SLAVE_RESPONSE);
    wire cmd_start = slave_accept && slave_req_we &&
                      (slave_req_offset == {8'd0, `REG_CONTROL}) && slave_req_sel[0] &&
                      slave_req_wdata[`CONTROL_START];
    wire cmd_clear = slave_accept && slave_req_we &&
                      (slave_req_offset == {8'd0, `REG_CONTROL}) && slave_req_sel[0] &&
                      slave_req_wdata[`CONTROL_CLEAR_IRQ];


    wire dma_busy;
    wire busy_flag = ((state != `ST_IDLE) && (state != `ST_DONE) &&
                      (state != `ST_ERROR)) || dma_busy;
    wire [LAYER_INDEX_WIDTH-1:0] descriptor_index =
        (cfg_layer_index >= MAX_LAYERS) ? {LAYER_INDEX_WIDTH{1'b0}} :
        cfg_layer_index[LAYER_INDEX_WIDTH-1:0];
    wire [10:0] descriptor_index_value =
        {{(11-LAYER_INDEX_WIDTH){1'b0}}, descriptor_index};
    wire [2:0] result_window_index =
        (descriptor_index_value >= ACT_BUFFER_SIZE_VALUE) ? 3'd0 :
        descriptor_index_value[2:0];
    wire [10:0] active_inputs = layer_inputs[cur_layer];
    wire [10:0] active_outputs = layer_outputs[cur_layer];
    wire [31:0] active_weight_addr = layer_weights[cur_layer];
    wire [31:0] active_bias_addr = layer_bias[cur_layer];
    wire [31:0] active_scale_addr = layer_scale[cur_layer];
    wire [5:0] active_shift = layer_quant[cur_layer][5:0];
    wire active_relu = layer_quant[cur_layer][8];
    wire [10:0] words_per_output =
        (active_inputs + WEIGHTS_PER_WORD_VALUE - 11'd1) / WEIGHTS_PER_WORD_VALUE;
    wire [10:0] batch_count =
        (active_inputs + NUM_PES_VALUE - 11'd1) / NUM_PES_VALUE;
    wire [10:0] input_word_count =
        (layer_inputs[0] + ACTS_PER_WORD_VALUE - 11'd1) / ACTS_PER_WORD_VALUE;
    wire [ACT_BANK_INDEX_WIDTH-1:0] current_batch_row =
        cur_batch[ACT_BANK_INDEX_WIDTH-1:0];
    wire [PE_BANK_INDEX_WIDTH-1:0] current_output_bank =
        cur_output[PE_BANK_INDEX_WIDTH-1:0];
    wire [ACT_BANK_INDEX_WIDTH-1:0] current_output_row =
        cur_output[PE_BANK_INDEX_WIDTH +: ACT_BANK_INDEX_WIDTH];
    wire [31:0] input_word_byte_offset = {19'd0, input_word, 2'b00};
    wire [31:0] output_word_byte_offset = {19'd0, cur_output, 2'b00};
    wire [31:0] tile_word_byte_offset = {27'd0, tile_word, 2'b00};

    function [PE_COUNT_WIDTH-1:0] valid_lanes_for_batch;
        input [10:0] input_count;
        input [10:0] batch_index;
        reg [10:0] input_base;
        reg [10:0] remaining_inputs;
        begin
            input_base = batch_index * NUM_PES_VALUE;
            if (input_count <= input_base)
                valid_lanes_for_batch = {PE_COUNT_WIDTH{1'b0}};
            else begin
                remaining_inputs = input_count - input_base;
                if (remaining_inputs >= NUM_PES_VALUE)
                    valid_lanes_for_batch = NUM_PES_COUNT;
                else
                    valid_lanes_for_batch = remaining_inputs[PE_COUNT_WIDTH-1:0];
            end
        end
    endfunction

    function [2:0] tile_words_for_batch;
        input [10:0] input_count;
        input [10:0] batch_index;
        reg [10:0] word_count;
        reg [10:0] word_base;
        reg [10:0] remaining_words;
        begin
            word_count = (input_count + WEIGHTS_PER_WORD_VALUE - 11'd1) /
                         WEIGHTS_PER_WORD_VALUE;
            word_base = batch_index * WORDS_PER_TILE_VALUE;
            if (word_count <= word_base)
                tile_words_for_batch = 3'd0;
            else begin
                remaining_words = word_count - word_base;
                if (remaining_words >= WORDS_PER_TILE_VALUE)
                    tile_words_for_batch = TILE_WORD_COUNT;
                else
                    tile_words_for_batch = remaining_words[2:0];
            end
        end
    endfunction

    wire [31:0] current_layer_number =
        {{(32-LAYER_INDEX_WIDTH){1'b0}}, cur_layer};
    wire final_layer = (current_layer_number + 32'd1 >= cfg_layer_count);

    /* DMA command channel: one stable 32-bit Wishbone Classic beat. */
    reg        dma_cmd_valid;
    reg [31:0] dma_cmd_addr;
    reg [31:0] dma_cmd_wdata;
    reg        dma_cmd_we;
    reg [3:0]  dma_cmd_sel;
    wire       dma_cmd_ready;
    wire       dma_rsp_valid;
    wire [31:0] dma_rsp_data;
    wire       dma_rsp_err;

    wishbone_master u_dma (
        .clk        (clk),
        .rst_n      (rst_n),
        .cmd_valid  (dma_cmd_valid),
        .cmd_ready  (dma_cmd_ready),
        .cmd_addr   (dma_cmd_addr),
        .cmd_wdata  (dma_cmd_wdata),
        .cmd_we     (dma_cmd_we),
        .cmd_sel    (dma_cmd_sel),
        .rsp_valid  (dma_rsp_valid),
        .rsp_rdata  (dma_rsp_data),
        .rsp_err    (dma_rsp_err),
        .busy       (dma_busy),
        .wb_adr_o   (wb_m_adr_o),
        .wb_dat_o   (wb_m_dat_o),
        .wb_sel_o   (wb_m_sel_o),
        .wb_we_o    (wb_m_we_o),
        .wb_cyc_o   (wb_m_cyc_o),
        .wb_stb_o   (wb_m_stb_o),
        .wb_cti_o   (wb_m_cti_o),
        .wb_bte_o   (wb_m_bte_o),
        .wb_dat_i   (wb_m_dat_i),
        .wb_ack_i   (wb_m_ack_i),
        .wb_err_i   (wb_m_err_i)
    );

    /* The tile is assembled from local buffers and packed weight words. */
    reg [NUM_PES*`NPU_ACT_WIDTH-1:0] mac_acts;
    reg [NUM_PES*2-1:0] mac_weights;
    reg signed [NUM_PES*2-1:0] zero_terms;
    wire [NUM_PES*`NPU_PROD_WIDTH-1:0] mac_products;
    wire [NUM_PES-1:0] invalid_weights;
    integer lane;
    reg [PE_COUNT_WIDTH-1:0] valid_lanes;
    wire [NUM_PES-1:0] invalid_active = invalid_weights;
    always @* begin
        mac_acts = {(NUM_PES*`NPU_ACT_WIDTH){1'b0}};
        mac_weights = {(NUM_PES*2){1'b0}};
        zero_terms = {(NUM_PES*2){1'b0}};
        for (lane = 0; lane < NUM_PES; lane = lane + 1) begin
            if (lane < valid_lanes) begin
                if (!active_buffer)
                    mac_acts[lane*`NPU_ACT_WIDTH +: `NPU_ACT_WIDTH] =
                        act_buffer_a[lane][current_batch_row];
                else
                    mac_acts[lane*`NPU_ACT_WIDTH +: `NPU_ACT_WIDTH] =
                        act_buffer_b[lane][current_batch_row];
                mac_weights[lane*2 +: 2] =
                    weight_tile[lane/WEIGHTS_PER_WORD][(lane%WEIGHTS_PER_WORD)*2 +: 2];
                if (weight_tile[lane/WEIGHTS_PER_WORD][(lane%WEIGHTS_PER_WORD)*2 +: 2] == 2'b00)
                    zero_terms[lane*2 +: 2] = 2'b01;
            end
        end
    end

    ternary_mac_array #(
        .NUM_MACS(NUM_PES), .ACT_WIDTH(`NPU_ACT_WIDTH),
        .PROD_WIDTH(`NPU_PROD_WIDTH)
    ) u_mac_array (
        .acts           (mac_acts),
        .weights        (mac_weights),
        .products       (mac_products),
        .invalid_weights(invalid_weights)
    );

    wire signed [TREE_SUM_WIDTH-1:0] tree_sum;
    wire tree_valid;
    adder_tree_power_of_two #(
        .NUM_INPUTS(NUM_PES),
        .IN_WIDTH  (`NPU_PROD_WIDTH)
    ) u_adder_tree (
        .clk         (clk),
        .rst         (!rst_n),
        .en          (state == `ST_COMPUTE_LAUNCH),
        .values_in   (mac_products),
        .sum_out     (tree_sum),
        .output_valid(tree_valid)
    );

    wire signed [ZERO_TREE_SUM_WIDTH-1:0] zero_tree_sum;
    wire zero_tree_valid;
    adder_tree_power_of_two #(
        .NUM_INPUTS(NUM_PES),
        .IN_WIDTH  (2)
    ) u_zero_tree (
        .clk         (clk),
        .rst         (!rst_n),
        .en          (state == `ST_COMPUTE_LAUNCH),
        .values_in   (zero_terms),
        .sum_out     (zero_tree_sum),
        .output_valid(zero_tree_valid)
    );

    wire signed [31:0] batch_sum_extended =
        {{(`NPU_ACC_WIDTH-TREE_SUM_WIDTH){tree_sum[TREE_SUM_WIDTH-1]}}, tree_sum};
    wire signed [31:0] acc_reg_next = acc_reg + batch_sum_extended;
    wire [15:0] batch_zero_sum =
        {{(16-ZERO_TREE_SUM_WIDTH){1'b0}}, zero_tree_sum};

    wire postprocess_start = (state == `ST_POSTPROCESS);
    wire postprocess_output_valid;
    wire signed [31:0] post_value;
    wire signed [7:0] post_activation;
    postprocess_unit u_postprocess (
        .clk          (clk),
        .rst_n        (rst_n),
        .start        (postprocess_start),
        .accumulator   (acc_reg),
        .bias         (bias_value),
        .multiplier   (scale_value),
        .shift        (active_shift),
        .relu         (active_relu && !final_layer),
        .value_out    (post_value),
        .activation_out(post_activation),
        .output_valid (postprocess_output_valid)
    );

    /* Command generation is combinational; the DMA itself accepts only when idle. */
    always @* begin
        dma_cmd_valid = 1'b0;
        dma_cmd_addr  = 32'd0;
        dma_cmd_wdata = 32'd0;
        dma_cmd_we    = 1'b0;
        dma_cmd_sel   = 4'b1111;
        case (state)
            `ST_INPUT_CMD: begin
                if (input_word < input_word_count) begin
                    dma_cmd_valid = 1'b1;
                    dma_cmd_addr = cfg_input_addr + input_word_byte_offset;
                end
            end
            `ST_WEIGHT_CMD: begin
                if (tile_word < tile_words) begin
                    dma_cmd_valid = 1'b1;
                    dma_cmd_addr = weight_batch_base_addr + tile_word_byte_offset;
                end
            end
            `ST_BIAS_CMD: begin
                if (active_bias_addr != 0) begin
                    dma_cmd_valid = 1'b1;
                    dma_cmd_addr = active_bias_addr + output_word_byte_offset;
                end
            end
            `ST_SCALE_CMD: begin
                if (active_scale_addr != 0) begin
                    dma_cmd_valid = 1'b1;
                    dma_cmd_addr = active_scale_addr + output_word_byte_offset;
                end
            end
            `ST_OUTPUT_CMD: begin
                dma_cmd_valid = 1'b1;
                dma_cmd_addr = cfg_output_addr + output_word_byte_offset;
                dma_cmd_wdata = final_value;
                dma_cmd_we = 1'b1;
            end
            default: begin
            end
        endcase
    end

    function [31:0] merge_bytes;
        input [31:0] old_value;
        input [31:0] new_value;
        input [3:0]  sel;
        integer b;
        begin
            merge_bytes = old_value;
            for (b = 0; b < 4; b = b + 1)
                if (sel[b]) merge_bytes[b*8 +: 8] = new_value[b*8 +: 8];
        end
    endfunction

    function [10:0] merge_count;
        input [10:0] old_value;
        input [31:0] new_value;
        input [3:0]  sel;
        begin
            merge_count = old_value;
            if (sel[0]) merge_count[7:0] = new_value[7:0];
            if (sel[1]) merge_count[10:8] = new_value[10:8];
            if (sel[2] || sel[3]) merge_count = merge_count;
            if (|new_value[31:11]) merge_count[10:8] = new_value[10:8];
        end
    endfunction

    wire [31:0] status_value = {
        3'd0, state[4:0], zero_counter[7:0],
        {{(8-LAYER_INDEX_WIDTH){1'b0}}, cur_layer},
        4'd0,
        error_flag, done_flag, irq_pending, busy_flag
    };
    reg [31:0] slave_read_data;
    always @* begin
        slave_read_data = 32'h0000_0000;
        case (local_offset)
            {8'd0, `REG_STATUS}:        slave_read_data = status_value;
            {8'd0, `REG_INPUT_ADDR}:    slave_read_data = cfg_input_addr;
            {8'd0, `REG_OUTPUT_ADDR}:   slave_read_data = cfg_output_addr;
            {8'd0, `REG_WEIGHT_ADDR}:   slave_read_data = layer_weights[descriptor_index];
            {8'd0, `REG_BIAS_ADDR}:     slave_read_data = layer_bias[descriptor_index];
            {8'd0, `REG_SCALE_ADDR}:    slave_read_data = layer_scale[descriptor_index];
            {8'd0, `REG_LAYER_COUNT}:   slave_read_data = cfg_layer_count;
            {8'd0, `REG_LAYER_INDEX}:   slave_read_data = cfg_layer_index;
            {8'd0, `REG_LAYER_INPUTS}:  slave_read_data = {21'd0, layer_inputs[descriptor_index]};
            {8'd0, `REG_LAYER_OUTPUTS}: slave_read_data = {21'd0, layer_outputs[descriptor_index]};
            {8'd0, `REG_LAYER_QUANT}:   slave_read_data = layer_quant[descriptor_index];
            {8'd0, `REG_RESULT}:        slave_read_data = cfg_result;
            {8'd0, `REG_RESULT_WINDOW}: slave_read_data = result_window_shadow[result_window_index];
            {8'd0, `REG_ERROR_INFO}:    slave_read_data = error_info;
            {8'd0, `REG_CAPABILITIES}:  slave_read_data = CAPABILITY_VALUE;
            {8'd0, `REG_MAC_CFG}:       slave_read_data = cfg_mac_cfg;
            default:            slave_read_data = 32'h0000_0000;
        endcase
    end

    function is_valid_reg;
        input [15:0] address;
        begin
            case (address)
                {8'd0, `REG_STATUS}, {8'd0, `REG_CONTROL},
                {8'd0, `REG_INPUT_ADDR}, {8'd0, `REG_OUTPUT_ADDR},
                {8'd0, `REG_WEIGHT_ADDR}, {8'd0, `REG_BIAS_ADDR},
                {8'd0, `REG_SCALE_ADDR}, {8'd0, `REG_LAYER_COUNT},
                {8'd0, `REG_LAYER_INDEX}, {8'd0, `REG_LAYER_INPUTS},
                {8'd0, `REG_LAYER_OUTPUTS}, {8'd0, `REG_LAYER_QUANT},
                {8'd0, `REG_RESULT}, {8'd0, `REG_RESULT_WINDOW},
                {8'd0, `REG_ERROR_INFO}, {8'd0, `REG_CAPABILITIES},
                {8'd0, `REG_MAC_CFG}: is_valid_reg = 1'b1;
                default: is_valid_reg = 1'b0;
            endcase
        end
    endfunction

    /* MMIO slave. Capture a complete request before decoding or executing it. */
    integer cfg_i;
    always @(posedge clk) begin
        if (!rst_n) begin
            slave_state <= SLAVE_IDLE;
            slave_req_offset <= 16'd0;
            slave_req_wdata <= 32'd0;
            slave_req_sel <= 4'd0;
            slave_req_we <= 1'b0;
            wb_s_ack_o <= 1'b0;
            wb_s_err_o <= 1'b0;
            wb_s_dat_o <= 32'd0;
            cfg_input_addr <= 32'd0;
            cfg_output_addr <= 32'd0;
            cfg_layer_count <= 32'd0;
            cfg_layer_index <= 32'd0;
            cfg_mac_cfg <= NUM_PES;
            for (cfg_i = 0; cfg_i < MAX_LAYERS; cfg_i = cfg_i + 1) begin
                layer_inputs[cfg_i] <= 11'd0;
                layer_outputs[cfg_i] <= 11'd0;
                layer_quant[cfg_i] <= 32'd0;
                layer_weights[cfg_i] <= 32'd0;
                layer_bias[cfg_i] <= 32'd0;
                layer_scale[cfg_i] <= 32'd0;
            end
        end else begin
            wb_s_ack_o <= 1'b0;
            wb_s_err_o <= 1'b0;
            case (slave_state)
                SLAVE_IDLE: begin
                    if (slave_valid) begin
                        slave_req_offset <= wb_s_adr_i[15:0];
                        slave_req_wdata <= wb_s_dat_i;
                        slave_req_sel <= wb_s_sel_i;
                        slave_req_we <= wb_s_we_i;
                        slave_state <= SLAVE_RESPONSE;
                    end
                end
                SLAVE_RESPONSE: begin
                    if (!is_valid_reg(slave_req_offset)) begin
                        wb_s_err_o <= 1'b1;
                    end else begin
                        wb_s_ack_o <= 1'b1;
                        if (!slave_req_we)
                            wb_s_dat_o <= slave_read_data;
                        else begin
                            case (slave_req_offset)
                                {8'd0, `REG_INPUT_ADDR}:
                                    cfg_input_addr <= merge_bytes(cfg_input_addr, slave_req_wdata, slave_req_sel);
                                {8'd0, `REG_OUTPUT_ADDR}:
                                    cfg_output_addr <= merge_bytes(cfg_output_addr, slave_req_wdata, slave_req_sel);
                                {8'd0, `REG_WEIGHT_ADDR}:
                                    layer_weights[descriptor_index] <= merge_bytes(layer_weights[descriptor_index], slave_req_wdata, slave_req_sel);
                                {8'd0, `REG_BIAS_ADDR}:
                                    layer_bias[descriptor_index] <= merge_bytes(layer_bias[descriptor_index], slave_req_wdata, slave_req_sel);
                                {8'd0, `REG_SCALE_ADDR}:
                                    layer_scale[descriptor_index] <= merge_bytes(layer_scale[descriptor_index], slave_req_wdata, slave_req_sel);
                                {8'd0, `REG_LAYER_COUNT}:
                                    cfg_layer_count <= merge_bytes(cfg_layer_count, slave_req_wdata, slave_req_sel);
                                {8'd0, `REG_LAYER_INDEX}:
                                    cfg_layer_index <= merge_bytes(cfg_layer_index, slave_req_wdata, slave_req_sel);
                                {8'd0, `REG_LAYER_INPUTS}:
                                    layer_inputs[descriptor_index] <= merge_count(layer_inputs[descriptor_index], slave_req_wdata, slave_req_sel);
                                {8'd0, `REG_LAYER_OUTPUTS}:
                                    layer_outputs[descriptor_index] <= merge_count(layer_outputs[descriptor_index], slave_req_wdata, slave_req_sel);
                                {8'd0, `REG_LAYER_QUANT}:
                                    layer_quant[descriptor_index] <= merge_bytes(layer_quant[descriptor_index], slave_req_wdata, slave_req_sel);
                                {8'd0, `REG_MAC_CFG}:
                                    cfg_mac_cfg <= merge_bytes(cfg_mac_cfg, slave_req_wdata, slave_req_sel);
                                default: begin
                                end
                            endcase
                        end
                    end
                    slave_state <= SLAVE_WAIT_RELEASE;
                end
                SLAVE_WAIT_RELEASE: begin
                    if (!wb_s_cyc_i || !wb_s_stb_i)
                        slave_state <= SLAVE_IDLE;
                end
                default: slave_state <= SLAVE_IDLE;
            endcase
        end
    end

    function valid_configuration;
        input [31:0] layer_count_value;
        integer check_i;
        begin
            valid_configuration = 1'b1;
            if ((layer_count_value == 0) || (layer_count_value > MAX_LAYERS) ||
                (cfg_mac_cfg != NUM_PES) || (cfg_input_addr[1:0] != 0) ||
                (cfg_output_addr[1:0] != 0))
                valid_configuration = 1'b0;
            for (check_i = 0; check_i < MAX_LAYERS; check_i = check_i + 1) begin
                if (check_i < layer_count_value) begin
                    if ((layer_inputs[check_i] == 0) ||
                        (layer_outputs[check_i] == 0) ||
                        (layer_inputs[check_i] > ACT_BUFFER_SIZE_VALUE) ||
                        (layer_outputs[check_i] > ACT_BUFFER_SIZE_VALUE) ||
                        (layer_weights[check_i][1:0] != 0) ||
                        (layer_bias[check_i][1:0] != 0) ||
                        (layer_scale[check_i][1:0] != 0))
                        valid_configuration = 1'b0;
                    if ((check_i > 0) &&
                        (layer_inputs[check_i] != layer_outputs[check_i-1]))
                        valid_configuration = 1'b0;
                end
            end
        end
    endfunction

    integer i;
    integer byte_lane;
    always @(posedge clk) begin
        if (!rst_n) begin
            state <= `ST_IDLE;
            cur_layer <= 0;
            cur_output <= 0;
            cur_batch <= 0;
            tile_word <= 0;
            tile_words <= 0;
            input_word <= 0;
            active_buffer <= 1'b0;
            weight_row_stride_bytes <= 32'd0;
            weight_row_base_addr <= 32'd0;
            weight_batch_base_addr <= 32'd0;
            valid_lanes <= {PE_COUNT_WIDTH{1'b0}};
            bias_value <= 0;
            scale_value <= 32'sd1;
            final_value <= 0;
            cfg_result <= 0;
            error_info <= ERR_NONE;
            zero_counter <= 0;
            done_flag <= 1'b0;
            error_flag <= 1'b0;
            irq_pending <= 1'b0;
            irq_out <= 1'b0;
            acc_reg <= 0;
            for (i = 0; i < RESULT_WINDOW_SIZE_VALUE; i = i + 1)
                result_window_shadow[i] <= 0;
            for (i = 0; i < WORDS_PER_TILE; i = i + 1)
                weight_tile[i] <= 0;
        end else begin
            if (cmd_clear) begin
                irq_pending <= 1'b0;
                irq_out <= 1'b0;
                if ((state == `ST_DONE) || (state == `ST_ERROR)) begin
                    state <= `ST_IDLE;
                    done_flag <= 1'b0;
                    error_flag <= 1'b0;
                    error_info <= ERR_NONE;
                end
            end

            if (cmd_start && (state != `ST_IDLE)) begin
                error_flag <= 1'b1;
                error_info <= ERR_BUSY;
            end

            case (state)
                `ST_IDLE: begin
                    if (cmd_start) begin
                        done_flag <= 1'b0;
                        error_flag <= 1'b0;
                        error_info <= ERR_NONE;
                        irq_pending <= 1'b0;
                        irq_out <= 1'b0;
                        zero_counter <= 0;
                        cur_layer <= 0;
                        cur_output <= 0;
                        cur_batch <= 0;
                        tile_word <= 0;
                        input_word <= 0;
                        active_buffer <= 1'b0;
                        acc_reg <= 0;
                        for (i = 0; i < RESULT_WINDOW_SIZE_VALUE; i = i + 1)
                            result_window_shadow[i] <= 0;
                        if (valid_configuration(cfg_layer_count))
                            state <= `ST_INPUT_CMD;
                        else begin
                            state <= `ST_ERROR;
                            error_flag <= 1'b1;
                            error_info <= ERR_CONFIG;
                            irq_pending <= 1'b1;
                            irq_out <= 1'b1;
                        end
                    end
                end

                `ST_INPUT_CMD: begin
                    if (input_word >= input_word_count)
                        state <= `ST_LAYER_SETUP;
                    else if (dma_cmd_ready)
                        state <= `ST_INPUT_WAIT;
                end

                `ST_INPUT_WAIT: begin
                    if (dma_rsp_valid) begin
                        if (dma_rsp_err) begin
                            state <= `ST_ERROR;
                            error_flag <= 1'b1;
                            error_info <= ERR_DMA;
                            irq_pending <= 1'b1;
                            irq_out <= 1'b1;
                        end else begin
                            for (byte_lane = 0; byte_lane < ACTS_PER_WORD; byte_lane = byte_lane + 1) begin
                                if ((input_word * ACTS_PER_WORD_VALUE + byte_lane) < layer_inputs[0])
                                    act_buffer_a[(input_word * ACTS_PER_WORD_VALUE + byte_lane) % NUM_PES]
                                                 [(input_word * ACTS_PER_WORD_VALUE + byte_lane) / NUM_PES] <=
                                        dma_rsp_data[byte_lane*8 +: 8];
                            end
                            input_word <= input_word + 1'b1;
                            state <= `ST_INPUT_CMD;
                        end
                    end
                end

                `ST_LAYER_SETUP: begin
                    cur_output <= 0;
                    cur_batch <= 0;
                    tile_word <= 0;
                    tile_words <= tile_words_for_batch(active_inputs, 11'd0);
                    valid_lanes <= valid_lanes_for_batch(active_inputs, 11'd0);
                    weight_row_stride_bytes <= {19'd0, words_per_output, 2'b00};
                    weight_row_base_addr <= active_weight_addr;
                    weight_batch_base_addr <= active_weight_addr;
                    bias_value <= 0;
                    scale_value <= 32'sd1;
                    acc_reg <= 0;
                    for (i = 0; i < RESULT_WINDOW_SIZE_VALUE; i = i + 1)
                        result_window_shadow[i] <= 0;
                    state <= `ST_WEIGHT_CMD;
                end

                `ST_WEIGHT_CMD: begin
                    if (tile_word < tile_words) begin
                        if (dma_cmd_ready)
                            state <= `ST_WEIGHT_WAIT;
                    end else if (tile_word < TILE_WORD_COUNT) begin
                        weight_tile[tile_word[TILE_INDEX_WIDTH-1:0]] <= 0;
                        tile_word <= tile_word + 1'b1;
                    end else begin
                        state <= `ST_COMPUTE_LAUNCH;
                    end
                end

                `ST_WEIGHT_WAIT: begin
                    if (dma_rsp_valid) begin
                        if (dma_rsp_err) begin
                            state <= `ST_ERROR;
                            error_flag <= 1'b1;
                            error_info <= ERR_DMA;
                            irq_pending <= 1'b1;
                            irq_out <= 1'b1;
                        end else begin
                            weight_tile[tile_word[TILE_INDEX_WIDTH-1:0]] <= dma_rsp_data;
                            tile_word <= tile_word + 1'b1;
                            state <= `ST_WEIGHT_CMD;
                        end
                    end
                end

                `ST_COMPUTE_LAUNCH: begin
                    state <= `ST_COMPUTE_WAIT;
                end

                `ST_COMPUTE_WAIT: begin
                    if (tree_valid && zero_tree_valid) begin
                        if (invalid_active != 0) begin
                            state <= `ST_ERROR;
                            error_flag <= 1'b1;
                            error_info <= ERR_WEIGHT;
                            irq_pending <= 1'b1;
                            irq_out <= 1'b1;
                        end else begin
                            acc_reg <= acc_reg_next;
                            if (cur_output < RESULT_WINDOW_SIZE_VALUE)
                                result_window_shadow[cur_output[2:0]] <= acc_reg_next;
                            zero_counter <= zero_counter + batch_zero_sum;
                            if ((cur_batch + 1) < batch_count) begin
                                cur_batch <= cur_batch + 1'b1;
                                tile_word <= 0;
                                tile_words <= tile_words_for_batch(active_inputs,
                                                                    cur_batch + 1'b1);
                                valid_lanes <= valid_lanes_for_batch(active_inputs,
                                                                      cur_batch + 1'b1);
                                weight_batch_base_addr <=
                                    weight_batch_base_addr + TILE_BYTES;
                                state <= `ST_WEIGHT_CMD;
                            end else begin
                                state <= `ST_BIAS_CMD;
                            end
                        end
                    end
                end

                `ST_BIAS_CMD: begin
                    if (active_bias_addr == 0) begin
                        bias_value <= 0;
                        state <= `ST_SCALE_CMD;
                    end else if (dma_cmd_ready) begin
                        state <= `ST_BIAS_WAIT;
                    end
                end

                `ST_BIAS_WAIT: begin
                    if (dma_rsp_valid) begin
                        if (dma_rsp_err) begin
                            state <= `ST_ERROR;
                            error_flag <= 1'b1;
                            error_info <= ERR_DMA;
                            irq_pending <= 1'b1;
                            irq_out <= 1'b1;
                        end else begin
                            bias_value <= $signed(dma_rsp_data);
                            state <= `ST_SCALE_CMD;
                        end
                    end
                end

                `ST_SCALE_CMD: begin
                    if (active_scale_addr == 0) begin
                        scale_value <= 32'sd1;
                        state <= `ST_POSTPROCESS;
                    end else if (dma_cmd_ready) begin
                        state <= `ST_SCALE_WAIT;
                    end
                end

                `ST_SCALE_WAIT: begin
                    if (dma_rsp_valid) begin
                        if (dma_rsp_err) begin
                            state <= `ST_ERROR;
                            error_flag <= 1'b1;
                            error_info <= ERR_DMA;
                            irq_pending <= 1'b1;
                            irq_out <= 1'b1;
                        end else begin
                            scale_value <= $signed(dma_rsp_data);
                            state <= `ST_POSTPROCESS;
                        end
                    end
                end

                `ST_POSTPROCESS: begin
                    state <= `ST_POSTPROCESS_WAIT;
                end

                `ST_POSTPROCESS_WAIT: begin
                    if (postprocess_output_valid) begin
                    if (final_layer) begin
                        final_value <= post_value;
                        if (cur_output == 0)
                            cfg_result <= post_value;
                        state <= `ST_OUTPUT_CMD;
                    end else begin
                        if (!active_buffer)
                            act_buffer_b[current_output_bank][current_output_row] <= post_activation;
                        else
                            act_buffer_a[current_output_bank][current_output_row] <= post_activation;
                        if ((cur_output + 1) >= active_outputs) begin
                            active_buffer <= ~active_buffer;
                            cur_layer <= cur_layer + 1'b1;
                            state <= `ST_LAYER_SETUP;
                        end else begin
                            acc_reg <= 0;
                            cur_output <= cur_output + 1'b1;
                            cur_batch <= 0;
                            tile_word <= 0;
                            tile_words <= tile_words_for_batch(active_inputs, 11'd0);
                            valid_lanes <= valid_lanes_for_batch(active_inputs, 11'd0);
                            weight_row_base_addr <=
                                weight_row_base_addr + weight_row_stride_bytes;
                            weight_batch_base_addr <=
                                weight_row_base_addr + weight_row_stride_bytes;
                            state <= `ST_WEIGHT_CMD;
                        end
                    end
                    end
                end

                `ST_OUTPUT_CMD: begin
                    if (dma_cmd_ready)
                        state <= `ST_OUTPUT_WAIT;
                end

                `ST_OUTPUT_WAIT: begin
                    if (dma_rsp_valid) begin
                        if (dma_rsp_err) begin
                            state <= `ST_ERROR;
                            error_flag <= 1'b1;
                            error_info <= ERR_DMA;
                            irq_pending <= 1'b1;
                            irq_out <= 1'b1;
                        end else if ((cur_output + 1) >= active_outputs) begin
                            done_flag <= 1'b1;
                            irq_pending <= 1'b1;
                            irq_out <= 1'b1;
                            state <= `ST_DONE;
                        end else begin
                            acc_reg <= 0;
                            cur_output <= cur_output + 1'b1;
                            cur_batch <= 0;
                            tile_word <= 0;
                            tile_words <= tile_words_for_batch(active_inputs, 11'd0);
                            valid_lanes <= valid_lanes_for_batch(active_inputs, 11'd0);
                            weight_row_base_addr <=
                                weight_row_base_addr + weight_row_stride_bytes;
                            weight_batch_base_addr <=
                                weight_row_base_addr + weight_row_stride_bytes;
                            state <= `ST_WEIGHT_CMD;
                        end
                    end
                end

                `ST_DONE: begin
                    /* IRQ and DONE remain asserted until CONTROL.CLEAR_IRQ. */
                end

                `ST_ERROR: begin
                    /* Error is sticky until CONTROL.CLEAR_IRQ. */
                end

                default: begin
                    state <= `ST_ERROR;
                    error_flag <= 1'b1;
                    error_info <= ERR_CONFIG;
                    irq_pending <= 1'b1;
                    irq_out <= 1'b1;
                end
            endcase
        end
    end
endmodule
