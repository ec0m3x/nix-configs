{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "ahci" "usb_storage" "usbhid" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" =
    { device = "/dev/mapper/luks-41e9aa50-bb26-4764-a529-a8825862b757";
      fsType = "ext4";
    };

  boot.initrd.luks.devices."luks-41e9aa50-bb26-4764-a529-a8825862b757" = {
    device = "/dev/disk/by-uuid/41e9aa50-bb26-4764-a529-a8825862b757";
    crypttabExtraOpts = [ "tpm2-device-auto" ];
  };

  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/407C-F411";
      fsType = "vfat";
      options = [ "fmask=0077" "dmask=0077" ];
    };

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}