# Plano de Trabalho — Gildo Alves de Lima Junior
**Papel no Projeto:** OS Infrastructure (Buildroot, Kernel Configuration, Device Tree, Testbenches)
**Última atualização:** 10/06/2026

---

## Marcos do Projeto

| Marco | Previsão | Status |
|:------|:---------|:-------|
| M1 — Buildroot + QEMU boot funcional (RV32IMA) | Concluído | ✅ |
| M2 — Toolchain exportada via SDK (cada um compila a sua) | Concluído | ✅ |
| M3 — Device Tree (.dts) com node da NPU v2 finalizada | 2 semanas | ⏳ |
| M4 — RootFS com suporte a armazenamento + deploy físico | Após M3 + 1 sem | ⏳ |
| M5 — Seção "OS Infrastructure" do Paper 1 escrita | Antes do prazo final | ⏳ |

---

## Fase 1 (Concluída): Configuração do Ambiente e Boot em Emulação

- ✅ Buildroot configurado (external tree em `software/os_buildroot/`)
- ✅ defconfig ternária (RV32IMA, linux) criada
- ✅ Boot funcional no QEMU (OpenSBI + U-Boot + Kernel + RootFS)
- ✅ HIGH_RES_TIMERS habilitado no kernel

## Fase 2 (Concluída): Geração da Toolchain

- ✅ `make sdk` funcional — cada membro compila sua toolchain localmente
- ✅ README.md em `software/os_buildroot/` com instruções
- ✅ Nenhuma dependência de Google Drive para distribuir toolchain

## Fase 3 (Em Andamento): Device Tree e Testbench

### 3.1 — Device Tree (.dts) para NPU v2

O node da NPU deve usar o mapa de memória revisado (architecture_contract.md v2):

```dts
npu_ternaria: npu@40000000 {
    compatible = "ternaryedge,npu-ternaria";
    reg = <0x40000000 0x00001000>;
    interrupts = <0x0a>;
    interrupt-parent = <&plic>;
};
```

- **Compatível com driver existente:** Manter `compatible` igual ao usado no QEMU para não quebrar o driver que o Gustavo já escreveu.
- **Interrupt:** IRQ=10 conectado ao PLIC do VexRiscv.

### 3.2 — Testbench Verilator (Apoio ao Arthur)

Gildo auxiliará Arthur na escrita do testbench Verilator para a NPU v2:

- Configurar ambiente Verilator na máquina de Gildo
- Escrever módulo de RAM simulada (comportamental) para o DMA Master ler/escrever
- Validar que o protocolo Wishbone Master está correto (endereços, burst, handshake)
- Rodar simulação em paralelo com Arthur para acelerar a validação

### 3.3 — Atualização do RootFS

Confirmar que o RootFS atual inclui:
- Módulos de kernel carregáveis (LKM) — para o `npu_driver.ko`
- Binário do user_app estaticamente compilado
- Sistema de arquivos suportando leitura de imagens (FAT32/ext4)

## Fase 4 (Futura): Deploy Físico e Paper

- 【 】 Gravar imagem final do Linux em SD card
- 【 】 Bootar na FPGA e validar `dmesg`
- 【 】 Carregar driver NPU e executar inferência
- 【 】 Escrever seção **"OS Infrastructure"** do Paper 1: config de boot, Device Tree, integração Linux + NPU
