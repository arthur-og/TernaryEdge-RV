# Scientific Thesis & Motivation: Ternary Edge-RV

## 1. The Problem: The Extreme Edge Paradox
As Artificial Intelligence moves towards the "Extreme Edge" (e.g., nano-drones, remote agricultural sensors, wearable medical devices), systems face a fundamental paradox:
1. **The Need for Intelligence:** Devices must perform complex tasks like computer vision or anomaly detection locally, which traditionally requires power-hungry Multiply-Accumulate (MAC) units.
2. **The Need for Abstraction & Connectivity:** These devices cannot exist in a vacuum. They require a General-Purpose Processor (GPP) and a full Operating System (like Linux) to handle networking (Wi-Fi/Radio), file systems (SD Cards), and flight/system controllers.

Running both the OS and the AI inference on a general-purpose processor (like an RV32IMA) completely drains the tight energy budget. Conversely, building a purely bare-metal hardware accelerator makes the system commercially unviable and impossible to integrate with modern high-level software stacks.

## 2. The Solution: Hardware-Software Co-Design
**Ternary Edge-RV** proposes a symbiotic Co-Design approach that bridges the gap between extreme hardware efficiency and high-level software abstraction. 

Our architecture divides the workload strictly based on computational efficiency:
* **The Manager (RV32IMA + Linux):** The RISC-V core is intentionally kept small and lightweight. Its sole purpose is to run the OS, handle high-level applications (User-Space POSIX), and manage peripherals. It *does not* compute the Neural Network.
* **The Heavy Lifter (Multiplierless Ternary NPU):** AI inference is completely offloaded to a custom RTL accelerator. By quantizing the neural network to ternary values (-1, 0, 1), we entirely eliminate the need for DSP (Digital Signal Processor) blocks on the FPGA. The NPU relies exclusively on adders, subtractors, and multiplexers, drastically reducing dynamic power consumption and silicon area.

## 3. The Golden Bridge: Defeating the "OS Overhead"
The common critique of attaching minimal accelerators to Linux is the "OS Overhead" (context switching, MMIO latency, and CPU polling). If the RV32IMA has to constantly poll the NPU to check if inference is done, the CPU remains active, destroying the energy savings achieved by the NPU.

**Our Architectural Guarantee:**
The Ternary Edge-RV stack relies on a strictly **Interrupt-Driven (IRQ) Kernel Driver**. 
When the User-Space application requests an inference:
1. The CPU copies the data to the NPU via MMIO and triggers the start signal.
2. The CPU immediately goes to sleep (`wait_event_interruptible`), yielding cycles to other critical OS tasks (like drone flight control or networking).
3. The Ternary NPU computes the data autonomously.
4. Upon completion, the NPU fires a hardware interrupt (IRQ), waking the CPU exactly when the results are ready.

## 4. Formal Hypothesis
> *"Sistemas autônomos de extremo baixo consumo exigem inteligência embarcada aliada à abstração de sistemas operacionais. Historicamente, executar IA sob um OS (como Linux) em processadores de propósito geral consome rapidamente o orçamento energético. Esta pesquisa propõe o 'Ternary Edge-RV': um offload total da computação neural para uma NPU Ternária 'Multiplierless' (Zero DSPs), orquestrada por um RISC-V (RV32IMA) executando Linux. Demonstramos que, através de um driver de kernel baseado em interrupções (IRQ-driven), o processador pode gerenciar o sistema e abstrair o hardware (POSIX) enquanto a NPU resolve a IA na casa dos miliwatts. O resultado prova a viabilidade de aliar a eficiência energética do silício minimalista à escalabilidade do software open-source."*