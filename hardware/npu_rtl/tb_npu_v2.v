`timescale 1ns / 1ps
`include "npu_v2_pkg.v"

/* Acceptance test: 8 -> 5 -> 3, one START, delayed DMA acknowledgements. */
module tb_npu_v2 #(
    parameter integer PHYSICAL_PES = 64,
    parameter integer DUMP_VCD = 0
);
    reg clk;
    reg rst_n;
    reg [31:0] wb_s_adr_i, wb_s_dat_i;
    reg [3:0] wb_s_sel_i;
    reg wb_s_we_i, wb_s_cyc_i, wb_s_stb_i;
    wire [31:0] wb_s_dat_o;
    wire wb_s_ack_o, wb_s_err_o;
    wire [31:0] wb_m_adr_o, wb_m_dat_o;
    wire [3:0] wb_m_sel_o;
    wire wb_m_we_o, wb_m_cyc_o, wb_m_stb_o;
    wire [2:0] wb_m_cti_o;
    wire [1:0] wb_m_bte_o;
    reg [31:0] wb_m_dat_i;
    reg wb_m_ack_i, wb_m_err_i;
    wire irq_out;

    localparam [31:0] PROD_INPUT_ADDR = 32'h0000_1800;
    localparam [31:0] PROD_L0_W_ADDR = 32'h0000_2000;
    localparam [31:0] PROD_L1_W_ADDR = 32'h0003_3000;
    localparam [31:0] PROD_L2_W_ADDR = 32'h0005_3000;
    localparam [31:0] PROD_OUTPUT_ADDR = 32'h0005_b000;
    localparam integer PROD_INPUT_WORDS = 196;
    localparam integer PROD_L0_W_WORDS = 50176;
    localparam integer PROD_L1_W_WORDS = 32768;
    localparam integer PROD_L2_W_WORDS = 8192;
    localparam integer PROD_L2_WORDS_PER_OUTPUT = 32;
    localparam integer PROD_OUTPUT_WORDS = 256;
    localparam integer EXT_RAM_WORDS = (PROD_OUTPUT_ADDR / 4) + PROD_OUTPUT_WORDS;
    localparam integer PRODUCTION_TIMEOUT = 2000000;
    localparam integer WEIGHT_TRACE_MAX = 16;

    reg [31:0] ext_ram[0:EXT_RAM_WORDS-1];
    reg pending;
    reg [31:0] pending_addr, pending_data;
    reg pending_we;
    reg pending_err;
    reg dma_err_once;
     integer dma_err_responses;
     integer i;
     integer protocol_ack_count;
     integer protocol_err_count;
    integer errors;
    reg [31:0] readback;
    reg trace_weight_reads;
    reg [31:0] weight_trace[0:WEIGHT_TRACE_MAX-1];
    integer weight_trace_count;

    localparam [31:0] INPUT_ADDR  = 32'h0000_0100;
    localparam [31:0] L0_W_ADDR  = 32'h0000_0200;
    localparam [31:0] L1_W_ADDR  = 32'h0000_0400;
    localparam [31:0] L0_B_ADDR  = 32'h0000_0600;
    localparam [31:0] L1_B_ADDR  = 32'h0000_0620;
    localparam [31:0] OUTPUT_ADDR = 32'h0000_0800;
    localparam [31:0] BOUNDARY_INPUT_ADDR = 32'h0000_0a00;
    localparam [31:0] BOUNDARY_W_ADDR = 32'h0000_0b00;
    localparam [31:0] BOUNDARY_OUTPUT_ADDR = 32'h0000_0c00;
    localparam [31:0] WIDE_INPUT_ADDR = 32'h0000_0e00;
    localparam [31:0] WIDE_W_ADDR = 32'h0000_1000;
    localparam [31:0] WIDE_REPEAT_W_ADDR = 32'h0000_1200;
    localparam [31:0] WIDE_OUTPUT_ADDR = 32'h0000_1400;
    localparam [31:0] ERROR_OUTPUT_ADDR = 32'h0000_1600;

    function [31:0] pack8;
        input [1:0] w0, w1, w2, w3, w4, w5, w6, w7;
        begin
            pack8 = w0 | (w1 << 2) | (w2 << 4) | (w3 << 6) |
                    (w4 << 8) | (w5 << 10) | (w6 << 12) | (w7 << 14);
        end
    endfunction

    function is_trace_weight_address;
        input [31:0] address;
        begin
            is_trace_weight_address =
                ((address >= L0_W_ADDR) && (address < L0_W_ADDR + 32'd20)) ||
                ((address >= L1_W_ADDR) && (address < L1_W_ADDR + 32'd12)) ||
                ((address >= BOUNDARY_W_ADDR) && (address < BOUNDARY_W_ADDR + 32'd8)) ||
                ((address >= WIDE_W_ADDR) && (address < WIDE_W_ADDR + 32'd20)) ||
                ((address >= WIDE_REPEAT_W_ADDR) &&
                 (address < WIDE_REPEAT_W_ADDR + 32'd20));
        end
    endfunction

    task check_weight_trace_8;
        begin
            if (weight_trace_count !== 8) begin
                $display("FAIL 8->5->3 weight trace count=%0d expected 8",
                         weight_trace_count);
                errors = errors + 1;
            end
            if (weight_trace[0] !== L0_W_ADDR ||
                weight_trace[1] !== L0_W_ADDR + 32'd4 ||
                weight_trace[2] !== L0_W_ADDR + 32'd8 ||
                weight_trace[3] !== L0_W_ADDR + 32'd12 ||
                weight_trace[4] !== L0_W_ADDR + 32'd16 ||
                weight_trace[5] !== L1_W_ADDR ||
                weight_trace[6] !== L1_W_ADDR + 32'd4 ||
                weight_trace[7] !== L1_W_ADDR + 32'd8) begin
                $display("FAIL 8->5->3 weight trace sequence");
                errors = errors + 1;
            end
        end
    endtask

    task check_weight_trace_2;
        input [31:0] base_address;
        begin
            if (weight_trace_count !== 2) begin
                $display("FAIL 17-input weight trace count=%0d expected 2",
                         weight_trace_count);
                errors = errors + 1;
            end
            if (weight_trace[0] !== base_address ||
                weight_trace[1] !== base_address + 32'd4) begin
                $display("FAIL 17-input weight trace sequence");
                errors = errors + 1;
            end
        end
    endtask

    task check_weight_trace_5;
        input [31:0] base_address;
        begin
            if (weight_trace_count !== 5) begin
                $display("FAIL 65-input weight trace count=%0d expected 5",
                         weight_trace_count);
                errors = errors + 1;
            end
            if (weight_trace[0] !== base_address ||
                weight_trace[1] !== base_address + 32'd4 ||
                weight_trace[2] !== base_address + 32'd8 ||
                weight_trace[3] !== base_address + 32'd12 ||
                weight_trace[4] !== base_address + 32'd16) begin
                $display("FAIL 65-input weight trace sequence");
                errors = errors + 1;
            end
        end
    endtask

    npu_ternaria_top_v2 #(
        .NUM_PES(PHYSICAL_PES)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .wb_s_adr_i(wb_s_adr_i), .wb_s_dat_i(wb_s_dat_i),
        .wb_s_sel_i(wb_s_sel_i), .wb_s_we_i(wb_s_we_i),
        .wb_s_cyc_i(wb_s_cyc_i), .wb_s_stb_i(wb_s_stb_i),
        .wb_s_dat_o(wb_s_dat_o), .wb_s_ack_o(wb_s_ack_o),
        .wb_s_err_o(wb_s_err_o),
        .wb_m_adr_o(wb_m_adr_o), .wb_m_dat_o(wb_m_dat_o),
        .wb_m_sel_o(wb_m_sel_o), .wb_m_we_o(wb_m_we_o),
        .wb_m_cyc_o(wb_m_cyc_o), .wb_m_stb_o(wb_m_stb_o),
        .wb_m_cti_o(wb_m_cti_o), .wb_m_bte_o(wb_m_bte_o),
        .wb_m_dat_i(wb_m_dat_i), .wb_m_ack_i(wb_m_ack_i),
        .wb_m_err_i(wb_m_err_i), .irq_out(irq_out)
    );

    always #5 clk = ~clk;

    /* One-cycle request capture plus one delayed response cycle. */
    always @* begin
        wb_m_dat_i = 32'd0;
        if (!pending_we)
            wb_m_dat_i = ext_ram[pending_addr / 4];
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            pending <= 1'b0;
            pending_addr <= 0;
            pending_data <= 0;
            pending_we <= 1'b0;
            pending_err <= 1'b0;
            wb_m_ack_i <= 1'b0;
            wb_m_err_i <= 1'b0;
        end else begin
            wb_m_ack_i <= 1'b0;
            wb_m_err_i <= 1'b0;
            if (pending) begin
                if (pending_err) begin
                    wb_m_err_i <= 1'b1;
                    dma_err_responses <= dma_err_responses + 1;
                end else begin
                    if (pending_we)
                    ext_ram[pending_addr / 4] <= pending_data;
                    wb_m_ack_i <= 1'b1;
                end
                pending <= 1'b0;
            end else if (wb_m_cyc_o && wb_m_stb_o && !wb_m_ack_i) begin
                if (trace_weight_reads && !wb_m_we_o &&
                    is_trace_weight_address(wb_m_adr_o) &&
                    (weight_trace_count < WEIGHT_TRACE_MAX)) begin
                    weight_trace[weight_trace_count] <= wb_m_adr_o;
                    weight_trace_count <= weight_trace_count + 1;
                end
                pending <= 1'b1;
                pending_addr <= wb_m_adr_o;
                pending_data <= wb_m_dat_o;
                pending_we <= wb_m_we_o;
                pending_err <= dma_err_once;
                dma_err_once <= 1'b0;
            end
        end
    end

    task wb_write;
        input [31:0] address;
        input [31:0] data;
        integer t;
        begin
            @(negedge clk);
            wb_s_adr_i = address;
            wb_s_dat_i = data;
            wb_s_sel_i = 4'b1111;
            wb_s_we_i = 1'b1;
            wb_s_cyc_i = 1'b1;
            wb_s_stb_i = 1'b1;
            for (t = 0; t < 64 && !wb_s_ack_o && !wb_s_err_o; t = t + 1)
                @(posedge clk);
            if (wb_s_err_o || t == 64) begin
                $display("FAIL MMIO write 0x%08x", address);
                errors = errors + 1;
            end
            @(negedge clk);
            wb_s_cyc_i = 1'b0;
            wb_s_stb_i = 1'b0;
            wb_s_we_i = 1'b0;
            wb_s_sel_i = 0;
        end
    endtask

    task wb_read;
        input [31:0] address;
        output [31:0] data;
        integer t;
        begin
            @(negedge clk);
            wb_s_adr_i = address;
            wb_s_dat_i = 0;
            wb_s_sel_i = 4'b1111;
            wb_s_we_i = 1'b0;
            wb_s_cyc_i = 1'b1;
            wb_s_stb_i = 1'b1;
            data = 0;
            for (t = 0; t < 64 && !wb_s_ack_o && !wb_s_err_o; t = t + 1)
                @(posedge clk);
            if (wb_s_err_o || t == 64) begin
                $display("FAIL MMIO read 0x%08x", address);
                errors = errors + 1;
            end else
                data = wb_s_dat_o;
            @(negedge clk);
            wb_s_cyc_i = 1'b0;
            wb_s_stb_i = 1'b0;
            wb_s_sel_i = 0;
        end
    endtask

    task wb_expect_err;
        input [31:0] address;
        integer t;
        begin
            @(negedge clk);
            wb_s_adr_i = address;
            wb_s_dat_i = 0;
            wb_s_sel_i = 4'b1111;
            wb_s_we_i = 1'b0;
            wb_s_cyc_i = 1'b1;
            wb_s_stb_i = 1'b1;
            for (t = 0; t < 64 && !wb_s_ack_o && !wb_s_err_o; t = t + 1)
                @(posedge clk);
            if (wb_s_ack_o || !wb_s_err_o || t == 64) begin
                $display("FAIL MMIO offset 0x%08x did not return expected ERR", address);
                errors = errors + 1;
            end
            @(negedge clk);
            wb_s_cyc_i = 1'b0;
            wb_s_stb_i = 1'b0;
            wb_s_we_i = 1'b0;
            wb_s_sel_i = 0;
        end
    endtask

     task set_layer;
         input [31:0] index;
         input [31:0] inputs;
         input [31:0] outputs;
         input [31:0] weight_addr;
         input [31:0] bias_addr;
         input [31:0] quant;
         begin
             wb_write(`REG_LAYER_INDEX, index);
             wb_write(`REG_LAYER_INPUTS, inputs);
             wb_write(`REG_LAYER_OUTPUTS, outputs);
             wb_write(`REG_WEIGHT_ADDR, weight_addr);
             wb_write(`REG_BIAS_ADDR, bias_addr);
             wb_write(`REG_SCALE_ADDR, 0);
             wb_write(`REG_LAYER_QUANT, quant);
         end
     endtask

     task protocol_expect_held_response;
         input [31:0] address;
         input [31:0] write_data;
         input write_enable;
         input expect_error;
         input integer hold_cycles;
         input [8*64-1:0] name;
         integer t;
         begin
             @(negedge clk);
             wb_s_adr_i = address;
             wb_s_dat_i = write_data;
             wb_s_sel_i = 4'b1111;
             wb_s_we_i = write_enable;
             wb_s_cyc_i = 1'b1;
             wb_s_stb_i = 1'b1;
             protocol_ack_count = 0;
             protocol_err_count = 0;
             for (t = 0; t < hold_cycles; t = t + 1) begin
                 @(posedge clk);
                 if (wb_s_ack_o) protocol_ack_count = protocol_ack_count + 1;
                 if (wb_s_err_o) protocol_err_count = protocol_err_count + 1;
             end
             if (expect_error) begin
                 if (protocol_ack_count !== 0 || protocol_err_count !== 1)
                     $display("FAIL MMIO held %0s ack=%0d err=%0d expected ack=0 err=1",
                              name, protocol_ack_count, protocol_err_count);
             end else if (protocol_ack_count !== 1 || protocol_err_count !== 0) begin
                 $display("FAIL MMIO held %0s ack=%0d err=%0d expected ack=1 err=0",
                          name, protocol_ack_count, protocol_err_count);
             end
             if ((expect_error && (protocol_ack_count !== 0 || protocol_err_count !== 1)) ||
                 (!expect_error && (protocol_ack_count !== 1 || protocol_err_count !== 0)))
                 errors = errors + 1;
             @(negedge clk);
             wb_s_cyc_i = 1'b0;
             wb_s_stb_i = 1'b0;
             wb_s_we_i = 1'b0;
             wb_s_sel_i = 0;
             @(posedge clk);
         end
     endtask

     task protocol_expect_reset_clears_response;
         begin
             @(negedge clk);
             wb_s_adr_i = `REG_STATUS;
             wb_s_dat_i = 0;
             wb_s_sel_i = 4'b1111;
             wb_s_we_i = 1'b0;
             wb_s_cyc_i = 1'b1;
             wb_s_stb_i = 1'b1;
             @(posedge clk);
             rst_n = 1'b0;
             @(posedge clk);
             if (wb_s_ack_o || wb_s_err_o) begin
                 $display("FAIL MMIO reset during held request left stale response");
                 errors = errors + 1;
             end
             @(negedge clk);
             wb_s_cyc_i = 1'b0;
             wb_s_stb_i = 1'b0;
             wb_s_sel_i = 0;
             rst_n = 1'b1;
             @(posedge clk);
             if (wb_s_ack_o || wb_s_err_o) begin
                 $display("FAIL MMIO reset released with stale response");
                 errors = errors + 1;
             end
         end
     endtask

     task protocol_expect_back_to_back;
         integer t;
         begin
             @(negedge clk);
             wb_s_adr_i = `REG_STATUS;
             wb_s_dat_i = 0;
             wb_s_sel_i = 4'b1111;
             wb_s_we_i = 1'b0;
             wb_s_cyc_i = 1'b1;
             wb_s_stb_i = 1'b1;
             for (t = 0; t < 8 && !wb_s_ack_o && !wb_s_err_o; t = t + 1)
                 @(posedge clk);
             if (!wb_s_ack_o || wb_s_err_o || t == 8) begin
                 $display("FAIL first back-to-back request did not ACK");
                 errors = errors + 1;
             end
             @(negedge clk);
             wb_s_cyc_i = 1'b0;
             wb_s_stb_i = 1'b0;
             @(negedge clk);
             wb_s_adr_i = `REG_CAPABILITIES;
             wb_s_cyc_i = 1'b1;
             wb_s_stb_i = 1'b1;
             for (t = 0; t < 8 && !wb_s_ack_o && !wb_s_err_o; t = t + 1)
                 @(posedge clk);
             if (!wb_s_ack_o || wb_s_err_o || t == 8) begin
                 $display("FAIL second back-to-back request did not ACK");
                 errors = errors + 1;
             end
             @(negedge clk);
             wb_s_cyc_i = 1'b0;
             wb_s_stb_i = 1'b0;
             wb_s_sel_i = 0;
         end
     endtask

     initial begin
        clk = 0;
        rst_n = 0;
        wb_s_adr_i = 0;
        wb_s_dat_i = 0;
        wb_s_sel_i = 0;
        wb_s_we_i = 0;
        wb_s_cyc_i = 0;
        wb_s_stb_i = 0;
        pending = 0;
        dma_err_once = 0;
        dma_err_responses = 0;
        errors = 0;
        trace_weight_reads = 1'b1;
        weight_trace_count = 0;
        for (i = 0; i < 4096; i = i + 1) ext_ram[i] = 0;

        for (i = 4096; i < EXT_RAM_WORDS; i = i + 1) ext_ram[i] = 0;

        /* Input vector 1..8, packed as four little-endian bytes. */
        ext_ram[INPUT_ADDR/4] = 32'h0403_0201;
        ext_ram[INPUT_ADDR/4+1] = 32'h0807_0605;

        /* Layer 0: five output-major rows, eight useful weights each. */
        ext_ram[L0_W_ADDR/4+0] = pack8(2'b01,2'b01,2'b01,2'b01,2'b01,2'b01,2'b01,2'b01);
        ext_ram[L0_W_ADDR/4+1] = pack8(2'b11,2'b11,2'b11,2'b11,2'b11,2'b11,2'b11,2'b11);
        ext_ram[L0_W_ADDR/4+2] = pack8(2'b01,2'b11,2'b01,2'b11,2'b01,2'b11,2'b01,2'b11);
        ext_ram[L0_W_ADDR/4+3] = pack8(2'b01,2'b00,2'b01,2'b00,2'b01,2'b00,2'b01,2'b00);
        ext_ram[L0_W_ADDR/4+4] = 0;

        /* Layer 1 rows: [+, +, +, +, +], [+, -, +, 0, 0], [-, -, -, -, -]. */
        ext_ram[L1_W_ADDR/4+0] = pack8(2'b01,2'b01,2'b01,2'b01,2'b01,0,0,0);
        ext_ram[L1_W_ADDR/4+1] = pack8(2'b01,2'b11,2'b01,2'b00,2'b00,0,0,0);
        ext_ram[L1_W_ADDR/4+2] = pack8(2'b11,2'b11,2'b11,2'b11,2'b11,0,0,0);

        /* Layer 0 biases: +1, +100, 0, -20, +7. Layer 1: -10, +2, 0. */
        ext_ram[L0_B_ADDR/4+0] = 1;
        ext_ram[L0_B_ADDR/4+1] = 100;
        ext_ram[L0_B_ADDR/4+2] = 0;
        ext_ram[L0_B_ADDR/4+3] = -20;
        ext_ram[L0_B_ADDR/4+4] = 7;
        ext_ram[L1_B_ADDR/4+0] = -10;
        ext_ram[L1_B_ADDR/4+1] = 2;
        ext_ram[L1_B_ADDR/4+2] = 0;

        /* Boundary layer: 17 inputs crosses the 16-weight word/tile boundary. */
        ext_ram[BOUNDARY_INPUT_ADDR/4+0] = 32'h0101_0101;
        ext_ram[BOUNDARY_INPUT_ADDR/4+1] = 32'h0101_0101;
        ext_ram[BOUNDARY_INPUT_ADDR/4+2] = 32'h0101_0101;
        ext_ram[BOUNDARY_INPUT_ADDR/4+3] = 32'h0101_0101;
        ext_ram[BOUNDARY_INPUT_ADDR/4+4] = 32'h0000_0001;
        ext_ram[BOUNDARY_W_ADDR/4+0] = 32'h5555_5555;
        ext_ram[BOUNDARY_W_ADDR/4+1] = 32'h0000_0000;

        /* 65 all-one inputs exercise one partial tile at every PE width. */
        for (i = 0; i < 17; i = i + 1)
            ext_ram[WIDE_INPUT_ADDR/4+i] = (i == 16) ? 32'h0000_0001 : 32'h0101_0101;
        ext_ram[WIDE_W_ADDR/4+0] = 32'h5555_5555;
        ext_ram[WIDE_W_ADDR/4+1] = 32'h5555_5555;
        ext_ram[WIDE_W_ADDR/4+2] = 32'h5555_5555;
        ext_ram[WIDE_W_ADDR/4+3] = 32'h5555_5555;
        ext_ram[WIDE_W_ADDR/4+4] = 32'h0000_0001;
        ext_ram[WIDE_REPEAT_W_ADDR/4+0] = 32'h5555_5557;
        ext_ram[WIDE_REPEAT_W_ADDR/4+1] = 32'h5555_5555;
        ext_ram[WIDE_REPEAT_W_ADDR/4+2] = 32'h5555_5555;
        ext_ram[WIDE_REPEAT_W_ADDR/4+3] = 32'h5555_5555;
        ext_ram[WIDE_REPEAT_W_ADDR/4+4] = 32'h0000_0001;
        ext_ram[WIDE_OUTPUT_ADDR/4] = 32'hA5A5_A5A5;
        ext_ram[ERROR_OUTPUT_ADDR/4] = 32'h5A5A_5A5A;

        for (i = 0; i < PROD_INPUT_WORDS; i = i + 1)
            ext_ram[PROD_INPUT_ADDR/4+i] = 32'h0101_0101;
        for (i = 0; i < PROD_L0_W_WORDS; i = i + 1)
            ext_ram[PROD_L0_W_ADDR/4+i] = 32'h5555_5555;
        for (i = 0; i < PROD_L1_W_WORDS; i = i + 1)
            ext_ram[PROD_L1_W_ADDR/4+i] = 32'h5555_5555;
        for (i = 0; i < PROD_L2_W_WORDS; i = i + 1)
            ext_ram[PROD_L2_W_ADDR/4+i] = 32'h5555_5555;
        for (i = 0; i < PROD_L2_WORDS_PER_OUTPUT; i = i + 1)
            ext_ram[PROD_L2_W_ADDR/4 +
                    (PROD_OUTPUT_WORDS - 1) * PROD_L2_WORDS_PER_OUTPUT + i] =
                32'hffff_ffff;
        for (i = 0; i < PROD_OUTPUT_WORDS; i = i + 1)
            ext_ram[PROD_OUTPUT_ADDR/4+i] = 32'hA5A5_A5A5;

        if (DUMP_VCD) begin
            $dumpfile("tb_npu_v2.vcd");
            $dumpvars(0, tb_npu_v2);
        end
         #30 rst_n = 1'b1;

         /* Registered MMIO boundary regressions: keep STB asserted past response. */
         protocol_expect_held_response(`REG_STATUS, 0, 1'b0, 1'b0, 8, "read");
         protocol_expect_held_response(`REG_LAYER_INPUTS, 32'd17, 1'b1, 1'b0, 8, "write");
         wb_read(`REG_LAYER_INPUTS, readback);
         if (readback !== 32'd17) begin
             $display("FAIL MMIO held write value=0x%08x expected 17", readback);
             errors = errors + 1;
         end
         protocol_expect_held_response(`REG_CONTROL, 32'd1, 1'b1, 1'b0, 8, "START");
         protocol_expect_held_response(32'h0000_0100, 0, 1'b0, 1'b1, 8, "invalid");
         protocol_expect_back_to_back;
         protocol_expect_reset_clears_response;

         wb_expect_err(32'h0000_0100);
        wb_write(`REG_INPUT_ADDR, INPUT_ADDR);
        wb_write(`REG_OUTPUT_ADDR, OUTPUT_ADDR);
        wb_write(`REG_LAYER_COUNT, 2);
        wb_write(`REG_MAC_CFG, PHYSICAL_PES);
        set_layer(0, 8, 5, L0_W_ADDR, L0_B_ADDR, 32'h0000_0100);
        set_layer(1, 5, 3, L1_W_ADDR, L1_B_ADDR, 32'h0000_0000);

        wb_write(`REG_CONTROL, 1);
        for (i = 0; i < 200000 && !irq_out; i = i + 1) @(posedge clk);
        if (!irq_out) begin
            $display("FAIL timeout waiting for IRQ");
            errors = errors + 1;
        end

        wb_read(`REG_STATUS, readback);
        if (readback[0] || !readback[1] || !readback[2]) begin
            $display("FAIL status=0x%08x", readback);
            errors = errors + 1;
        end
        if (readback[3]) begin
            $display("FAIL status unexpectedly reports error: 0x%08x", readback);
            errors = errors + 1;
        end
        if (readback[15:8] !== 8'd1) begin
            $display("FAIL 2-layer STATUS current layer=%0d expected 1", readback[15:8]);
            errors = errors + 1;
        end
        if (readback[23:16] !== 8'd14) begin
            $display("FAIL 8->5->3 STATUS zero count=%0d expected 14",
                     readback[23:16]);
            errors = errors + 1;
        end
        trace_weight_reads = 1'b0;
        check_weight_trace_8;

        if (ext_ram[OUTPUT_ADDR/4] !== 98) begin
            $display("FAIL output[0]=%0d expected 98", $signed(ext_ram[OUTPUT_ADDR/4]));
            errors = errors + 1;
        end
        if (ext_ram[OUTPUT_ADDR/4+1] !== -25) begin
            $display("FAIL output[1]=%0d expected -25", $signed(ext_ram[OUTPUT_ADDR/4+1]));
            errors = errors + 1;
        end
        if (ext_ram[OUTPUT_ADDR/4+2] !== -108) begin
            $display("FAIL output[2]=%0d expected -108", $signed(ext_ram[OUTPUT_ADDR/4+2]));
            errors = errors + 1;
        end
        wb_read(`REG_RESULT, readback);
        if (readback !== 32'd98) begin
            $display("FAIL REG_RESULT=%0d expected 98", $signed(readback));
            errors = errors + 1;
        end
        wb_write(`REG_LAYER_INDEX, 0);
        wb_read(`REG_RESULT_WINDOW, readback);
        if (readback !== 32'd108) begin
            $display("FAIL RESULT_WINDOW[descriptor 0]=%0d expected 108",
                     $signed(readback));
            errors = errors + 1;
        end
        wb_write(`REG_LAYER_INDEX, 1);
        wb_read(`REG_RESULT_WINDOW, readback);
        if (readback !== -32'sd27) begin
            $display("FAIL RESULT_WINDOW[descriptor 1]=%0d expected -27",
                     $signed(readback));
            errors = errors + 1;
        end

        wb_write(`REG_CONTROL, 2);
        if (irq_out) begin
            $display("FAIL IRQ did not clear");
            errors = errors + 1;
        end

        /* Keep the original acceptance test, then exercise a second tile. */
        weight_trace_count = 0;
        trace_weight_reads = 1'b1;
        wb_write(`REG_INPUT_ADDR, BOUNDARY_INPUT_ADDR);
        wb_write(`REG_OUTPUT_ADDR, BOUNDARY_OUTPUT_ADDR);
        wb_write(`REG_LAYER_COUNT, 1);
        wb_write(`REG_MAC_CFG, PHYSICAL_PES);
        set_layer(0, 17, 1, BOUNDARY_W_ADDR, 0, 0);
        wb_write(`REG_CONTROL, 1);
        for (i = 0; i < 200000 && !irq_out; i = i + 1) @(posedge clk);
        if (!irq_out) begin
            $display("FAIL boundary timeout waiting for IRQ");
            errors = errors + 1;
        end
        wb_read(`REG_STATUS, readback);
        if (readback[0] || !readback[1] || !readback[2] || readback[3]) begin
            $display("FAIL boundary status=0x%08x", readback);
            errors = errors + 1;
        end
        if (readback[23:16] !== 8'd1) begin
            $display("FAIL 17-input STATUS zero count=%0d expected 1",
                     readback[23:16]);
            errors = errors + 1;
        end
        if (ext_ram[BOUNDARY_OUTPUT_ADDR/4] !== 32'd16) begin
            $display("FAIL boundary output=%0d expected 16",
                     $signed(ext_ram[BOUNDARY_OUTPUT_ADDR/4]));
            errors = errors + 1;
        end
        trace_weight_reads = 1'b0;
        check_weight_trace_2(BOUNDARY_W_ADDR);
        wb_write(`REG_CONTROL, 2);
        if (irq_out) begin
            $display("FAIL boundary IRQ did not clear");
            errors = errors + 1;
        end

        /* A 65-input all-one row must accumulate across the PE boundary. */
        weight_trace_count = 0;
        trace_weight_reads = 1'b1;
        wb_write(`REG_INPUT_ADDR, WIDE_INPUT_ADDR);
        wb_write(`REG_OUTPUT_ADDR, WIDE_OUTPUT_ADDR);
        wb_write(`REG_LAYER_COUNT, 1);
        wb_write(`REG_MAC_CFG, PHYSICAL_PES);
        set_layer(0, 65, 1, WIDE_W_ADDR, 0, 0);
        wb_write(`REG_CONTROL, 1);
        for (i = 0; i < 200000 && !irq_out; i = i + 1) @(posedge clk);
        if (!irq_out) begin
            $display("FAIL 65-input timeout waiting for IRQ");
            errors = errors + 1;
        end
        wb_read(`REG_STATUS, readback);
        if (readback[0] || !readback[1] || !readback[2] || readback[3]) begin
            $display("FAIL 65-input status=0x%08x", readback);
            errors = errors + 1;
        end
        if (readback[23:16] !== 8'd0) begin
            $display("FAIL 65-input STATUS zero count=%0d expected 0",
                     readback[23:16]);
            errors = errors + 1;
        end
        trace_weight_reads = 1'b0;
        check_weight_trace_5(WIDE_W_ADDR);
        if (ext_ram[WIDE_OUTPUT_ADDR/4] !== 32'd65) begin
            $display("FAIL 65-input output=%0d expected 65",
                     $signed(ext_ram[WIDE_OUTPUT_ADDR/4]));
            errors = errors + 1;
        end
        wb_read(`REG_RESULT, readback);
        if (readback !== 32'd65) begin
            $display("FAIL 65-input REG_RESULT=%0d expected 65", $signed(readback));
            errors = errors + 1;
        end
        wb_read(`REG_RESULT_WINDOW, readback);
        if (readback !== 32'd65) begin
            $display("FAIL 65-input RESULT_WINDOW=%0d expected 65", $signed(readback));
            errors = errors + 1;
        end
        wb_write(`REG_CONTROL, 2);
        if (irq_out) begin
            $display("FAIL 65-input IRQ did not clear");
            errors = errors + 1;
        end

        /* Repeat without reset, with one literal weight changed: 65 -> 63. */
        weight_trace_count = 0;
        trace_weight_reads = 1'b1;
        wb_write(`REG_OUTPUT_ADDR, WIDE_OUTPUT_ADDR + 4);
        ext_ram[WIDE_OUTPUT_ADDR/4+1] = 32'hA5A5_A5A5;
        wb_write(`REG_LAYER_COUNT, 1);
        wb_write(`REG_MAC_CFG, PHYSICAL_PES);
        set_layer(0, 65, 1, WIDE_REPEAT_W_ADDR, 0, 0);
        wb_write(`REG_CONTROL, 1);
        for (i = 0; i < 200000 && !irq_out; i = i + 1) @(posedge clk);
        if (!irq_out) begin
            $display("FAIL repeated inference timeout waiting for IRQ");
            errors = errors + 1;
        end
        wb_read(`REG_STATUS, readback);
        if (readback[0] || !readback[1] || !readback[2] || readback[3]) begin
            $display("FAIL repeated inference status=0x%08x", readback);
            errors = errors + 1;
        end
        if (readback[23:16] !== 8'd0) begin
            $display("FAIL repeated inference STATUS zero count=%0d expected 0",
                     readback[23:16]);
            errors = errors + 1;
        end
        trace_weight_reads = 1'b0;
        check_weight_trace_5(WIDE_REPEAT_W_ADDR);
        if (ext_ram[WIDE_OUTPUT_ADDR/4+1] !== 32'd63) begin
            $display("FAIL repeated inference output=%0d expected 63",
                     $signed(ext_ram[WIDE_OUTPUT_ADDR/4+1]));
            errors = errors + 1;
        end
        wb_read(`REG_RESULT, readback);
        if (readback !== 32'd63) begin
            $display("FAIL repeated inference REG_RESULT=%0d expected 63",
                     $signed(readback));
            errors = errors + 1;
        end
        wb_read(`REG_RESULT_WINDOW, readback);
        if (readback !== 32'd63) begin
            $display("FAIL repeated inference RESULT_WINDOW=%0d expected 63",
                     $signed(readback));
            errors = errors + 1;
        end
        wb_write(`REG_CONTROL, 2);
        if (irq_out) begin
            $display("FAIL repeated inference IRQ did not clear");
            errors = errors + 1;
        end

        /* One DMA ERR response must be sticky until CLEAR_IRQ. */
        dma_err_once = 1'b1;
        wb_write(`REG_INPUT_ADDR, WIDE_INPUT_ADDR);
        wb_write(`REG_OUTPUT_ADDR, ERROR_OUTPUT_ADDR);
        wb_write(`REG_LAYER_COUNT, 1);
        wb_write(`REG_MAC_CFG, PHYSICAL_PES);
        set_layer(0, 65, 1, WIDE_W_ADDR, 0, 0);
        wb_write(`REG_CONTROL, 1);
        for (i = 0; i < 200000 && !irq_out; i = i + 1) @(posedge clk);
        if (!irq_out) begin
            $display("FAIL DMA error timeout waiting for IRQ");
            errors = errors + 1;
        end
        if (dma_err_responses !== 1) begin
            $display("FAIL DMA error response count=%0d expected 1", dma_err_responses);
            errors = errors + 1;
        end
        wb_read(`REG_STATUS, readback);
        if (readback[0] || !readback[1] || readback[2] || !readback[3]) begin
            $display("FAIL DMA error status=0x%08x", readback);
            errors = errors + 1;
        end
        wb_read(`REG_ERROR_INFO, readback);
        if (readback !== 32'h0000_0003) begin
            $display("FAIL ERROR_INFO=0x%08x expected ERR_DMA", readback);
            errors = errors + 1;
        end
        repeat (4) @(posedge clk);
        if (!irq_out) begin
            $display("FAIL DMA error IRQ was not sticky");
            errors = errors + 1;
        end
        wb_read(`REG_ERROR_INFO, readback);
        if (readback !== 32'h0000_0003) begin
            $display("FAIL sticky ERROR_INFO=0x%08x expected ERR_DMA", readback);
            errors = errors + 1;
        end
        wb_write(`REG_CONTROL, 2);
        if (irq_out) begin
            $display("FAIL DMA error IRQ did not clear");
            errors = errors + 1;
        end
        wb_read(`REG_STATUS, readback);
        if (readback[3:0] !== 4'b0000 || readback[28:24] !== 5'd0) begin
            $display("FAIL DMA error CLEAR did not return idle: status=0x%08x", readback);
            errors = errors + 1;
        end
        wb_read(`REG_ERROR_INFO, readback);
        if (readback !== 32'd0) begin
            $display("FAIL ERROR_INFO after CLEAR=0x%08x", readback);
            errors = errors + 1;
        end

        /* Production-sized 784 -> 1024 -> 512 -> 256 descriptor chain. */
        wb_write(`REG_INPUT_ADDR, PROD_INPUT_ADDR);
        wb_write(`REG_OUTPUT_ADDR, PROD_OUTPUT_ADDR);
        wb_write(`REG_LAYER_COUNT, 3);
        wb_write(`REG_MAC_CFG, PHYSICAL_PES);
        set_layer(0, 784, 1024, PROD_L0_W_ADDR, 0, 32'h0000_0100);
        set_layer(1, 1024, 512, PROD_L1_W_ADDR, 0, 32'h0000_0100);
        set_layer(2, 512, 256, PROD_L2_W_ADDR, 0, 32'h0000_0000);
        wb_write(`REG_CONTROL, 1);
        for (i = 0; i < PRODUCTION_TIMEOUT && !irq_out; i = i + 1)
            @(posedge clk);
        if (!irq_out) begin
            $display("FAIL production chain timeout waiting for IRQ");
            errors = errors + 1;
        end

        wb_read(`REG_STATUS, readback);
        if (readback[0] || !readback[1] || !readback[2] || readback[3]) begin
            $display("FAIL production chain status=0x%08x", readback);
            errors = errors + 1;
        end
        if (readback[15:8] !== 8'd2) begin
            $display("FAIL 3-layer STATUS current layer=%0d expected 2", readback[15:8]);
            errors = errors + 1;
        end
        wb_read(`REG_RESULT, readback);
        if (readback !== 32'd65024) begin
            $display("FAIL production chain REG_RESULT=%0d expected 65024",
                     $signed(readback));
            errors = errors + 1;
        end
        if (ext_ram[PROD_OUTPUT_ADDR/4] !== 32'd65024 ||
            ext_ram[PROD_OUTPUT_ADDR/4+127] !== 32'd65024 ||
            ext_ram[PROD_OUTPUT_ADDR/4+254] !== 32'd65024 ||
            ext_ram[PROD_OUTPUT_ADDR/4+255] !== -32'sd65024) begin
            $display("FAIL production chain representative outputs");
            errors = errors + 1;
        end
        for (i = 0; i < PROD_OUTPUT_WORDS - 1; i = i + 1) begin
            if (ext_ram[PROD_OUTPUT_ADDR/4+i] !== 32'd65024) begin
                $display("FAIL production output[%0d]=%0d expected 65024",
                         i, $signed(ext_ram[PROD_OUTPUT_ADDR/4+i]));
                errors = errors + 1;
            end
        end
        if (ext_ram[PROD_OUTPUT_ADDR/4+PROD_OUTPUT_WORDS-1] !== -32'sd65024) begin
            $display("FAIL production output[255]=%0d expected -65024",
                     $signed(ext_ram[PROD_OUTPUT_ADDR/4+PROD_OUTPUT_WORDS-1]));
            errors = errors + 1;
        end
        wb_write(`REG_CONTROL, 2);
        if (irq_out) begin
            $display("FAIL production chain IRQ did not clear");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: autonomous production 784->1024->512->256 chain, 8->5->3, 17/65-input tiles, repeat, and DMA error at %0d PEs",
                     PHYSICAL_PES);
        else
            $display("FAIL: %0d error(s)", errors);
        if (errors != 0) $fatal(1);
        $finish;
    end
endmodule
