{
  lib,
  pkgs,
  ...
}: let
  wolfAppConfig = let
    python = pkgs.python3.withPackages (pythonPackages: [pythonPackages.tomlkit]);
  in
    pkgs.writeTextFile {
      name = "wolf-configure-apps";
      destination = "/bin/wolf-configure-apps";
      executable = true;
      text = ''
        #!${python}/bin/python
        import os
        import stat
        import sys
        import tempfile
        from pathlib import Path

        import tomlkit

        config_path = Path(
            sys.argv[1] if len(sys.argv) > 1 else "/etc/wolf/cfg/config.toml"
        )
        if not config_path.exists():
            raise SystemExit(0)

        document = tomlkit.parse(config_path.read_text())
        managed_environment_keys = (
            "XKB_DEFAULT_LAYOUT=",
            "XKB_DEFAULT_VARIANT=",
            "TZ=",
        )
        desired_environment = [
            "XKB_DEFAULT_LAYOUT=de",
            "XKB_DEFAULT_VARIANT=",
            "TZ=Europe/Berlin",
        ]
        steam_mount_target = "/mnt/steam-library"
        desired_steam_mount = (
            f"/mnt/ssd/steam-library:{steam_mount_target}:rw"
        )
        changed_apps = 0
        changed_steam_mounts = 0

        for profile in document.get("profiles", []):
            for app in profile.get("apps", []):
                runner = app.get("runner")
                if runner is None or runner.get("type") != "docker":
                    continue

                environment = runner.get("env")
                if environment is None:
                    environment = tomlkit.array()
                    runner["env"] = environment

                current_environment = [str(entry) for entry in environment]
                updated_environment = [
                    entry
                    for entry in current_environment
                    if not entry.startswith(managed_environment_keys)
                ] + desired_environment

                if current_environment != updated_environment:
                    environment.clear()
                    environment.extend(updated_environment)
                    changed_apps += 1

                if runner.get("name") == "WolfSteam":
                    mounts = runner.get("mounts")
                    if mounts is None:
                        mounts = tomlkit.array()
                        runner["mounts"] = mounts

                    current_mounts = [str(entry) for entry in mounts]
                    updated_mounts = [
                        entry
                        for entry in current_mounts
                        if not (
                            len(entry.split(":")) >= 2
                            and entry.split(":")[1] == steam_mount_target
                        )
                    ] + [desired_steam_mount]

                    if current_mounts != updated_mounts:
                        mounts.clear()
                        mounts.extend(updated_mounts)
                        changed_steam_mounts += 1

        if changed_apps == 0 and changed_steam_mounts == 0:
            raise SystemExit(0)

        config_stat = config_path.stat()
        temporary_fd, temporary_name = tempfile.mkstemp(
            dir=config_path.parent,
            prefix=".config.toml.",
        )
        try:
            with os.fdopen(temporary_fd, "w") as temporary_file:
                temporary_file.write(tomlkit.dumps(document))
                temporary_file.flush()
                os.fsync(temporary_file.fileno())
            os.chmod(temporary_name, stat.S_IMODE(config_stat.st_mode))
            os.chown(temporary_name, config_stat.st_uid, config_stat.st_gid)
            os.replace(temporary_name, config_path)
        finally:
            if os.path.exists(temporary_name):
                os.unlink(temporary_name)

        print(
            f"Configured German keyboard layout and timezone for "
            f"{changed_apps} Wolf apps; "
            f"configured SSD Steam library for {changed_steam_mounts} apps"
        )
      '';
    };
in {
  # Games On Whales - Wolf (headless game streaming)
  # Nvidia Manual method: requires a pre-populated `nvidia-driver-vol` docker volume
  # containing the host's Nvidia driver files. Run `wolf-update-nvidia-volume` once
  # (and again after every Nvidia driver update) before starting Wolf.
  # Docs: https://games-on-whales.github.io/wolf/stable/user/quickstart.html
  virtualisation.oci-containers.containers.wolf = {
    autoStart = true;
    image = "ghcr.io/games-on-whales/wolf:stable";
    environment = {
      NVIDIA_DRIVER_VOLUME_NAME = "nvidia-driver-vol";
      TZ = "Europe/Berlin";
      # Apps run as ecomex (uid 1000) : users (gid 100) on the host
      WOLF_DEFAULT_RUN_UID = "1000";
      WOLF_DEFAULT_RUN_GID = "100";
    };
    volumes = [
      "nvidia-driver-vol:/usr/nvidia:rw"
      "/etc/wolf:/etc/wolf:rw"
      "/var/run/docker.sock:/var/run/docker.sock:rw"
      "/dev/:/dev/:rw"
      "/run/udev:/run/udev:rw"
    ];
    extraOptions = [
      "--network=host"
      "--device-cgroup-rule=c 13:* rmw"
      "--device=/dev/dri"
      "--device=/dev/uinput"
      "--device=/dev/uhid"
      "--device=/dev/nvidia-uvm"
      "--device=/dev/nvidia-uvm-tools"
      "--device=/dev/nvidia-caps/nvidia-cap1"
      "--device=/dev/nvidia-caps/nvidia-cap2"
      "--device=/dev/nvidiactl"
      "--device=/dev/nvidia0"
      "--device=/dev/nvidia-modeset"
    ];
  };

  # Keep the mutable Wolf app config consistent before the container starts:
  # use a German keyboard layout and the Europe/Berlin timezone in every
  # Docker app, and expose the SSD-backed Steam library to the Steam app container.
  systemd.services.docker-wolf.unitConfig.RequiresMountsFor = "/mnt/ssd";
  systemd.services.docker-wolf.preStart = lib.mkBefore ''
    ${wolfAppConfig}/bin/wolf-configure-apps
  '';

  # Virtual input devices (uinput/uhid + virtual gamepads)
  services.udev.extraRules = ''
    KERNEL=="uinput", SUBSYSTEM=="misc", MODE="0660", GROUP="input", OPTIONS+="static_node=uinput", TAG+="uaccess"
    KERNEL=="uhid", GROUP="input", MODE="0660", TAG+="uaccess"
    KERNEL=="hidraw*",   ATTRS{name}=="Wolf PS5 (virtual) pad", GROUP="root", MODE="0660", ENV{ID_SEAT}="seat9"
    SUBSYSTEMS=="input", ATTRS{name}=="Wolf X-Box One (virtual) pad", GROUP="root", MODE="0660", ENV{ID_SEAT}="seat9"
    SUBSYSTEMS=="input", ATTRS{name}=="Wolf PS5 (virtual) pad", GROUP="root", MODE="0660", ENV{ID_SEAT}="seat9"
    SUBSYSTEMS=="input", ATTRS{name}=="Wolf gamepad (virtual) motion sensors", GROUP="root", MODE="0660", ENV{ID_SEAT}="seat9"
    SUBSYSTEMS=="input", ATTRS{name}=="Wolf Nintendo (virtual) pad", GROUP="root", MODE="0660", ENV{ID_SEAT}="seat9"
  '';

  # Wolf config directory
  systemd.tmpfiles.rules = [
    "d /etc/wolf 0755 root root -"
    "d /mnt/ssd/steam-library 0755 ecomex users -"
  ];

  # Firewall: Wolf (host network)
  networking.firewall = {
    allowedTCPPorts = [47984 47989 48010];
    allowedUDPPorts = [47999 48100 48200];
  };

  # Helper: build gow/nvidia-driver image + populate nvidia-driver-vol
  # Re-run after every Nvidia driver update.
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "wolf-update-nvidia-volume" ''
      set -euo pipefail
      NV_VERSION=$(cat /sys/module/nvidia/version)
      echo "Building gow/nvidia-driver image for driver $NV_VERSION ..."
      ${pkgs.curl}/bin/curl -fsSL \
        https://raw.githubusercontent.com/games-on-whales/gow/master/images/nvidia-driver/Dockerfile \
        | docker build -t gow/nvidia-driver:latest -f - --build-arg NV_VERSION="$NV_VERSION" .
      echo "Populating nvidia-driver-vol ..."
      docker volume rm nvidia-driver-vol 2>/dev/null || true
      docker create --mount source=nvidia-driver-vol,destination=/usr/nvidia gow/nvidia-driver:latest sh >/dev/null
      echo "Done. Restart Wolf with: systemctl restart docker-wolf.service"
    '')
  ];
}
