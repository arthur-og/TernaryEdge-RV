/*
 * demo_npu.cpp — Demo Completo da NPU Ternária
 * Ternary Edge-RV Project
 *
 * Compile: g++ -o demo_npu demo_npu.cpp npu_sim.cpp -std=c++11
 * Run:     ./demo_npu
 *
 * Este programa demonstra a NPU funcionando com:
 *   1. Teste com pesos positivos (+1)
 *   2. Teste com pesos negativos (-1)
 *   3. Teste com pesos zero (sparsity)
 *   4. Teste combinado (+1, -1, 0)
 *   5. Simulação de inferência MNIST (cálculo de 1 neurônio)
 *   6. Verificação contra modelo matemático (golden)
 */

#include "npu_sim.h"
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <cassert>

// =============================================================================
// Golden Model (Python-equivalent reference)
// =============================================================================
int32_t golden_mac(const uint8_t* activations, const uint8_t* weights_2bit, int count) {
    int32_t acc = 0;
    for (int i = 0; i < count; i++) {
        int8_t act = static_cast<int8_t>(activations[i]);
        int32_t prod;
        switch (weights_2bit[i] & 0x03) {
            case 0b01: prod = act;               break;  // +1
            case 0b11: prod = -act;              break;  // -1
            default:   prod = 0;                         //  0
        }
        acc += prod;
    }
    return acc;
}

// Pack 16 two-bit weights into a uint32_t (Little-Endian)
uint32_t pack_weights(const uint8_t w[16]) {
    uint32_t word = 0;
    for (int i = 0; i < 16; i++) {
        word |= (uint32_t)(w[i] & 0x03) << (i * 2);
    }
    return word;
}

// =============================================================================
// Test Framework
// =============================================================================
int tests_passed = 0;
int tests_failed = 0;

#define TEST(name, condition) do { \
    printf("  %-45s ", name); \
    if (condition) { printf("✓ PASS\n"); tests_passed++; } \
    else { printf("✗ FAIL\n"); tests_failed++; } \
} while(0)

void run_test_1_positive_weights() {
    printf("\n[TEST 1] Pesos Positivos (+1)\n");

    uint8_t acts[8] = { 10, 20, 30, 40, 50, 60, 70, 80 };
    uint8_t w[16]   = { 0b01, 0b01, 0b01, 0b01, 0b01, 0b01, 0b01, 0b01,
                        0b00, 0b00, 0b00, 0b00, 0b00, 0b00, 0b00, 0b00 };
    uint32_t packed = pack_weights(w);

    int32_t golden = golden_mac(acts, w, 8);
    // golden = 10+20+30+40+50+60+70+80 = 360

    NPUSim npu;
    npu.load_activations(acts, 8);
    npu.load_weights(&packed, 1);
    npu.set_data_size(8);
    npu.start_inference();
    npu.wait_for_irq();

    int32_t result = static_cast<int32_t>(npu.get_result());
    TEST("Resultado (+1 weights)", result == golden);
    TEST("IRQ gerado", npu.irq_received());
    printf("    Esperado: %d, Obtido: %d\n", golden, result);
}

void run_test_2_negative_weights() {
    printf("\n[TEST 2] Pesos Negativos (-1)\n");

    uint8_t acts[4] = { 100, 50, 25, 10 };
    uint8_t w[16]   = { 0b11, 0b11, 0b11, 0b11,
                        0b00, 0b00, 0b00, 0b00,
                        0b00, 0b00, 0b00, 0b00,
                        0b00, 0b00, 0b00, 0b00 };
    uint32_t packed = pack_weights(w);

    int32_t golden = golden_mac(acts, w, 4);
    // golden = (-100)+(-50)+(-25)+(-10) = -185

    NPUSim npu;
    npu.load_activations(acts, 4);
    npu.load_weights(&packed, 1);
    npu.set_data_size(4);
    npu.start_inference();
    npu.wait_for_irq();

    int32_t result = static_cast<int32_t>(npu.get_result());
    TEST("Resultado (-1 weights)", result == golden);
    printf("    Esperado: %d, Obtido: %d\n", golden, result);
}

void run_test_3_sparsity() {
    printf("\n[TEST 3] Sparsity (Pesos Zero)\n");

    uint8_t acts[10] = { 10, 20, 30, 40, 50, 60, 70, 80, 90, 100 };

    uint32_t packed = 0;  // All 16 weights = zero = 0x00000000
    int32_t golden = 0;   // All MACs skipped

    NPUSim npu;
    npu.load_activations(acts, 10);
    npu.load_weights(&packed, 1);
    npu.set_data_size(10);
    npu.start_inference();
    npu.wait_for_irq();

    int32_t result = static_cast<int32_t>(npu.get_result());
    TEST("Resultado (all zero weights)", result == golden);
    TEST("Zero-skipped count", npu.get_zero_skipped() == 10);
    printf("    Esperado: %d, Obtido: %d, Zeros pulados: %d\n",
           golden, result, npu.get_zero_skipped());
}

void run_test_4_mixed_weights() {
    printf("\n[TEST 4] Pesos Mistos (+1, 0, -1)\n");

    uint8_t acts[8] = { 15, 25, 35, 45, 55, 65, 75, 85 };
    uint8_t w[16]   = { 0b01, 0b11, 0b00, 0b01,   // +1, -1, 0, +1
                        0b11, 0b00, 0b01, 0b11,   // -1, 0, +1, -1
                        0b00, 0b00, 0b00, 0b00,
                        0b00, 0b00, 0b00, 0b00 };
    uint32_t packed = pack_weights(w);

    int32_t golden = golden_mac(acts, w, 8);
    // golden = 15 + (-25) + 0 + 45 + (-55) + 0 + 75 + (-85) = -30

    NPUSim npu;
    npu.load_activations(acts, 8);
    npu.load_weights(&packed, 1);
    npu.set_data_size(8);
    npu.start_inference();
    npu.wait_for_irq();

    int32_t result = static_cast<int32_t>(npu.get_result());
    TEST("Resultado (mixed weights)", result == golden);
    printf("    Esperado: %d, Obtido: %d\n", golden, result);
}

void run_test_5_mnist_neuron_simulation() {
    printf("\n[TEST 5] Simulação de 1 Neurônio MNIST\n");

    // Simula o cálculo de 1 neurônio da primeira camada:
    // 784 pixels (INT8, normalizados 0-127)
    // 784 pesos ternários: 80% zeros (sparsity), 10% +1, 10% -1
    
    const int NUM_PIXELS = 784;
    uint8_t activations[NUM_PIXELS];
    uint8_t weights[NUM_PIXELS];

    // Gera dados de teste (simulando uma imagem MNIST real)
    for (int i = 0; i < NUM_PIXELS; i++) {
        activations[i] = static_cast<uint8_t>(rand() % 128);
        // 80% zeros, 10% +1, 10% -1 (simulando sparsity L1)
        int r = rand() % 100;
        if (r < 10)      weights[i] = 0b01;   // +1
        else if (r < 20) weights[i] = 0b11;   // -1
        else              weights[i] = 0b00;   // 0
    }

    // Golden model (Python reference)
    int32_t golden = golden_mac(activations, weights, NUM_PIXELS);

    // Pack weights into 32-bit words (49 words = 784/16)
    uint32_t packed_words[49];
    for (int i = 0; i < 49; i++) {
        uint8_t chunk[16];
        memcpy(chunk, &weights[i * 16], 16);
        packed_words[i] = pack_weights(chunk);
    }

    // NPU simulation
    NPUSim npu;
    npu.load_activations(activations, NUM_PIXELS);
    npu.load_weights(packed_words, 49);
    npu.set_data_size(NUM_PIXELS);
    npu.start_inference();
    npu.wait_for_irq(4000);  // 784 MACs × ~3 ciclos/MAC ≈ 2355 ciclos

    int32_t result = static_cast<int32_t>(npu.get_result());
    TEST("Resultado MNIST (784 MACs)", result == golden);
    TEST("IRQ gerado", npu.irq_received());

    int zero_pct = npu.get_zero_skipped() * 100 / NUM_PIXELS;
    printf("    Esperado: %d, Obtido: %d\n", golden, result);
    printf("    MACs totais: %d, Zeros pulados: %d (%d%% sparsity)\n",
           NUM_PIXELS, npu.get_zero_skipped(), zero_pct);
}

// =============================================================================
// Main
// =============================================================================
int main() {
    printf("╔══════════════════════════════════════════════════╗\n");
    printf("║   NPU Ternária — DEMONSTRAÇÃO DE ARQUITETURA    ║\n");
    printf("║   Ternary Edge-RV Project                       ║\n");
    printf("║   Zero DSPs. Apenas Muxes e Somadores.          ║\n");
    printf("╚══════════════════════════════════════════════════╝\n");

    // Run all tests
    run_test_1_positive_weights();
    run_test_2_negative_weights();
    run_test_3_sparsity();
    run_test_4_mixed_weights();
    run_test_5_mnist_neuron_simulation();

    // Summary
    printf("\n══════════════════════════════════════════════════\n");
    printf("  ✅ PASS: %d   ❌ FAIL: %d   Total: %d\n",
           tests_passed, tests_failed, tests_passed + tests_failed);
    printf("══════════════════════════════════════════════════\n");

    // Detailed output
    printf("\n--- Demonstração do Datapath Multiplierless ---\n");
    printf("A operação MAC foi realizada SEM multiplicadores.\n");
    printf("O peso ternário (-1, 0, +1) controla um MUX que:\n");
    printf("  +1: passa a ativação direto para o somador\n");
    printf("  -1: inverte o sinal (complemento de 2)\n");
    printf("   0: pula a operação (sparsity = economia de energia)\n");
    printf("\nResultado: ZERO blocos DSP utilizados na FPGA!\n");

    return (tests_failed > 0) ? 1 : 0;
}
