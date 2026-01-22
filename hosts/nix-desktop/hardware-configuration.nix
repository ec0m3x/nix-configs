{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "ahci" "usb_storage" "usbhid" "sd_mod" "tpm_tis" "tpm_crb"];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" =
    { device = "/dev/mapper/luks-9b52aee9-052c-4033-9a05-0ae564b01ea7";
      fsType = "ext4";
    };

  boot.initrd.luks.devices."luks-9b52aee9-052c-4033-9a05-0ae564b01ea7" = {
    device = "/dev/disk/by-uuid/9b52aee9-052c-4033-9a05-0ae564b01ea7";
    crypttabExtraOpts = [ "tpm2-device-auto" ];
  };

  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/3AE2-D58C";
      fsType = "vfat";
      options = [ "fmask=0077" "dmask=0077" ];
    };

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
