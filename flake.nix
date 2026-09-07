{
  description = "Ternary Edge-RV reproducible FPGA development environment (openXC7 + Vivado)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # LiteX is not packaged in the selected nixpkgs revision. Keep the source
    # in the flake so the Python import path is pinned by flake.lock.
    litex = {
      url = "github:enjoy-digital/litex";
      flake = false;
    };
    litex-boards = {
      url = "github:litex-hub/litex-boards";
      flake = false;
    };
    litedram = {
      url = "github:enjoy-digital/litedram";
      flake = false;
    };
    litespi = {
      url = "github:litex-hub/litespi";
      flake = false;
    };
    litesdcard = {
      url = "github:enjoy-digital/litesdcard";
      flake = false;
    };
    pythondata-cpu-vexriscv = {
      url = "github:litex-hub/pythondata-cpu-vexriscv";
      flake = false;
    };
    pythondata-software-picolibc = {
      url = "github:litex-hub/pythondata-software-picolibc";
      flake = false;
    };
    pythondata-software-compiler_rt = {
      url = "github:litex-hub/pythondata-software-compiler_rt";
      flake = false;
    };

    # Provides the Python fasm sources and the xc7frames2bit C++ tool.
    prjxray = {
      url = "git+https://github.com/f4pga/prjxray?submodules=1";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, litex, litex-boards, litedram, litespi, litesdcard
    , pythondata-cpu-vexriscv, pythondata-software-picolibc
    , pythondata-software-compiler_rt, prjxray }:
    let
      systems = [ "x86_64-linux" ];
      forEachSystem = function:
        nixpkgs.lib.genAttrs systems (system:
          function (import nixpkgs { inherit system; }));
    in {
      packages = forEachSystem (pkgs:
        let
          prjxray-tools = pkgs.stdenv.mkDerivation {
            pname = "prjxray-tools";
            version = "git";
            src = prjxray;

            nativeBuildInputs = [ pkgs.cmake pkgs.gnumake ];

            postPatch = ''
              substituteInPlace lib/include/prjxray/memory_mapped_file.h \
                --replace-fail '#include <absl/types/span.h>' \
                $'#include <absl/types/span.h>\n#include <cstdint>'
            '';

            configurePhase = "cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5";
            buildPhase = "cmake --build build --target xc7frames2bit -j$NIX_BUILD_CORES";
            installPhase = ''
              install -Dm755 build/tools/xc7frames2bit $out/bin/xc7frames2bit
            '';
          };
        in {
          default = prjxray-tools;
          inherit prjxray-tools;
        });

      devShells = forEachSystem (pkgs:
        let
          pythonHardware = pkgs.python312.withPackages (ps: with ps; [
            migen
            numpy
            packaging
            pyyaml
            requests
          ]);
          pythonAi = pkgs.python311.withPackages (ps: [ ps.pip ]);
          riscvBareMetal = pkgs.pkgsCross.riscv32-embedded.stdenv.cc;

          prjxray-tools = self.packages.${pkgs.system}.prjxray-tools;

          # ---------------------------------------------------------------------------
          # Vivado toolchain (proprietary, FHS-wrapped).
          #   nix develop .#vivado
          #   python3 base_soc.py --build --toolchain vivado
          #
          # The wrapper sources Vivado's settings64.sh inside a buildFHSEnv
          # bubble, so the proprietary binaries see the FHS layout they
          # expect. The devShell keeps LITEX_ENV_VIVADO unset so LiteX calls
          # the wrapper from PATH instead of sourcing host settings directly.
          # ---------------------------------------------------------------------------
          vivado-nix = import ./nix/vivado.nix { inherit pkgs; lib = pkgs.lib; };
          vivadoToolchain = vivado-nix.mkVivadoToolchain { };

          setupOpenxc7 = pkgs.writeShellScriptBin "ternaryedge-setup-openxc7" ''
            set -euo pipefail

            root="''${TERNARYEDGE_ROOT:-$(pwd)}"
            state="$root/.ternaryedge/openxc7"
            venv="$state/venv"
            bin="$state/bin"

            mkdir -p "$state" "$bin"
            if [ ! -x "$venv/bin/python" ]; then
              ${pkgs.uv}/bin/uv venv --python ${pythonHardware}/bin/python3 "$venv"
            fi

            ${pkgs.uv}/bin/uv pip install --python "$venv/bin/python" \
              "fasm" "pyyaml" "simplejson" "intervaltree" \
              "progressbar2" "pyjson5" "numpy"

            cat > "$bin/fasm2frames" <<EOF
            #!/bin/sh
            PYTHONPATH="${prjxray}:\${PYTHONPATH:-}" \
              exec "$venv/bin/python" "${prjxray}/utils/fasm2frames.py" "\$@"
            EOF
            chmod +x "$bin/fasm2frames"

            echo "openXC7 Python tools installed in $venv"
            echo "fasm2frames wrapper: $bin/fasm2frames"
          '';

          setupAi = pkgs.writeShellScriptBin "ternaryedge-setup-ai" ''
            set -euo pipefail

            root="''${TERNARYEDGE_ROOT:-$(pwd)}"
            venv="$root/.ternaryedge/ai-venv"

            if [ ! -x "$venv/bin/python" ]; then
              ${pkgs.uv}/bin/uv venv --python ${pythonAi}/bin/python3 "$venv"
            fi

            ${pkgs.uv}/bin/uv pip install --python "$venv/bin/python" \
              "tensorflow>=2.17,<2.18" \
              "tf-keras>=2.17,<2.18" \
              "larq>=0.13,<0.14" \
              "numpy<2"

            echo "AI environment installed in $venv"
          '';

          checkLitexBoard = pkgs.writeShellScriptBin "ternaryedge-check-litex-board" ''
            set -euo pipefail
            root="''${TERNARYEDGE_ROOT:-$(pwd)}"
            board_root="$root/hardware/litex_soc/litex_boards"
            export PYTHONPATH="$root/hardware/litex_soc:''${PYTHONPATH:-}"
            TERNARYEDGE_BOARD_ROOT="$board_root" python3 - <<'PY'
            import importlib
            import os
            from pathlib import Path

            board_root = Path(os.environ["TERNARYEDGE_BOARD_ROOT"]).resolve()
            target = importlib.import_module("litex_boards.targets.realdigital_urbana")
            platform = importlib.import_module("litex_boards.platforms.realdigital_urbana")
            target_file = Path(target.__file__).resolve()
            platform_file = Path(platform.__file__).resolve()

            if not target_file.is_relative_to(board_root):
                raise SystemExit(f"target import escaped project board tree: {target_file}")
            if not platform_file.is_relative_to(board_root):
                raise SystemExit(f"platform import escaped project board tree: {platform_file}")
            if target.Platform is not platform.Platform:
                raise SystemExit("target/platform Platform wiring mismatch")

            urbana = platform.Platform(toolchain="vivado")
            if urbana.device != "xc7s50csga324-1":
                raise SystemExit(f"unexpected Urbana device: {urbana.device}")

            print(
                "LiteX Urbana provenance: "
                f"target={target_file} platform={platform_file} device={urbana.device}"
            )
            PY
          '';

          hostBuildPackages = with pkgs; [
            bc
            bison
            cpio
            file
            flex
            gcc
            git
            gnumake
            gnutar
            ncurses
            openssl
            patch
            perl
            rsync
            unzip
            wget
            which
            xz
            zstd
          ];

          commonHardwarePackages = with pkgs; [
            cmake
            fasm
            git
            gnumake
            gtkwave
            iverilog
            libusb1
            openfpgaloader
            picocom
            pythonHardware
            setupOpenxc7
            checkLitexBoard
            usbutils
            verilator
            yosys
            nextpnr-xilinx
            prjxray-tools
            riscvBareMetal
          ];

          hardwareShellHook = ''
            export TERNARYEDGE_ROOT="''${TERNARYEDGE_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
            export CHIPDB="''${CHIPDB:-$TERNARYEDGE_ROOT/.ternaryedge/openxc7/chipdb}"
            export PRJXRAY_DB_DIR="''${PRJXRAY_DB_DIR:-${pkgs.nextpnr-xilinx}/share/nextpnr/external/prjxray-db}"
            export NEXTPNR_XILINX_PYTHON_DIR="''${NEXTPNR_XILINX_PYTHON_DIR:-${pkgs.nextpnr-xilinx}/share/nextpnr/python}"
            export PYTHONPATH="${litex}:$TERNARYEDGE_ROOT/hardware/litex_soc:${litex-boards}:${litedram}:${litespi}:${litesdcard}:${pythondata-cpu-vexriscv}:${pythondata-software-picolibc}:${pythondata-software-compiler_rt}:''${PYTHONPATH:-}"
            export PATH="$TERNARYEDGE_ROOT/.ternaryedge/openxc7/bin:$PATH"

            if [ -x "$TERNARYEDGE_ROOT/.ternaryedge/openxc7/bin/fasm2frames" ]; then
              echo "openXC7 conversion tools: ready"
            else
              echo "Run ternaryedge-setup-openxc7 once to install fasm2frames."
            fi
            echo "CHIPDB=$CHIPDB"
            echo "PRJXRAY_DB_DIR=$PRJXRAY_DB_DIR"
          '';

          softwarePackages = with pkgs; hostBuildPackages ++ [
            dtc
            libelf
            python312
            qemu
            rsync
            util-linux
          ];

          # ---------------------------------------------------------------------------
          # Packages shared by the Vivado devShell — all LiteX/Migen/Python
          # deps from `commonHardwarePackages` but WITHOUT the openXC7-only
          # tools (yosys, nextpnr-xilinx, prjxray-tools, fasm, setupOpenxc7).
          # Vivado replaces them.
          # ---------------------------------------------------------------------------
          commonVivadoPackages = with pkgs; [
            cmake
            git
            gnumake
            gtkwave
            iverilog
            libusb1
            openfpgaloader
            picocom
            pythonHardware
            checkLitexBoard
            usbutils
            verilator
            riscvBareMetal
          ] ++ vivadoToolchain;
        in {
          hardware = pkgs.mkShell {
            packages = commonHardwarePackages;
            shellHook = hardwareShellHook;
          };

          software = pkgs.mkShell {
            packages = softwarePackages;
            shellHook = ''
              export TERNARYEDGE_ROOT="''${TERNARYEDGE_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
              export BUILDROOT_DIR="''${BUILDROOT_DIR:-$TERNARYEDGE_ROOT/../buildroot}"
              export BR2_EXTERNAL="$TERNARYEDGE_ROOT/software/os_buildroot"
              echo "BUILDROOT_DIR=$BUILDROOT_DIR"
              echo "BR2_EXTERNAL=$BR2_EXTERNAL"
            '';
          };

          ai = pkgs.mkShell {
            packages = with pkgs; [
              git
              pythonAi
              setupAi
              uv
            ];
            shellHook = ''
              export TERNARYEDGE_ROOT="''${TERNARYEDGE_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
              export PATH="$TERNARYEDGE_ROOT/.ternaryedge/ai-venv/bin:$PATH"
              export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath [ pkgs.stdenv.cc.cc.lib pkgs.zlib ]}:''${LD_LIBRARY_PATH:-}"
              if [ -x "$TERNARYEDGE_ROOT/.ternaryedge/ai-venv/bin/python" ]; then
                echo "AI environment: ready"
              else
                echo "Run ternaryedge-setup-ai once to install TensorFlow 2.17 and Larq 0.13."
              fi
            '';
          };

          vivado = pkgs.mkShell {
            packages = commonVivadoPackages;
            shellHook = ''
              export TERNARYEDGE_ROOT="''${TERNARYEDGE_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
              export PYTHONPATH="${litex}:$TERNARYEDGE_ROOT/hardware/litex_soc:${litex-boards}:${litedram}:${litespi}:${litesdcard}:${pythondata-cpu-vexriscv}:${pythondata-software-picolibc}:${pythondata-software-compiler_rt}:''${PYTHONPATH:-}"

              # Do NOT export LITEX_ENV_VIVADO: LiteX uses it to generate
              # `source $LITEX_ENV_VIVADO/settings64.sh` in its build script,
              # which pollutes PATH with un-patched binaries outside the FHS.
              # Instead, LiteX will call `vivado` from PATH, which correctly
              # invokes our FHS wrapper.
              unset LITEX_ENV_VIVADO || true

              echo "=== Ternary Edge-RV — Vivado toolchain ==="
              ${vivado-nix.vivadoPathResolution}
              echo "  Vivado path: $vivado_home"
              echo "  Build: python3 base_soc.py --build --toolchain vivado"
              echo "  Clock target/default: 100 MHz (implementation reports pending)"
              echo ""

              if [ ! -f "$vivado_home/settings64.sh" ]; then
                echo "  WARNING: settings64.sh not found at $vivado_home" >&2
                echo "  Install AMD Vivado Design Suite 2026.1, then re-enter this shell." >&2
                echo "  If installed elsewhere: VIVADO_HOME=/your/path nix develop .#vivado" >&2
              fi
            '';
          };

          default = pkgs.mkShell {
            packages = commonHardwarePackages ++ softwarePackages;
            shellHook = hardwareShellHook + ''
              export BUILDROOT_DIR="''${BUILDROOT_DIR:-$TERNARYEDGE_ROOT/../buildroot}"
              export BR2_EXTERNAL="$TERNARYEDGE_ROOT/software/os_buildroot"
            '';
          };
        });
    };
}
