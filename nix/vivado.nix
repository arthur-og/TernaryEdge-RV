# nix/vivado.nix — Declarative wrapper for the proprietary Xilinx Vivado
# toolchain on NixOS.
#
# Vivado is a ~50 GB proprietary binary that cannot live in the Nix store
# (licensing + size).  It ships a `settings64.sh` script that assumes a
# standard FHS layout (`/lib64/ld-linux-x86-64.so.2`, `/usr/bin`, ...), which
# NixOS does not provide by default.  We solve both problems with one
# `buildFHSEnv` wrapper:
#
#   1. The FHS bubble provides the directory layout Vivado expects.
#   2. Inside the bubble we `source $VIVADO_PATH/settings64.sh`, which sets
#      `XILINX_VIVADO`, `PATH`, `LD_LIBRARY_PATH`, and every other variable
#      Vivado needs — then `exec "$@"`.
#
# LiteX (litex/build/xilinx/vivado.py) discovers Vivado through one of:
#   a) `which("vivado")` succeeds  →  vivado on PATH
#   b) `$LITEX_ENV_VIVADO` set     →  LiteX sources `settings64.sh` itself
#
# The wrapper below makes (a) work inside the FHS. The devShell deliberately
# leaves `LITEX_ENV_VIVADO` unset so LiteX does not source host settings outside
# the FHS wrapper.
#
# Usage from the project flake:
#
#   vivado-nix = import ./nix/vivado.nix { inherit pkgs lib; };
#   devShells.vivado = pkgs.mkShell {
#     packages = vivado-nix.mkVivadoToolchain {};
#     # ...
#   };
#
# If your Vivado is installed somewhere other than the defaults, set
# `VIVADO_HOME` when entering the shell.
{ pkgs, lib }:

let
  # ---------------------------------------------------------------------------
  # Deterministic Vivado install candidates.  These are checked only by the
  # runtime wrapper, never during Nix evaluation.
  #
  # AMD/Xilinx moved the install prefix from /opt/Xilinx to /opt/amd in
  # recent releases.  The first candidate containing settings64.sh wins.  If
  # none exists yet, the first candidate is retained for a deterministic
  # runtime error message.
  # ---------------------------------------------------------------------------
  candidatePaths = [
    "/opt/Xilinx/2026.1/Vivado"
    "/opt/amd/2026.1/Vivado"
    "/opt/Xilinx/Vivado/2026.1"
    "/opt/amd/Vivado/2026.1"
    "/opt/Xilinx/Vivado/2024.2"
    "/opt/amd/Vivado/2024.2"
    "/opt/Xilinx/Vivado/2024.1"
    "/opt/amd/Vivado/2024.1"
    "/opt/Xilinx/Vivado/2023.2"
    "/opt/amd/Vivado/2023.2"
  ];

  defaultVivadoPath = builtins.head candidatePaths;

  vivadoPathResolution = ''
    if [ -n "''${VIVADO_HOME:-}" ]; then
      vivado_home="$VIVADO_HOME"
    else
      vivado_home=""
      for candidate in ${lib.concatStringsSep " " (map lib.escapeShellArg candidatePaths)}; do
        if [ -f "$candidate/settings64.sh" ]; then
          vivado_home="$candidate"
          break
        fi
      done
    fi
    vivado_home="''${vivado_home:-${defaultVivadoPath}}"
  '';

  # ---------------------------------------------------------------------------
  # buildFHSEnv — the FHS bubble that makes Vivado's settings64.sh work.
  #
  # `targetPkgs` provides the shared libraries Vivado links against but does
  # not ship (or ships versions incompatible with NixOS).  `extraBuildCommands`
  # bind-mounts /opt/Xilinx and /opt/amd from the host so the FHS can see the
  # proprietary install.
  # ---------------------------------------------------------------------------
  vivadoFhs = pkgs.buildFHSEnv {
    name = "vivado-fhs";
    targetPkgs = pkgs: with pkgs; [
      bash
      libusb1
      ncurses                # Vivado 2026.1 also loads libtinfo.so.6
      ncurses5              # Vivado links against libtinfo.so.5
      zlib
      stdenv.cc.cc.lib      # libstdc++.so
      expat
      fontconfig
      freetype
      libuuid
      glib
      dbus
      libpng
      pixman
      libx11                # GUI (Vivado IDE)
      libxext
      libxrender
      libICE
      libSM
      libxcb
      libXtst
      libXi
    ];
    multiPkgs = pkgs: with pkgs; [
      zlib
    ];

    extraBuildCommands = ''
      ln -s /opt/Xilinx $out/opt/Xilinx 2>/dev/null || true
      ln -s /opt/amd   $out/opt/amd   2>/dev/null || true
    '';

    # The entry point runs inside the FHS bubble, sources Vivado's environment,
    # and then executes the requested command.
    runScript = ''
      #!${pkgs.bash}/bin/bash
      set -e

      ${vivadoPathResolution}
      export VIVADO_HOME="$vivado_home"

      if [ ! -f "$VIVADO_HOME/settings64.sh" ]; then
        echo "vivado-fhs: Vivado not found at $VIVADO_HOME" >&2
        echo "" >&2
        echo "  Install AMD Vivado Design Suite 2026.1 and ensure" >&2
        echo "  settings64.sh exists at the path above." >&2
        echo "" >&2
        echo "  If Vivado is installed elsewhere, run:" >&2
        echo "    VIVADO_HOME=/your/path nix develop .#vivado" >&2
        exit 1
      fi

      # Source Vivado's own environment script.
      source "$VIVADO_HOME/settings64.sh"

      # Vivado's loader replaces LD_LIBRARY_PATH with its private libraries.
      # Keep the FHS system directories in the inherited path so Tcl extensions
      # can resolve both the ncurses ABI 5 and ABI 6 compatibility libraries.
      export LD_LIBRARY_PATH="/lib64:/lib:/usr/lib64:/usr/lib:''${LD_LIBRARY_PATH:-}"

      exec "$@"
    '';
  };

  # ---------------------------------------------------------------------------
  # Thin PATH wrappers — each puts one Vivado binary on `$PATH` by delegating
  # to the FHS bubble.  LiteX needs `vivado`; the other tools are useful for
  # flashing, simulation, and loading the certificate license through `vlm`.
  # ---------------------------------------------------------------------------
  vivadoTools = [ "vivado" "bootgen" "xsdb" "vivado_hsm" "vlm" ];

  vivadoWrappers = builtins.map (tool:
    pkgs.writeShellScriptBin tool ''
      exec ${vivadoFhs}/bin/vivado-fhs ${tool} "$@"
    ''
  ) vivadoTools;

  # ---------------------------------------------------------------------------
  # mkVivadoToolchain — returns a list of derivations for `packages = [...]`
  # in a devShell.  Call it with `{ }` for defaults, or override the path via
  # the `VIVADO_HOME` env var at `nix develop` time (handled in runScript).
  # ---------------------------------------------------------------------------
  mkVivadoToolchain = { }: vivadoWrappers ++ [ vivadoFhs ];

in
{
  inherit mkVivadoToolchain vivadoFhs vivadoWrappers defaultVivadoPath
    candidatePaths vivadoPathResolution;
}
