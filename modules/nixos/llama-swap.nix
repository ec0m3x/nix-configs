{pkgs, ...}: let
  configFile = (pkgs.formats.yaml {}).generate "llama-swap-config.yaml" {
    healthCheckTimeout = 300;
    logLevel = "info";
    startPort = 10001;
    globalTTL = 0;

    macros = {
      models_dir = "/models";
    };

    aliases = {
      ornith = "ornith-1.0-9b";
    };

    models = {
      "glm-4.7-flash" = {
        cmd = ''
          /usr/local/bin/llama-server
          -m ''${models_dir}/GLM-4.7-Flash-REAP-23B-A3B-UD-Q4_K_XL.gguf
          --host 0.0.0.0
          --port ''${PORT}
          --fit on
          --no-mmap
          --mlock
          -c 65536
          --parallel 1
          --flash-attn auto
          --cache-type-k q8_0
          --cache-type-v q8_0
          --alias glm-4.7-flash
        '';
        checkEndpoint = "/health";
        ttl = 120;
        name = "GLM-4.7-Flash";
        description = "GLM-4.7-Flash-REAP-23B-A3B-UD-Q4_K_XL, via unified llama-swap Container (CUDA)";
        capabilities = {
          "in" = ["text"];
          out = ["text"];
          tools = true;
          context = 65536;
        };
      };

      "qwen-3.6-27b" = {
        cmd = ''
          /usr/local/bin/llama-server
          -m ''${models_dir}/Qwen3.6-27B-UD-Q4_K_XL.gguf
          --host 0.0.0.0
          --port ''${PORT}
          --fit on
          --no-mmap
          --mlock
          --jinja
          --reasoning-format auto
          --reasoning on
          -c 131072
          --parallel 1
          --flash-attn auto
          --cache-type-k q8_0
          --cache-type-v q8_0
          --alias qwen-3.6-27b
        '';
        checkEndpoint = "/health";
        ttl = 300;
        name = "Qwen 3.6 27B";
        description = "Qwen3.6-27B-UD-Q4_K_XL, via unified llama-swap Container (CUDA)";
        capabilities = {
          "in" = ["text"];
          out = ["text"];
          tools = true;
          context = 131072;
        };
      };

      "ornith-1.0-9b" = {
        cmd = ''
          /usr/local/bin/llama-server
          -m ''${models_dir}/ornith-1.0-9b-Q8_0.gguf
          --host 0.0.0.0
          --port ''${PORT}
          --fit on
          --no-mmap
          --mlock
          -c 32768
          --parallel 4
          --flash-attn auto
          --cache-type-k q8_0
          --cache-type-v q8_0
          --alias ornith-1.0-9b
        '';
        checkEndpoint = "/health";
        ttl = 300;
        name = "Ornith 1.0 9B";
        description = "ornith-1.0-9b-Q8_0, via unified llama-swap Container (CUDA)";
        capabilities = {
          "in" = ["text"];
          out = ["text"];
          tools = true;
          context = 32768;
        };
      };
    };
  };
in {
  systemd.tmpfiles.rules = [
    "d /data/llama-cpp 0775 root users -"
  ];

  virtualisation.oci-containers = {
    backend = "docker";
    containers.llama-swap = {
      image = "ghcr.io/mostlygeek/llama-swap:unified-cuda";
      ports = ["9292:8080"];
      volumes = [
        "/data/llama-cpp:/models"
        "${configFile}:/etc/llama-swap/config/config.yaml:ro"
      ];
      extraOptions = ["--device=nvidia.com/gpu=all"];
    };
  };
}
