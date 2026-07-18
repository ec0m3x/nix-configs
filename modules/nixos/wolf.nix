{
  pkgs,
  ...
}: {
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
      # Apps run as ecomex (uid 1000) : users (gid 100) on the host
      WOLF_DEFAULT_RUN_UID = "1000";
      WOLF_DEFAULT_RUN_GID = "100";
      WOLF_LOG_LEVEL = "DEBUG";
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
