{ config, lib, pkgs, ... }:

let
  cfg = config.services.ternaryedge;
in
{
  options.services.ternaryedge = {
    enable = lib.mkEnableOption "Ternary Edge-RV FPGA USB access";

    user = lib.mkOption {
      type = lib.types.str;
      default = "arthur";
      description = "Local user allowed to access the Urbana FTDI programmer.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups.plugdev = { };
    users.users.${cfg.user}.extraGroups = [ "dialout" "plugdev" ];

    boot.kernelModules = [ "ftdi_sio" "usbserial" ];

    environment.systemPackages = [ pkgs.usbutils ];

    services.udev.extraRules = ''
      # RealDigital Urbana uses the FTDI FT2232H USB interface.
      SUBSYSTEM=="usb", ATTR{idVendor}=="0403", ATTR{idProduct}=="6010", MODE="0666", GROUP="dialout", TAG+="uaccess"
      SUBSYSTEM=="usb", ATTR{idVendor}=="0403", ATTR{idProduct}=="6011", MODE="0666", GROUP="dialout", TAG+="uaccess"
      KERNEL=="ttyUSB[0-9]*", MODE="0666", GROUP="dialout"
    '';
  };
}
