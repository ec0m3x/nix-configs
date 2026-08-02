{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.homelabGitOps;
  inherit (lib) mkEnableOption mkIf mkOption types;

  activationCommand = "/run/current-system/sw/bin/homelab-gitops-activate";
  activationPackage = pkgs.writeShellApplication {
    name = "homelab-gitops-activate";
    runtimeInputs = [
      config.nix.package
      pkgs.coreutils
    ];
    text = ''
      new_system="''${1-}"
      revision="''${2-}"

      if [[ $# -ne 2 ]]; then
        echo "usage: homelab-gitops-activate SYSTEM_PATH GIT_REVISION" >&2
        exit 2
      fi

      if [[ ! "$new_system" =~ ^/nix/store/[0-9a-df-np-sv-z]{32}-nixos-system-${config.networking.hostName}-[^/]+$ ]]; then
        echo "refusing unexpected system path: $new_system" >&2
        exit 1
      fi
      if [[ ! "$revision" =~ ^[0-9a-f]{40}$ ]]; then
        echo "refusing invalid Git revision: $revision" >&2
        exit 1
      fi
      if [[ ! -x "$new_system/bin/switch-to-configuration" ]]; then
        echo "system closure is incomplete: $new_system" >&2
        exit 1
      fi

      old_system=$(readlink -f /nix/var/nix/profiles/system)
      nix-env --profile /nix/var/nix/profiles/system --set "$new_system"

      if ! "$new_system/bin/switch-to-configuration" switch; then
        echo "activation failed; restoring the previous system profile" >&2
        nix-env --profile /nix/var/nix/profiles/system --set "$old_system"
        "$old_system/bin/switch-to-configuration" switch || true
        exit 1
      fi

      install -d -m 0755 /var/lib/homelab-gitops-target
      printf '%s\n' "$revision" > /var/lib/homelab-gitops-target/revision
      chmod 0644 /var/lib/homelab-gitops-target/revision
      echo "activated $revision as $new_system"
    '';
  };

  remoteTargets = builtins.filter (target: !target.local) cfg.controller.targets;
  controllerPackage = pkgs.writeShellApplication {
    name = "homelab-gitops-controller";
    runtimeInputs = [
      config.nix.package
      pkgs.coreutils
      pkgs.curl
      pkgs.git
      pkgs.jq
      pkgs.openssh
      config.systemd.package
    ];
    text = ''
      readonly state_dir="''${STATE_DIRECTORY:?STATE_DIRECTORY is not set}"
      readonly checkout="$state_dir/checkout"
      readonly applied_revision_file="$state_dir/applied-revision"
      readonly repository=${lib.escapeShellArg cfg.controller.repository}
      readonly branch=${lib.escapeShellArg cfg.controller.branch}
      readonly workflow_api=${lib.escapeShellArg cfg.controller.workflowApi}
      readonly deploy_user=${lib.escapeShellArg cfg.controller.deployUser}
      readonly activation_command=${lib.escapeShellArg activationCommand}

      die() {
        echo "Error: $*" >&2
        exit 1
      }

      export GIT_TERMINAL_PROMPT=0
      readonly -a ssh_options=(
        -o BatchMode=yes
        -o ConnectTimeout=10
        -o StrictHostKeyChecking=yes
      )
      export NIX_SSHOPTS="''${ssh_options[*]}"

      if [[ ! -d "$checkout/.git" ]]; then
        git clone --no-checkout "$repository" "$checkout"
      fi

      git -C "$checkout" fetch --prune origin "+refs/heads/$branch:refs/remotes/origin/$branch"
      revision=$(git -C "$checkout" rev-parse "origin/$branch^{commit}")

      if [[ -s "$applied_revision_file" ]]; then
        applied_revision=$(<"$applied_revision_file")
        if [[ "$revision" == "$applied_revision" ]]; then
          echo "revision $revision is already deployed"
          exit 0
        fi
        git -C "$checkout" merge-base --is-ancestor "$applied_revision" "$revision" || \
          die "origin/$branch is not a fast-forward from deployed revision $applied_revision"
      fi

      workflow_result=$(curl --fail --silent --show-error --location \
        --header "Accept: application/vnd.github+json" \
        --header "X-GitHub-Api-Version: 2022-11-28" \
        "$workflow_api?branch=$branch&event=push&head_sha=$revision&per_page=1")
      run_count=$(jq -r '.total_count' <<<"$workflow_result")

      if [[ "$run_count" == "0" ]]; then
        echo "waiting for the GitHub check of $revision"
        exit 0
      fi

      workflow_status=$(jq -r '.workflow_runs[0].status' <<<"$workflow_result")
      workflow_conclusion=$(jq -r '.workflow_runs[0].conclusion // "pending"' <<<"$workflow_result")
      workflow_url=$(jq -r '.workflow_runs[0].html_url' <<<"$workflow_result")

      if [[ "$workflow_status" != "completed" ]]; then
        echo "GitHub check for $revision is $workflow_status; waiting ($workflow_url)"
        exit 0
      fi
      if [[ "$workflow_conclusion" != "success" ]]; then
        die "GitHub check for $revision concluded $workflow_conclusion ($workflow_url)"
      fi

      git -C "$checkout" checkout --detach "$revision"
      [[ -z $(git -C "$checkout" status --porcelain) ]] || die "managed checkout is dirty"

      echo "checking target connectivity and identity"
      ${lib.concatMapStringsSep "\n" (target: ''
          remote_host=$(ssh "''${ssh_options[@]}" "$deploy_user@${target.address}" hostname -s)
          [[ "$remote_host" == ${lib.escapeShellArg target.name} ]] || \
            die "${target.address} identified itself as '$remote_host', expected ${target.name}"
        '')
        remoteTargets}

      declare -A system_paths
      echo "building every configuration before the first activation"
      ${lib.concatMapStringsSep "\n" (target: ''
          echo "==> building ${target.name}"
          system_paths[${lib.escapeShellArg target.name}]=$(nix build \
            --no-link \
            --print-out-paths \
            "$checkout#nixosConfigurations.${target.name}.config.system.build.toplevel")
          [[ "''${system_paths[${target.name}]}" != *$'\n'* ]] || \
            die "build for ${target.name} returned more than one path"
        '')
        cfg.controller.targets}

      echo "all builds succeeded; starting staggered deployment"
      ${lib.concatMapStringsSep "\n" (target:
        if target.local
        then ''
          echo "==> activating ${target.name} locally"
          /run/wrappers/bin/sudo -n "$activation_command" "''${system_paths[${target.name}]}" "$revision"
          failed_units=$(systemctl --failed --no-legend --plain --no-pager)
          if [[ -n "$failed_units" ]]; then
            printf 'Failed units on ${target.name}:\n%s\n' "$failed_units" >&2
            die "deployment stopped after ${target.name}"
          fi
        ''
        else ''
          echo "==> copying and activating ${target.name} (${target.address})"
          nix copy --to "ssh-ng://$deploy_user@${target.address}" "''${system_paths[${target.name}]}"
          ssh "''${ssh_options[@]}" "$deploy_user@${target.address}" \
            sudo -n "$activation_command" "''${system_paths[${target.name}]}" "$revision"
          failed_units=$(ssh "''${ssh_options[@]}" "$deploy_user@${target.address}" \
            systemctl --failed --no-legend --plain --no-pager)
          if [[ -n "$failed_units" ]]; then
            printf 'Failed units on ${target.name}:\n%s\n' "$failed_units" >&2
            die "deployment stopped after ${target.name}"
          fi
        '')
      cfg.controller.targets}

      printf '%s\n' "$revision" > "$applied_revision_file"
      echo "successfully deployed $revision to every NixOS host"
    '';
  };
in {
  options.services.homelabGitOps = {
    target.enable = mkEnableOption "restricted GitOps activation on this host";

    controller = {
      enable = mkEnableOption "the homelab GitOps controller";

      repository = mkOption {
        type = types.str;
        default = "https://github.com/ec0m3x/nix-configs.git";
        description = "Public Git repository polled by the controller.";
      };

      branch = mkOption {
        type = types.str;
        default = "main";
        description = "Branch deployed by the controller.";
      };

      workflowApi = mkOption {
        type = types.str;
        default = "https://api.github.com/repos/ec0m3x/nix-configs/actions/workflows/check.yml/runs";
        description = "GitHub API endpoint used as the deployment gate.";
      };

      deployUser = mkOption {
        type = types.str;
        default = "ecomex";
        description = "Existing SSH user used to copy closures to remote targets.";
      };

      interval = mkOption {
        type = types.str;
        default = "5min";
        description = "Delay between completed GitOps checks.";
      };

      targets = mkOption {
        description = "Ordered list of NixOS configurations to build and deploy.";
        default = [];
        type = types.listOf (types.submodule {
          options = {
            name = mkOption {type = types.str;};
            address = mkOption {
              type = types.nullOr types.str;
              default = null;
            };
            local = mkOption {
              type = types.bool;
              default = false;
            };
          };
        });
      };
    };
  };

  config = lib.mkMerge [
    (mkIf cfg.target.enable {
      environment.systemPackages = [activationPackage];

      security.sudo.extraRules = [
        {
          users = [cfg.controller.deployUser];
          commands = [
            {
              command = activationCommand;
              options = ["NOPASSWD"];
            }
          ];
        }
      ];
    })

    (mkIf cfg.controller.enable {
      assertions = [
        {
          assertion = cfg.target.enable;
          message = "The GitOps controller host must also enable homelabGitOps.target.";
        }
        {
          assertion = cfg.controller.targets != [];
          message = "The GitOps controller requires at least one deployment target.";
        }
        {
          assertion = lib.all (target: target.local != (target.address != null)) cfg.controller.targets;
          message = "Each GitOps target must be either local or have an address, but not both.";
        }
        {
          assertion = lib.length (builtins.filter (target: target.local) cfg.controller.targets) == 1;
          message = "The GitOps controller requires exactly one local target.";
        }
      ];

      systemd.services.homelab-gitops = {
        description = "Build and deploy the latest verified homelab revision";
        after = ["network-online.target"];
        wants = ["network-online.target"];
        restartIfChanged = false;
        unitConfig.X-StopOnRemoval = false;
        environment.HOME = "/home/${cfg.controller.deployUser}";
        serviceConfig = {
          Type = "oneshot";
          User = cfg.controller.deployUser;
          StateDirectory = "homelab-gitops";
          StateDirectoryMode = "0750";
          ExecStart = lib.getExe controllerPackage;
          Nice = 10;
          IOSchedulingClass = "best-effort";
          IOSchedulingPriority = 7;
        };
      };

      systemd.timers.homelab-gitops = {
        description = "Poll the GitOps repository";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnBootSec = "3min";
          OnUnitInactiveSec = cfg.controller.interval;
          RandomizedDelaySec = "30s";
          AccuracySec = "15s";
        };
      };
    })
  ];
}
