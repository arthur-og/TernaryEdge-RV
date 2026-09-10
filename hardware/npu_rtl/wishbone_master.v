`timescale 1ns / 1ps

/* Single-beat Wishbone Classic DMA master.
 * The request remains asserted and stable until ACK or ERR. */
module wishbone_master #(
    parameter integer TIMEOUT_CYCLES = 256
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        cmd_valid,
    output wire        cmd_ready,
    input  wire [31:0] cmd_addr,
    input  wire [31:0] cmd_wdata,
    input  wire        cmd_we,
    input  wire [3:0]  cmd_sel,
    output reg         rsp_valid,
    output reg  [31:0] rsp_rdata,
    output reg         rsp_err,
    output wire        busy,
    output reg  [31:0] wb_adr_o,
    output reg  [31:0] wb_dat_o,
    output reg  [3:0]  wb_sel_o,
    output reg         wb_we_o,
    output reg         wb_cyc_o,
    output reg         wb_stb_o,
    output reg  [2:0]  wb_cti_o,
    output reg  [1:0]  wb_bte_o,
    input  wire [31:0] wb_dat_i,
    input  wire        wb_ack_i,
    input  wire        wb_err_i
);
    localparam integer TIMEOUT_COUNT_WIDTH = (TIMEOUT_CYCLES < 2) ? 1 :
                                             $clog2(TIMEOUT_CYCLES + 1);
    localparam integer TIMEOUT_LAST = TIMEOUT_CYCLES - 1;
    localparam ST_IDLE = 1'b0;
    localparam ST_WAIT = 1'b1;
    reg state;
    reg [TIMEOUT_COUNT_WIDTH-1:0] timeout_count;

    generate
        if (TIMEOUT_CYCLES < 1) begin : gen_invalid_timeout
            initial $fatal(1, "TIMEOUT_CYCLES must be at least 1");
        end
    endgenerate

    assign cmd_ready = (state == ST_IDLE);
    assign busy = (state == ST_WAIT);

    always @(posedge clk) begin
        if (!rst_n) begin
            state      <= ST_IDLE;
            timeout_count <= {TIMEOUT_COUNT_WIDTH{1'b0}};
            rsp_valid  <= 1'b0;
            rsp_rdata  <= 32'd0;
            rsp_err    <= 1'b0;
            wb_adr_o   <= 32'd0;
            wb_dat_o   <= 32'd0;
            wb_sel_o   <= 4'd0;
            wb_we_o    <= 1'b0;
            wb_cyc_o   <= 1'b0;
            wb_stb_o   <= 1'b0;
            wb_cti_o   <= 3'b000;
            wb_bte_o   <= 2'b00;
        end else begin
            rsp_valid <= 1'b0;
            rsp_err   <= 1'b0;

            case (state)
                ST_IDLE: begin
                    wb_cyc_o <= 1'b0;
                    wb_stb_o <= 1'b0;
                    timeout_count <= {TIMEOUT_COUNT_WIDTH{1'b0}};
                    if (cmd_valid) begin
                        wb_adr_o <= cmd_addr;
                        wb_dat_o <= cmd_wdata;
                        wb_sel_o <= cmd_sel;
                        wb_we_o  <= cmd_we;
                        wb_cti_o <= 3'b000;
                        wb_bte_o <= 2'b00;
                        wb_cyc_o <= 1'b1;
                        wb_stb_o <= 1'b1;
                        timeout_count <= {TIMEOUT_COUNT_WIDTH{1'b0}};
                        state    <= ST_WAIT;
                    end
                end

                ST_WAIT: begin
                    /* All request signals stay unchanged while stalled. */
                    wb_cyc_o <= 1'b1;
                    wb_stb_o <= 1'b1;
                    if (wb_err_i || wb_ack_i) begin
                        rsp_valid <= 1'b1;
                        rsp_err   <= wb_err_i;
                        rsp_rdata <= wb_dat_i;
                        wb_cyc_o  <= 1'b0;
                        wb_stb_o  <= 1'b0;
                        timeout_count <= {TIMEOUT_COUNT_WIDTH{1'b0}};
                        state     <= ST_IDLE;
                    end else if (timeout_count == TIMEOUT_LAST[TIMEOUT_COUNT_WIDTH-1:0]) begin
                        rsp_valid <= 1'b1;
                        rsp_err   <= 1'b1;
                        wb_cyc_o  <= 1'b0;
                        wb_stb_o  <= 1'b0;
                        timeout_count <= {TIMEOUT_COUNT_WIDTH{1'b0}};
                        state     <= ST_IDLE;
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end
            endcase
        end
    end
endmodule
