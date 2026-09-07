`timescale 1ns / 1ps

/* Red-first contract for the single-beat Wishbone DMA master. */
module tb_wishbone_master;
    localparam integer TIMEOUT_OBSERVATION_CYCLES = 300;

    reg clk;
    reg rst_n;
    reg cmd_valid;
    wire cmd_ready;
    reg [31:0] cmd_addr;
    reg [31:0] cmd_wdata;
    reg cmd_we;
    reg [3:0] cmd_sel;
    wire rsp_valid;
    wire [31:0] rsp_rdata;
    wire rsp_err;
    wire busy;
    wire [31:0] wb_adr_o;
    wire [31:0] wb_dat_o;
    wire [3:0] wb_sel_o;
    wire wb_we_o;
    wire wb_cyc_o;
    wire wb_stb_o;
    wire [2:0] wb_cti_o;
    wire [1:0] wb_bte_o;
    reg [31:0] wb_dat_i;
    reg wb_ack_i;
    reg wb_err_i;

    reg [31:0] held_addr;
    reg [31:0] held_data;
    reg [3:0] held_sel;
    reg held_we;
    reg [2:0] held_cti;
    reg [1:0] held_bte;
    reg saw_timeout;
    integer cycle;

    wishbone_master dut (
        .clk(clk), .rst_n(rst_n), .cmd_valid(cmd_valid), .cmd_ready(cmd_ready),
        .cmd_addr(cmd_addr), .cmd_wdata(cmd_wdata), .cmd_we(cmd_we), .cmd_sel(cmd_sel),
        .rsp_valid(rsp_valid), .rsp_rdata(rsp_rdata), .rsp_err(rsp_err), .busy(busy),
        .wb_adr_o(wb_adr_o), .wb_dat_o(wb_dat_o), .wb_sel_o(wb_sel_o), .wb_we_o(wb_we_o),
        .wb_cyc_o(wb_cyc_o), .wb_stb_o(wb_stb_o), .wb_cti_o(wb_cti_o), .wb_bte_o(wb_bte_o),
        .wb_dat_i(wb_dat_i), .wb_ack_i(wb_ack_i), .wb_err_i(wb_err_i)
    );

    always #5 clk = ~clk;

    task assert_true;
        input condition;
        input [255:0] message;
        begin
            if (condition !== 1'b1)
                $fatal(1, "ASSERT %0s", message);
        end
    endtask

    task start_request;
        input [31:0] address;
        input [31:0] data;
        input write_enable;
        input [3:0] select;
        begin
            @(negedge clk);
            cmd_addr = address;
            cmd_wdata = data;
            cmd_we = write_enable;
            cmd_sel = select;
            cmd_valid = 1'b1;
            @(posedge clk);
            #1;
            cmd_valid = 1'b0;
        end
    endtask

    task check_response_pulse_clear;
        begin
            @(negedge clk);
            wb_ack_i = 1'b0;
            wb_err_i = 1'b0;
            @(posedge clk);
            #1;
            assert_true(!rsp_valid && !rsp_err, "response outputs must be one-cycle pulses");
            assert_true(!wb_cyc_o && !wb_stb_o, "bus must remain idle after response");
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        cmd_valid = 1'b0;
        cmd_addr = 32'd0;
        cmd_wdata = 32'd0;
        cmd_we = 1'b0;
        cmd_sel = 4'd0;
        wb_dat_i = 32'd0;
        wb_ack_i = 1'b0;
        wb_err_i = 1'b0;

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        /* Normal read ACK and Classic cycle fields. */
        start_request(32'h1000_0020, 32'h0000_0000, 1'b0, 4'b1111);
        assert_true(cmd_ready == 1'b0 && busy == 1'b1, "accepted command must make master busy");
        assert_true(wb_cyc_o && wb_stb_o, "read request must assert CYC and STB");
        assert_true(wb_adr_o == 32'h1000_0020 && wb_dat_o == 32'd0, "read request fields");
        assert_true(wb_sel_o == 4'b1111 && !wb_we_o, "read select and direction");
        assert_true(wb_cti_o == 3'b000 && wb_bte_o == 2'b00, "Classic CTI and BTE values");
        @(negedge clk);
        wb_dat_i = 32'hcafe_beef;
        wb_ack_i = 1'b1;
        @(posedge clk);
        #1;
        assert_true(rsp_valid && !rsp_err, "read ACK must produce a successful response");
        assert_true(rsp_rdata == 32'hcafe_beef, "read ACK data must be returned");
        assert_true(!wb_cyc_o && !wb_stb_o, "read ACK must end the bus cycle");
        check_response_pulse_clear;

        /* Normal write ACK. */
        start_request(32'h1000_0040, 32'h1234_5678, 1'b1, 4'b0011);
        assert_true(wb_adr_o == 32'h1000_0040 && wb_dat_o == 32'h1234_5678,
                    "write request address and data");
        assert_true(wb_sel_o == 4'b0011 && wb_we_o, "write select and direction");
        assert_true(wb_cti_o == 3'b000 && wb_bte_o == 2'b00, "write must use Classic fields");
        @(negedge clk);
        wb_ack_i = 1'b1;
        @(posedge clk);
        #1;
        assert_true(rsp_valid && !rsp_err, "write ACK must produce a successful response");
        check_response_pulse_clear;

        /* Stall a write and prove every request signal stays stable. */
        start_request(32'h2000_0080, 32'hdead_beef, 1'b1, 4'b0101);
        held_addr = wb_adr_o;
        held_data = wb_dat_o;
        held_sel = wb_sel_o;
        held_we = wb_we_o;
        held_cti = wb_cti_o;
        held_bte = wb_bte_o;
        for (cycle = 0; cycle < 4; cycle = cycle + 1) begin
            @(posedge clk);
            #1;
            assert_true(wb_cyc_o && wb_stb_o && busy, "stalled request must remain active");
            assert_true(wb_adr_o == held_addr && wb_dat_o == held_data && wb_sel_o == held_sel,
                        "address, data, and select must remain stable during stall");
            assert_true(wb_we_o == held_we && wb_cti_o == held_cti && wb_bte_o == held_bte,
                        "write, CTI, and BTE must remain stable during stall");
            assert_true(!rsp_valid && !rsp_err, "stall must not produce a response");
        end
        @(negedge clk);
        wb_ack_i = 1'b1;
        @(posedge clk);
        #1;
        assert_true(rsp_valid && !rsp_err, "stalled request must complete on ACK");
        check_response_pulse_clear;

        /* Explicit Wishbone ERR. */
        start_request(32'h3000_0000, 32'd0, 1'b0, 4'b1111);
        @(negedge clk);
        wb_dat_i = 32'hface_cafe;
        wb_err_i = 1'b1;
        @(posedge clk);
        #1;
        assert_true(rsp_valid && rsp_err, "explicit ERR must produce an error response");
        assert_true(rsp_rdata == 32'hface_cafe, "ERR response must capture bus data");
        assert_true(!wb_cyc_o && !wb_stb_o, "ERR must end the bus cycle");
        check_response_pulse_clear;

        /* Reset must cancel an in-flight request and clear its response state. */
        start_request(32'h4000_0000, 32'habcd_ef01, 1'b1, 4'b1111);
        assert_true(wb_cyc_o && wb_stb_o && busy, "request must be active before reset");
        @(negedge clk);
        rst_n = 1'b0;
        @(posedge clk);
        #1;
        assert_true(cmd_ready && !busy, "reset must return master to idle");
        assert_true(!rsp_valid && !rsp_err, "reset must cancel response state");
        assert_true(!wb_cyc_o && !wb_stb_o, "reset must cancel the bus cycle");
        assert_true(wb_adr_o == 32'd0 && wb_dat_o == 32'd0 && wb_sel_o == 4'd0 && !wb_we_o,
                    "reset must clear request fields");
        assert_true(wb_cti_o == 3'b000 && wb_bte_o == 2'b00, "reset must clear Classic fields");
        @(negedge clk);
        rst_n = 1'b1;

        /* Red case: no ACK/ERR must eventually become a bounded error response. */
        start_request(32'h5000_0000, 32'd0, 1'b0, 4'b1111);
        saw_timeout = 1'b0;
        wb_ack_i = 1'b0;
        wb_err_i = 1'b0;
        for (cycle = 0; cycle < TIMEOUT_OBSERVATION_CYCLES && !saw_timeout; cycle = cycle + 1) begin
            @(posedge clk);
            #1;
            if (rsp_valid) begin
                assert_true(rsp_err, "timeout response must set rsp_err");
                assert_true(!wb_cyc_o && !wb_stb_o, "timeout response must cancel the bus cycle");
                saw_timeout = 1'b1;
                check_response_pulse_clear;
            end
        end
        if (!saw_timeout)
            $fatal(1, "ASSERT timeout: no rsp_valid+rsp_err and bus cancellation within %0d cycles",
                   TIMEOUT_OBSERVATION_CYCLES);

        $display("PASS: wishbone_master contract");
        $finish;
    end
endmodule
