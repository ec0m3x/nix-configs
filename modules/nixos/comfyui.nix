{
  inputs,
  pkgs,
  ...
}: {
  # ComfyUI - AI image generation with node-based interface
  # https://github.com/utensils/comfyui-nix
  imports = [ inputs.comfyui-nix.nixosModules.default ];

  # Apply the overlay so pkgs.comfy-ui-cuda is available
  nixpkgs.overlays = [ inputs.comfyui-nix.overlays.default ];

  services.comfyui = {
    enable = true;
    gpuSupport = "cuda";
    enableManager = true;
    port = 8188;
    listenAddress = "0.0.0.0";
    dataDir = "/var/lib/comfyui";
    openFirewall = true;
  };

  systemd.services.comfyui.environment.LD_LIBRARY_PATH =
    "${pkgs.cudaPackages_12_8.cuda_nvrtc.lib}/lib";
}
