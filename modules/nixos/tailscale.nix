{ pkgs, config, ... }:
{
  services.tailscale = {
    enable = true;
    package = pkgs.unstable.tailscale;
    useRoutingFeatures = "both";
    openFirewall = true;
  };
  networking.firewall.trustedInterfaces = [ "tailscale0" ];
}