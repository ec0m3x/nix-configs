{ ... }:
{
  boot = {
    loader = {
        systemd-boot.enable = true;
        systemd-boot.configurationLimit = 5;
        efi.canTouchEfiVariables = true;
    };
    initrd.systemd.enable = true;
    initrd.kernelModules = [ "tpm_crb" ];
    kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
    };
  };
}