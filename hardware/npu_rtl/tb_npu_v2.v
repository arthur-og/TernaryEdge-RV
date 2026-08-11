/*
 * tb_npu_v2.v — Verilog Testbench for NPU Ternária v2
 * Ternary Edge-RV Project
 *
 * Self-checking testbench that:
 *   1. Instantiates npu_ternaria_top_v2
 *   2. Tests register read/write via Wishbone Slave
 *   3. Loads test data into RAM (simulated external memory)
 *   4. Configures and starts NPU inference
 *   5. Waits for IRQ (with timeout)
 *   6. Reads result and compares with expected value
 *   7. Verifies STATUS register bit layout
 *
 * Run with iverilog:
 *   iverilog -o tb_npu_v2.vvp tb_npu_v2.v npu_ternaria_top_v2.v
 *           ternary_mac.v ternary_mac_array.v adder_tree_64.v
 *   vvp tb_npu_v2.vvp
 *   gtkwave tb_npu_v2.vcd
 */

`timescale 1ns / 1ps

`include "npu_v2_pkg.v"

module tb_npu_v2;

    // =========================================================================
    // Signals
    // =========================================================================
    reg         clk;
    reg         rst_n;

    // Wishbone Slave (CPU → NPU)
    reg  [31:0] wb_s_adr_i;
    reg  [31:0] wb_s_dat_i;
    reg  [3:0]  wb_s_sel_i;
    reg         wb_s_we_i;
    reg         wb_s_cyc_i;
    reg         wb_s_stb_i;
    wire [31:0] wb_s_dat_o;
    wire        wb_s_ack_o;

    // Wishbone Master (NPU → RAM)
    wire [31:0] wb_m_adr_o;
    wire [31:0] wb_m_dat_o;
    wire [3:0]  wb_m_sel_o;
    wire        wb_m_we_o;
    wire        wb_m_cyc_o;
    wire        wb_m_stb_o;
    wire [2:0]  wb_m_cti_o;
    wire [1:0]  wb_m_bte_o;
    reg  [31:0] wb_m_dat_i;
    reg         wb_m_ack_i;
    reg         wb_m_err_i;

    // Interrupt
    wire        irq_out;

    // =========================================================================
    // External RAM (simulated — responds to Wishbone Master reads)
    // =========================================================================
    reg [31:0] ext_ram [0:262143];  // 1 MB simulated RAM

    integer test_errors;
    reg [31:0] readback;
    integer i;

    localparam integer WB_TIMEOUT_CYCLES  = 64;
    localparam integer IRQ_TIMEOUT_CYCLES = 1000000;
    localparam [31:0] TEST_SRC_ADDR = 32'h0000_0000;
    localparam [31:0] TEST_DST_ADDR = 32'h0004_0000;

    // Wishbone Master slave logic (responds to NPU's read requests)
    reg [31:0] wb_m_lat_addr;
    reg        wb_m_lat_we;
    reg        wb_m_got_stb;

    integer tb_ack_cnt;

    // The response phase is registered, and read data is combinational from
    // the latched address.  This makes the data stable before the DUT samples
    // the acknowledgement edge.
    always @(*) begin
        wb_m_ack_i = wb_m_got_stb;
        wb_m_err_i = 1'b0;
        wb_m_dat_i = 32'd0;

        if (wb_m_got_stb && !wb_m_lat_we) begin
            if ((wb_m_lat_addr / 4) < 262144)
                wb_m_dat_i = ext_ram[wb_m_lat_addr / 4];
            else
                wb_m_dat_i = 32'hDEAD;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            wb_m_got_stb <= 1'b0;
            wb_m_lat_addr <= 32'd0;
            wb_m_lat_we <= 1'b0;
            tb_ack_cnt <= 0;
        end else begin
            if (wb_m_got_stb) begin
                wb_m_got_stb <= 1'b0;
                tb_ack_cnt <= tb_ack_cnt + 1;

                if (wb_m_lat_we && ((wb_m_lat_addr / 4) < 262144))
                    ext_ram[wb_m_lat_addr / 4] <= wb_m_dat_o;
            end else if (wb_m_cyc_o && wb_m_stb_o) begin
                // Latch the request, then expose a response on the next cycle.
                wb_m_lat_addr <= wb_m_adr_o;
                wb_m_lat_we <= wb_m_we_o;
                wb_m_got_stb <= 1'b1;
            end
        end
    end

    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    npu_ternaria_top_v2 u_dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .wb_s_adr_i (wb_s_adr_i),
        .wb_s_dat_i (wb_s_dat_i),
        .wb_s_sel_i (wb_s_sel_i),
        .wb_s_we_i  (wb_s_we_i),
        .wb_s_cyc_i (wb_s_cyc_i),
        .wb_s_stb_i (wb_s_stb_i),
        .wb_s_dat_o (wb_s_dat_o),
        .wb_s_ack_o (wb_s_ack_o),
        .wb_m_adr_o (wb_m_adr_o),
        .wb_m_dat_o (wb_m_dat_o),
        .wb_m_sel_o (wb_m_sel_o),
        .wb_m_we_o  (wb_m_we_o),
        .wb_m_cyc_o (wb_m_cyc_o),
        .wb_m_stb_o (wb_m_stb_o),
        .wb_m_cti_o (wb_m_cti_o),
        .wb_m_bte_o (wb_m_bte_o),
        .wb_m_dat_i (wb_m_dat_i),
        .wb_m_ack_i (wb_m_ack_i),
        .wb_m_err_i (wb_m_err_i),
        .irq_out    (irq_out)
    );

    // =========================================================================
    // Clock Generator (50 MHz → 20 ns period)
    // =========================================================================
    always #10 clk = ~clk;

    // =========================================================================
    // Wishbone Slave Helper Tasks
    // =========================================================================
    task wb_write(input [31:0] addr, input [31:0] data);
        integer cycle_count;
        reg ack_seen;
        begin
            @(negedge clk);
            wb_s_adr_i = addr;
            wb_s_dat_i = data;
            wb_s_sel_i = 4'b1111;
            wb_s_we_i  = 1'b1;
            wb_s_cyc_i = 1'b1;
            wb_s_stb_i = 1'b1;
            ack_seen = 1'b0;
            for (cycle_count = 0;
                 cycle_count < WB_TIMEOUT_CYCLES && !ack_seen;
                 cycle_count = cycle_count + 1) begin
                @(posedge clk);
                #1;
                if (wb_s_ack_o === 1'b1)
                    ack_seen = 1'b1;
            end

            if (!ack_seen) begin
                $display("  ✗ Wishbone write timeout at 0x%08X", addr);
                test_errors = test_errors + 1;
            end

            @(negedge clk);
            wb_s_cyc_i = 1'b0;
            wb_s_stb_i = 1'b0;
            wb_s_we_i  = 1'b0;
            wb_s_sel_i = 4'b0000;
        end
    endtask

    task wb_read(input [31:0] addr, output [31:0] data);
        integer cycle_count;
        reg ack_seen;
        begin
            @(negedge clk);
            wb_s_adr_i = addr;
            wb_s_sel_i = 4'b1111;
            wb_s_we_i  = 1'b0;
            wb_s_cyc_i = 1'b1;
            wb_s_stb_i = 1'b1;
            ack_seen = 1'b0;
            data = 32'd0;
            for (cycle_count = 0;
                 cycle_count < WB_TIMEOUT_CYCLES && !ack_seen;
                 cycle_count = cycle_count + 1) begin
                @(posedge clk);
                #1;
                if (wb_s_ack_o === 1'b1) begin
                    ack_seen = 1'b1;
                    data = wb_s_dat_o;
                end
            end

            if (!ack_seen) begin
                $display("  ✗ Wishbone read timeout at 0x%08X", addr);
                test_errors = test_errors + 1;
            end

            @(negedge clk);
            wb_s_cyc_i = 1'b0;
            wb_s_stb_i = 1'b0;
            wb_s_sel_i = 4'b0000;
        end
    endtask

    task wait_for_irq(input integer max_cycles);
        integer cycle_count;
        reg irq_seen;
        begin
            irq_seen = (irq_out === 1'b1);
            for (cycle_count = 0;
                 cycle_count < max_cycles && !irq_seen;
                 cycle_count = cycle_count + 1) begin
                @(posedge clk);
                #1;
                if (irq_out === 1'b1)
                    irq_seen = 1'b1;
            end

            if (!irq_seen) begin
                $display("  ✗ IRQ timeout after %0d cycles", max_cycles);
                test_errors = test_errors + 1;
            end else begin
                $display("  ✓ IRQ received after %0d cycles", cycle_count);
            end
        end
    endtask

    // =========================================================================
    // Test
    // =========================================================================
    initial begin
        $display("==================================================");
        $display(" NPU Ternária v2 — Testbench de Validação");
        $display(" 64 MACs | Wishbone Master DMA | Fixed Layer-0 Contract");
        $display(" Ternary Edge-RV Project");
        $display("==================================================");

        // Initialize
        clk    = 0;
        rst_n  = 0;
        wb_s_adr_i = 32'd0;
        wb_s_dat_i = 32'd0;
        wb_s_sel_i = 4'b0000;
        wb_s_we_i  = 1'b0;
        wb_s_cyc_i = 1'b0;
        wb_s_stb_i = 1'b0;

        test_errors = 0;

        // Initialize external RAM to zeros
        for (i = 0; i < 262144; i = i + 1) ext_ram[i] = 32'd0;

        // VCD dump
        $dumpfile("tb_npu_v2.vcd");
        $dumpvars(0, tb_npu_v2);

        // Release reset
        #50;
        rst_n = 1;
        $display("\n[INFO] Reset liberado. Iniciando testes...\n");

        // =====================================================================
        // TEST 1: Register Write/Read
        // =====================================================================
        $display("[TEST 1] Wishbone Slave Register Access");

        wb_write(`REG_SRC_ADDR, 32'hAABBCCDD);
        wb_read(`REG_SRC_ADDR, readback);
        if (readback === 32'hAABBCCDD)
            $display("  ✓ SRC_ADDR write/read");
        else begin
            $display("  ✗ SRC_ADDR: expected AABBCCDD, got %h", readback);
            test_errors = test_errors + 1;
        end

        wb_write(`REG_DST_ADDR, TEST_DST_ADDR);
        wb_read(`REG_DST_ADDR, readback);
        if (readback === TEST_DST_ADDR)
            $display("  ✓ DST_ADDR write/read");
        else begin
            $display("  ✗ DST_ADDR: expected %h, got %h", TEST_DST_ADDR, readback);
            test_errors = test_errors + 1;
        end

        wb_write(`REG_LAYER_CFG, 32'd1);
        wb_read(`REG_LAYER_CFG, readback);
        if (readback === 32'd1)
            $display("  ✓ LAYER_CFG write/read");
        else begin
            $display("  ✗ LAYER_CFG: expected 1, got %d", readback);
            test_errors = test_errors + 1;
        end

        wb_write(`REG_MAC_CFG, 32'd64);
        wb_read(`REG_MAC_CFG, readback);
        if (readback == 32'd64)
            $display("  ✓ MAC_CFG write/read (default 64)");
        else begin
            $display("  ✗ MAC_CFG: expected 64, got %d", readback);
            test_errors = test_errors + 1;
        end

        // =====================================================================
        // TEST 2: STATUS Register (Bit Layout)
        // =====================================================================
        $display("\n[TEST 2] STATUS Register — Idle State");

        wb_read(`REG_STATUS, readback);
        if (readback === 32'd0)
            $display("  ✓ STATUS = 0x00000000 (idle)");
        else begin
            $display("  ✗ STATUS idle value: expected 00000000, got %h", readback);
            test_errors = test_errors + 1;
        end

        // =====================================================================
        // TEST 3: Fixed layer-0 DMA/accumulation regression
        // =====================================================================
        $display("\n[TEST 3] Fixed layer-0 DMA/accumulation regression");

        // The first 64 activation bytes are 1..64.  The remaining bytes of
        // layer 0 are already zero from RAM initialization.  The four words
        // below encode +1,+1,-1,-1 in the repository's 2-bit format.
        for (i = 0; i < 64; i = i + 1)
            ext_ram[i / 4][(i % 4) * 8 +: 8] = i + 1;

        for (i = 0; i < 50176; i = i + 1)
            ext_ram[(TEST_SRC_ADDR + 4096) / 4 + i] = 32'd0;
        ext_ram[(TEST_SRC_ADDR + 4096) / 4 + 0] = 32'h55555555;
        ext_ram[(TEST_SRC_ADDR + 4096) / 4 + 1] = 32'h55555555;
        ext_ram[(TEST_SRC_ADDR + 4096) / 4 + 2] = 32'hFFFFFFFF;
        ext_ram[(TEST_SRC_ADDR + 4096) / 4 + 3] = 32'hFFFFFFFF;

        // Sentinels ensure the output assertions prove that every checked
        // destination word was written by the result DMA.
        for (i = 0; i < 1024; i = i + 1)
            ext_ram[TEST_DST_ADDR / 4 + i] = 32'hA5A5A5A5;

        wb_write(`REG_SRC_ADDR, TEST_SRC_ADDR);
        wb_write(`REG_DST_ADDR, TEST_DST_ADDR);
        wb_write(`REG_MAC_CFG, 32'd64);
        wb_write(`REG_LAYER_CFG, 32'd1);
        wb_write(`REG_CONTROL, 32'd1);
        wait_for_irq(IRQ_TIMEOUT_CYCLES);

        if (irq_out === 1'b1)
            $display("  ✓ completion IRQ asserted");
        else begin
            $display("  ✗ completion IRQ is not asserted");
            test_errors = test_errors + 1;
        end

        if (ext_ram[TEST_DST_ADDR / 4] === 32'hFFFF_FC00)
            $display("  ✓ destination output 0 = 0xFFFFFC00");
        else begin
            $display("  ✗ destination output 0: expected FFFFFC00, got %h",
                     ext_ram[TEST_DST_ADDR / 4]);
            test_errors = test_errors + 1;
        end

        if (ext_ram[TEST_DST_ADDR / 4 + 1] === 32'd0)
            $display("  ✓ destination output 1 = 0");
        else begin
            $display("  ✗ destination output 1: expected 00000000, got %h",
                     ext_ram[TEST_DST_ADDR / 4 + 1]);
            test_errors = test_errors + 1;
        end

        if (ext_ram[TEST_DST_ADDR / 4 + 1023] === 32'd0)
            $display("  ✓ destination output 1023 = 0");
        else begin
            $display("  ✗ destination output 1023: expected 00000000, got %h",
                     ext_ram[TEST_DST_ADDR / 4 + 1023]);
            test_errors = test_errors + 1;
        end

        for (i = 2; i < 1023; i = i + 1) begin
            if (ext_ram[TEST_DST_ADDR / 4 + i] !== 32'd0) begin
                $display("  ✗ destination output %0d: expected 00000000, got %h",
                         i, ext_ram[TEST_DST_ADDR / 4 + i]);
                test_errors = test_errors + 1;
            end
        end

        wb_read(`REG_STATUS, readback);
        if (readback === 32'h0000_C003)
            $display("  ✓ STATUS = 0x0000C003");
        else begin
            $display("  ✗ STATUS: expected 0000C003, got %h", readback);
            test_errors = test_errors + 1;
        end

        wb_write(`REG_CONTROL, 32'd2);
        if (irq_out === 1'b0)
            $display("  ✓ clear_irq deasserted IRQ");
        else begin
            $display("  ✗ clear_irq left IRQ asserted");
            test_errors = test_errors + 1;
        end

        wb_read(`REG_STATUS, readback);
        if (readback === 32'h0000_C000)
            $display("  ✓ STATUS after clear = 0x0000C000");
        else begin
            $display("  ✗ STATUS after clear: expected 0000C000, got %h", readback);
            test_errors = test_errors + 1;
        end

        // =====================================================================
        // TEST 4: Two-layer all-zero termination smoke test
        // =====================================================================
        $display("\n[TEST 4] Two-layer all-zero termination smoke test");
        for (i = 0; i < 262144; i = i + 1)
            ext_ram[i] = 32'd0;

        wb_write(`REG_SRC_ADDR, TEST_SRC_ADDR);
        wb_write(`REG_DST_ADDR, TEST_DST_ADDR);
        wb_write(`REG_MAC_CFG, 32'd64);
        wb_write(`REG_LAYER_CFG, 32'd2);
        wb_write(`REG_CONTROL, 32'd1);
        wait_for_irq(IRQ_TIMEOUT_CYCLES);

        if (irq_out === 1'b1)
            $display("  ✓ two-layer completion IRQ asserted");
        else begin
            $display("  ✗ two-layer completion IRQ is not asserted");
            test_errors = test_errors + 1;
        end

        wb_write(`REG_CONTROL, 32'd2);

        // =====================================================================
        // Final Summary
        // =====================================================================
        #100;
        $display("\n==================================================");
        if (test_errors == 0) begin
            $display(" PASS: fixed layer-0 regression");
        end else begin
            $display(" FAIL: %d test error(s)", test_errors);
        end
        $display("==================================================");

        if (test_errors == 0)
            $finish;
        else
            $fatal(1);
    end

endmodule
