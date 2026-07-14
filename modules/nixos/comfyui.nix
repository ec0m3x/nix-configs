{
  inputs,
  pkgs,
  ...
}: {
  # ComfyUI - AI image generation with node-based interface
  # https://github.com/utensils/comfyui-nix
  imports = [ inputs.comfyui-nix.nixosModules.default ];

  # Apply the overlay so pkgs.comfy-ui-cuda is available
  # Also disable flaky portalocker tests that timeout in Nix builds
  nixpkgs.overlays = [
    inputs.comfyui-nix.overlays.default
    (final: prev: {
      python312Packages = prev.python312Packages.overrideScope (pyFinal: pyPrev: {
        portalocker = pyPrev.portalocker.overridePythonAttrs (old: {
          doCheck = false;
          doInstallCheck = false;
        });
      });
    })
  ];

  services.comfyui = {
    enable = true;
    gpuSupport = "cuda";
    enableManager = true;
    port = 8188;
    listenAddress = "127.0.0.1";
    dataDir = "/var/lib/comfyui";
    openFirewall = false;
  };
}
