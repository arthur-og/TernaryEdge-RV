/*
 * wishbone_master.v — Wishbone B4 Master (DMA Controller)
 * Ternary Edge-RV Project
 *
 * Implements a Wishbone B4 Standard Master for the NPU DMA engine.
 *
 * Features:
 *   - 32-bit data bus, 32-bit address
 *   - Incrementing burst reads and writes
 *   - Configurable burst length
 *   - Classic handshake (stb/ack)
 *   - Error handling with abort
 *
 * Interface:
 *   CPU side: cmd_addr, cmd_data, cmd_we, cmd_valid → cmd_ready
 *   Wishbone: cyc_o, stb_o, adr_o, dat_o, we_o, sel_o
 *             dat_i, ack_i, err_i (Wishbone is SLAVE perspective)
 *   Note: From the system perspective, NPU IS the Wishbone Master.
 *         The signals use _o (output) for master, _i (input) for slave response.
 */

module wishbone_master (
    input  wire        clk,
    input  wire        rst_n,

    // ---- Command Interface (from NPU FSM) ----
    input  wire        cmd_valid,    // Command valid
    output reg         cmd_ready,    // Command accepted (ready for next)
    input  wire [31:0] cmd_addr,     // Start address
    input  wire        cmd_we,       // 1=write, 0=read
    input  wire [15:0] cmd_length,   // Number of bytes to transfer

    // ---- Data Output (for read commands) ----
    output reg         data_valid,   // Read data valid
    output reg  [31:0] data_out,     // Read data

    // ---- Data Input (for write commands) ----
    input  wire        data_in_valid,// Write data valid
    input  wire [31:0] data_in,      // Write data

    // ---- Status ----
    output reg         busy,         // Transaction in progress
    output reg         error,        // Wishbone error occurred

    // ---- Wishbone Master Interface ----
    output reg         wb_cyc_o,
    output reg         wb_stb_o,
    output reg  [31:0] wb_adr_o,
    output reg  [31:0] wb_dat_o,
    output reg         wb_we_o,
    output reg  [3:0]  wb_sel_o,
    output reg  [2:0]  wb_cti_o,    // Cycle Type Identifier (Burst)
    output reg  [1:0]  wb_bte_o,    // Burst Type Extension
    input  wire [31:0] wb_dat_i,
    input  wire        wb_ack_i,
    input  wire        wb_err_i
);

    // =========================================================================
    // Constants
    // =========================================================================
    localparam CTI_CLASSIC       = 3'b000;  // Single transfer
    localparam CTI_INCR_BURST    = 3'b010;  // Incrementing burst
    localparam CTI_END_BURST     = 3'b111;  // End of burst
    localparam BTE_LINEAR        = 2'b00;   // Linear burst

    // =========================================================================
    // FSM States
    // =========================================================================
    localparam ST_IDLE    = 3'd0;
    localparam ST_ADDR    = 3'd1;   // Issue address + strobe
    localparam ST_WAIT    = 3'd2;   // Wait for ack
    localparam ST_DATA    = 3'd3;   // Data phase (read capture or write next)
    localparam ST_DONE    = 3'd4;   // Transaction complete
    localparam ST_ERROR   = 3'd5;   // Error occurred

    reg [2:0] state, next_state;

    // =========================================================================
    // Registers
    // =========================================================================
    reg [31:0] current_addr;
    reg [15:0] bytes_remaining;
    reg [15:0] burst_count;        // Words remaining in current burst
    reg        read_in_progress;

    // =========================================================================
    // FSM (sequential)
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            state            <= ST_IDLE;
            cmd_ready        <= 1'b0;
            data_valid       <= 1'b0;
            data_out         <= 32'd0;
            busy             <= 1'b0;
            error            <= 1'b0;
            current_addr     <= 32'd0;
            bytes_remaining  <= 16'd0;
            burst_count      <= 16'd0;
            read_in_progress <= 1'b0;
            wb_cyc_o         <= 1'b0;
            wb_stb_o         <= 1'b0;
            wb_adr_o         <= 32'd0;
            wb_dat_o         <= 32'd0;
            wb_we_o          <= 1'b0;
            wb_sel_o         <= 4'b0000;
            wb_cti_o         <= CTI_CLASSIC;
            wb_bte_o         <= BTE_LINEAR;
        end else begin
            state <= next_state;

            // Default: clear strobes after 1 cycle
            case (state)
                ST_ADDR: begin
                    // Addr/strobe issued this cycle, clear ready signals
                    cmd_ready  <= 1'b0;
                    data_valid <= 1'b0;
                end

                ST_WAIT: begin
                    // Waiting for ack — nothing to clear
                end

                ST_DATA: begin
                    // Data phase
                    if (!read_in_progress) begin
                        // Write: accept next data word
                        data_valid <= 1'b0;
                    end
                end

                ST_DONE: begin
                    busy     <= 1'b0;
                    cmd_ready <= 1'b1;
                end

                ST_ERROR: begin
                    error    <= 1'b1;
                    busy     <= 1'b0;
                    wb_cyc_o <= 1'b0;
                    wb_stb_o <= 1'b0;
                end
            endcase
        end
    end

    // =========================================================================
    // FSM (combinational next-state)
    // =========================================================================
    always @(*) begin
        next_state = state;

        case (state)
            ST_IDLE: begin
                if (cmd_valid && !busy) begin
                    next_state = ST_ADDR;
                end
            end

            ST_ADDR: begin
                // Address and strobe issued this cycle
                // Next: wait for ack
                next_state = ST_WAIT;
            end

            ST_WAIT: begin
                if (wb_ack_i) begin
                    // Got acknowledge
                    next_state = ST_DATA;
                end else if (wb_err_i) begin
                    next_state = ST_ERROR;
                end else begin
                    next_state = ST_WAIT;  // Keep waiting
                end
            end

            ST_DATA: begin
                if (bytes_remaining <= 4) begin
                    // Last word — end transaction
                    next_state = ST_DONE;
                end else begin
                    // More words to transfer
                    next_state = ST_ADDR;
                end
            end

            ST_DONE: begin
                // Wait for command to be deasserted
                if (!cmd_valid) begin
                    next_state = ST_IDLE;
                end
            end

            ST_ERROR: begin
                next_state = ST_ERROR;  // Stay in error until reset
            end
        endcase
    end

    // =========================================================================
    // Datapath Logic
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            current_addr    <= 32'd0;
            bytes_remaining <= 16'd0;
            burst_count     <= 16'd0;
        end else begin
            case (state)
                ST_IDLE: begin
                    if (cmd_valid && !busy) begin
                        // Latch command parameters
                        current_addr    <= cmd_addr;
                        bytes_remaining <= cmd_length;
                        read_in_progress <= !cmd_we;
                        burst_count     <= (cmd_length + 3) >> 2;  // Ceiling div by 4
                        busy            <= 1'b1;

                        // Drive Wishbone signals
                        wb_adr_o <= cmd_addr;
                        wb_dat_o <= data_in;
                        wb_we_o  <= cmd_we;
                        wb_sel_o <= 4'b1111;
                        wb_cti_o <= CTI_INCR_BURST;
                        wb_bte_o <= BTE_LINEAR;
                        wb_cyc_o <= 1'b1;
                        wb_stb_o <= 1'b1;
                    end
                end

                ST_ADDR: begin
                    // Issue address
                    wb_adr_o <= current_addr;
                    wb_dat_o <= data_in;
                    wb_stb_o <= 1'b1;
                    wb_sel_o <= 4'b1111;
                end

                ST_WAIT: begin
                    // Deassert strobe while waiting
                    wb_stb_o <= 1'b0;

                    if (wb_ack_i) begin
                        // Capture read data
                        if (read_in_progress) begin
                            data_out   <= wb_dat_i;
                            data_valid <= 1'b1;
                        end

                        // Update counters
                        current_addr    <= current_addr + 4;
                        bytes_remaining <= bytes_remaining - 4;
                        burst_count     <= burst_count - 1;

                        if (burst_count <= 1) begin
                            // Last transfer — signal end of burst
                            wb_cti_o <= CTI_END_BURST;
                        end
                    end

                    if (wb_err_i) begin
                        wb_cyc_o <= 1'b0;
                    end
                end

                ST_DATA: begin
                    // Data phase complete
                    wb_stb_o <= 1'b0;

                    if (bytes_remaining <= 4) begin
                        // Transaction done
                        wb_cyc_o <= 1'b0;
                        wb_cti_o <= CTI_CLASSIC;
                    end
                end

                ST_DONE: begin
                    wb_cyc_o <= 1'b0;
                    wb_stb_o <= 1'b0;
                end
            endcase
        end
    end

endmodule
