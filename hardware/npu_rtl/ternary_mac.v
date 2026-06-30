`timescale 1ns / 1ps

/*
 * Ternary MAC (Multiply-Accumulate) sem multiplicadores
 * Projeto: Ternary Edge-RV
 * Autor: Arthur Oliveira Gomes
 * 
 * Descrição:
 * Este módulo implementa a matemática central da rede neural ternária.
 * Em vez de usar blocos DSP caros para multiplicar, usamos as propriedades
 * dos pesos ternários (-1, 0, +1) para realizar apenas somas e subtrações,
 * usando Muxes lógicos (economizando energia e área de silício).
 */

module ternary_mac #(
    parameter ACT_WIDTH = 8,  // Ativações em 8-bits (INT8)
    parameter ACC_WIDTH = 32  // Acumulador em 32-bits para evitar overflow
)(
    input  wire                       clk,
    input  wire                       rst,
    input  wire                       en,       // Habilita a operação no ciclo
    input  wire                       clear,    // Zera o acumulador (nova inferência)
    input  wire signed [ACT_WIDTH-1:0] act_in,  // Valor de ativação de entrada
    input  wire        [1:0]           weight,  // Peso Ternário: 00=0, 01=+1, 11=-1
    output reg  signed [ACC_WIDTH-1:0] acc_out  // Resultado acumulado
);

    // Sinal intermediário para o resultado do "produto" (sem multiplicar)
    // Usamos ACT_WIDTH+1 para evitar erro de sinal no complemento de 2
    wire signed [ACT_WIDTH:0] pseudo_prod;

    // -------------------------------------------------------------------------
    // Lógica MULTIPLIERLESS (Sem Multiplicadores)
    // -------------------------------------------------------------------------
    // O mux escolhe se passa o valor, o valor negativo, ou zero,
    // com base apenas nos bits de peso.
    assign pseudo_prod = (weight == 2'b01) ?  act_in :          // Peso +1
                         (weight == 2'b11) ? -act_in :          // Peso -1 (Complemento de 2 sintético)
                         0;                                     // Peso  0 (Sparsity)

    // Acumulador
    always @(posedge clk) begin
        if (rst || clear) begin
            acc_out <= 0;
        end else if (en) begin
            acc_out <= acc_out + pseudo_prod;
        end
    end

endmodule
