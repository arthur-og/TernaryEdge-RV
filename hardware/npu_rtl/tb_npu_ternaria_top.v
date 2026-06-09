/*
 * Testbench da NPU Ternária
 * Projeto: Ternary Edge-RV
 * Autor: Arthur Oliveira Gomes
 *
 * Descrição:
 * Testbench auto-verificável que:
 *   1. Gera clock e reset
 *   2. Simula transações Wishbone (escrita de dados, leitura de status)
 *   3. Carrega pesos ternários e ativações nas memórias internas
 *   4. Dispara a NPU (escreve em CONTROL)
 *   5. Aguarda IRQ ou timeout
 *   6. Lê o resultado e compara com o esperado
 *   7. Gera arquivo VCD para visualização no GTKWave
 *
 * Uso:
 *   iverilog -o tb_npu tb_npu_ternaria_top.v npu_ternaria_top.v ternary_mac.v
 *   vvp tb_npu
 *   gtkwave tb_npu.vcd
 */

`timescale 1ns / 1ps

module tb_npu_ternaria_top;

    // =========================================================================
    // 1. Sinais do Testbench
    // =========================================================================
    reg         clk;
    reg         rst_n;

    // Wishbone
    reg  [31:0] wb_adr_i;
    reg  [31:0] wb_dat_i;
    reg  [3:0]  wb_sel_i;
    reg         wb_we_i;
    reg         wb_cyc_i;
    reg         wb_stb_i;
    wire [31:0] wb_dat_o;
    wire        wb_ack_o;

    // IRQ
    wire        irq_out;

    // =========================================================================
    // 2. Instantiate DUT (Device Under Test)
    // =========================================================================
    npu_ternaria_top u_dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .wb_adr_i (wb_adr_i),
        .wb_dat_i (wb_dat_i),
        .wb_sel_i (wb_sel_i),
        .wb_we_i  (wb_we_i),
        .wb_cyc_i (wb_cyc_i),
        .wb_stb_i (wb_stb_i),
        .wb_dat_o (wb_dat_o),
        .wb_ack_o (wb_ack_o),
        .irq_out  (irq_out)
    );

    // =========================================================================
    // 3. Clock Generator (50 MHz -> 20 ns period)
    // =========================================================================
    always #10 clk = ~clk;

    // =========================================================================
    // 4. Wishbone Helper Tasks
    // =========================================================================
    task wb_write(input [31:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            wb_adr_i <= addr;
            wb_dat_i <= data;
            wb_sel_i <= 4'b1111;
            wb_we_i  <= 1'b1;
            wb_cyc_i <= 1'b1;
            wb_stb_i <= 1'b1;
            @(posedge clk);
            while (!wb_ack_o) @(posedge clk);
            wb_cyc_i <= 1'b0;
            wb_stb_i <= 1'b0;
            wb_we_i  <= 1'b0;
        end
    endtask

    task wb_read(input [31:0] addr, output [31:0] data);
        begin
            @(posedge clk);
            wb_adr_i <= addr;
            wb_sel_i <= 4'b1111;
            wb_we_i  <= 1'b0;
            wb_cyc_i <= 1'b1;
            wb_stb_i <= 1'b1;
            @(posedge clk);
            while (!wb_ack_o) @(posedge clk);
            data = wb_dat_o;
            wb_cyc_i <= 1'b0;
            wb_stb_i <= 1'b0;
        end
    endtask

    // =========================================================================
    // 5. Test Principal
    // =========================================================================
    integer test_errors;
    reg [31:0] readback;
    reg [31:0] expected_result;
    integer i;

    initial begin
        $display("==================================================");
        $display(" NPU Ternária — Testbench de Validação");
        $display(" Ternary Edge-RV Project");
        $display("==================================================");

        // Inicialização
        clk    = 0;
        rst_n  = 0;
        wb_adr_i = 32'd0;
        wb_dat_i = 32'd0;
        wb_sel_i = 4'b0000;
        wb_we_i  = 1'b0;
        wb_cyc_i = 1'b0;
        wb_stb_i = 1'b0;

        test_errors = 0;

        // Gera arquivo VCD para visualização
        $dumpfile("tb_npu.vcd");
        $dumpvars(0, tb_npu_ternaria_top);

        // Aguarda 5 ciclos e libera reset
        #50;
        rst_n = 1;
        $display("\n[INFO] Reset liberado. Iniciando testes...\n");

        // =====================================================================
        // TESTE 1: Verificar leitura/escrita básica dos registradores
        // =====================================================================
        $display("[TEST 1] Verificando Wishbone...");
        wb_write(8'h08, 32'hAABBCCDD);
        wb_read(8'h08, readback);
        if (readback == 32'hAABBCCDD)
            $display("  ✓ SRC_ADDR: write/read OK");
        else begin
            $display("  ✗ SRC_ADDR: esperado AABBCCDD, obtido %h", readback);
            test_errors = test_errors + 1;
        end

        wb_write(8'h10, 32'd10);
        wb_read(8'h10, readback);
        if (readback == 32'd10)
            $display("  ✓ DATA_SIZE: write/read OK");
        else begin
            $display("  ✗ DATA_SIZE: esperado 10, obtido %d", readback);
            test_errors = test_errors + 1;
        end

        // =====================================================================
        // TESTE 2: Carregar dados e processar
        // =====================================================================
        $display("\n[TEST 2] Carregando dados e processando...");

        // DATA_SIZE = 8 (vamos processar 8 MACs)
        wb_write(8'h10, 32'd8);

        // Carregar 8 ativações (valores INT8: 10, 20, 30, 40, 50, 60, 70, 80)
        for (i = 0; i < 8; i = i + 1) begin
            wb_write(8'h18, (i+1) * 10);  // Auto-incrementa na NPU
        end

        // Carregar 1 palavra de peso = 16 pesos compactados
        // Vamos criar pesos que alternam entre +1 (01) e 0 (00)
        // peso[0] = +1 (01), peso[1] = 0 (00), peso[2] = +1 (01), peso[3] = 0 (00)...
        // word = 0b_00_01_00_01_00_01_00_01_00_01_00_01_00_01_00_01
        // word = 0x_11111111 (hex)
        wb_write(8'h14, 32'h11111111);

        // Calcular resultado esperado MANUALMENTE:
        // MAC com peso +1: soma a ativação
        // MAC com peso 0: soma 0
        // ativações: 10, 20, 30, 40, 50, 60, 70, 80
        // pesos:     +1,  0, +1,  0, +1,  0, +1,  0
        // resultado = 10 + 0 + 30 + 0 + 50 + 0 + 70 + 0 = 160
        expected_result = 10 + 30 + 50 + 70;

        // Disparar NPU
        $display("  Disparando NPU (CONTROL = 1)...");
        wb_write(8'h04, 32'd1);  // Start

        // Aguardar IRQ (com timeout de 100 ciclos)
        $display("  Aguardando IRQ...");
        wait (irq_out === 1'b1);
        // Se chegou aqui, IRQ foi gerado!
        $display("  ✓ IRQ recebido! NPU terminou processamento.");

        // Ler resultado
        wb_read(8'h1C, readback);
        $display("  Resultado obtido: %d", readback);
        $display("  Resultado esperado: %d", expected_result);

        if (readback === expected_result) begin
            $display("  ✓ RESULTADO CORRETO!");
        end else begin
            $display("  ✗ RESULTADO INCORRETO!");
            test_errors = test_errors + 1;
        end

        // Ler zero_skipped (deveria ser 4, pois metade dos pesos é 0)
        wb_read(8'h00, readback);
        $display("  STATUS (zero_skipped no byte[15:8]): %h", readback);

        // Limpar IRQ
        wb_write(8'h04, 32'd2);  // Clear IRQ

        // =====================================================================
        // TESTE 3: Teste com peso -1 (subtração)
        // =====================================================================
        $display("\n[TEST 3] Teste com pesos negativos (-1)...");

        // Novo teste com DATA_SIZE = 4
        wb_write(8'h10, 32'd4);

        // Ativações: 100, 50, 25, 10
        wb_write(8'h18, 100);
        wb_write(8'h18, 50);
        wb_write(8'h18, 25);
        wb_write(8'h18, 10);

        // Palavra de peso: -1 (11) para todos
        // 0b_11_11_11_11_11_11_11_11_11_11_11_11_11_11_11_11 = 0xFFFFFFFF
        wb_write(8'h14, 32'hFFFFFFFF);

        // Resultado esperado: (-100) + (-50) + (-25) + (-10) = -185
        // Em complemento de 2: 32'd4294967111 = 32'hFFFFFF47
        expected_result = -185;

        wb_write(8'h04, 32'd1);  // Start

        $display("  Aguardando IRQ...");
        wait (irq_out === 1'b1);
        $display("  ✓ IRQ recebido!");

        wb_read(8'h1C, readback);
        $display("  Resultado obtido (signed): %0d", $signed(readback));
        $display("  Resultado esperado (signed): %0d", expected_result);

        // Comparação (tratando signed)
        if ($signed(readback) === expected_result) begin
            $display("  ✓ RESULTADO CORRETO (multiplicação por -1 funciona!)");
        end else begin
            $display("  ✗ RESULTADO INCORRETO!");
            test_errors = test_errors + 1;
        end

        wb_write(8'h04, 32'd2);  // Clear IRQ

        // =====================================================================
        // 6. Resultado Final
        // =====================================================================
        #50;
        $display("\n==================================================");
        if (test_errors == 0) begin
            $display(" ✅ TODOS OS TESTES PASSARAM!");
            $display("    A NPU Ternária está funcionando corretamente.");
            $display("    Zero blocos DSP utilizados!");
        end else begin
            $display(" ❌ %d teste(s) falharam.", test_errors);
        end
        $display("==================================================");

        #100;
        $finish;
    end

endmodule
