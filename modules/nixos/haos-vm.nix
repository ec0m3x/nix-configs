{pkgs, ...}: let
  haosVersion = "18.2";
  haosDisk = "/srv/haos/haos.qcow2";
  haosConfigDisk = "/srv/haos/config.img";

  haosImage = pkgs.fetchurl {
    url = "https://github.com/home-assistant/operating-system/releases/download/${haosVersion}/haos_ova-${haosVersion}.qcow2.xz";
    hash = "sha256-JU5T81TfBznjr8Cb5UMaB99T8N9rcDiFQE9mXEVPJU4=";
  };

  haosNetwork = pkgs.writeText "haos-network" ''
    [connection]
    id=haos-lan
    uuid=0f79cd6c-48c8-41e4-b1db-6fffb112f90e
    type=802-3-ethernet
    autoconnect=true
    autoconnect-priority=100
    llmnr=2
    mdns=2

    [ipv4]
    method=manual
    address=10.20.50.14/24;10.20.50.1
    dns=10.20.50.49;10.20.50.1;

    [ipv6]
    method=disabled
  '';

  haosDomain = pkgs.writeText "haos-domain.xml" ''
    <domain type='kvm'>
      <name>haos</name>
      <uuid>bac9c9e3-ba38-4113-b3bb-7ee03cc6b09b</uuid>
      <description>Home Assistant Operating System ${haosVersion}</description>
      <memory unit='MiB'>4096</memory>
      <currentMemory unit='MiB'>4096</currentMemory>
      <vcpu placement='static'>2</vcpu>
      <os>
        <type arch='x86_64' machine='q35'>hvm</type>
        <loader readonly='yes' secure='no' type='pflash'>${pkgs.OVMF.fd}/FV/OVMF_CODE.fd</loader>
        <nvram template='${pkgs.OVMF.fd}/FV/OVMF_VARS.fd'>/srv/haos/OVMF_VARS.fd</nvram>
        <boot dev='hd'/>
      </os>
      <features>
        <acpi/>
        <apic/>
      </features>
      <cpu mode='host-passthrough' check='none'/>
      <clock offset='utc'/>
      <on_poweroff>destroy</on_poweroff>
      <on_reboot>restart</on_reboot>
      <on_crash>restart</on_crash>
      <devices>
        <emulator>/run/libvirt/nix-emulators/qemu-system-x86_64</emulator>
        <controller type='scsi' model='virtio-scsi'/>
        <controller type='usb' model='qemu-xhci'/>
        <disk type='file' device='disk'>
          <driver name='qemu' type='qcow2' cache='none' discard='unmap'/>
          <source file='${haosDisk}'/>
          <target dev='sda' bus='scsi'/>
        </disk>
        <disk type='file' device='disk'>
          <driver name='qemu' type='raw'/>
          <source file='${haosConfigDisk}'/>
          <target dev='sdb' bus='usb'/>
          <readonly/>
        </disk>
        <interface type='direct'>
          <mac address='02:00:00:20:50:14'/>
          <source dev='lan0' mode='bridge'/>
          <model type='virtio'/>
        </interface>
        <serial type='pty'>
          <target type='isa-serial' port='0'/>
        </serial>
        <console type='pty'>
          <target type='serial' port='0'/>
        </console>
        <channel type='unix'>
          <target type='virtio' name='org.qemu.guest_agent.0'/>
        </channel>
        <graphics type='vnc' autoport='yes' listen='127.0.0.1'/>
      </devices>
    </domain>
  '';
in {
  boot.kernelModules = ["kvm-intel"];

  virtualisation.libvirtd = {
    enable = true;
    onShutdown = "shutdown";
    shutdownTimeout = 300;
    qemu.package = pkgs.qemu_kvm;
  };

  users.users.ecomex.extraGroups = ["libvirtd"];

  systemd.tmpfiles.rules = [
    "d /srv/haos 0750 root root -"
  ];

  systemd.services.haos-vm-provision = {
    description = "Provision and start the Home Assistant OS VM";
    wantedBy = ["multi-user.target"];
    requires = ["libvirtd.service"];
    wants = ["network-online.target"];
    after = ["libvirtd.service" "network-online.target"];
    path = [
      pkgs.coreutils
      pkgs.dosfstools
      pkgs.libvirt
      pkgs.mtools
      pkgs.qemu_kvm
      pkgs.xz
    ];
    environment.LC_ALL = "C";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -Eeuo pipefail
      disk_temp=""
      config_temp=""
      cleanup() {
        [[ -z "''${disk_temp}" ]] || rm -f -- "''${disk_temp}"
        [[ -z "''${config_temp}" ]] || rm -f -- "''${config_temp}"
      }
      trap cleanup EXIT

      install --directory --owner=root --group=root --mode=0750 /srv/haos

      if [[ ! -e ${haosDisk} ]]; then
        disk_temp="$(mktemp --tmpdir=/srv/haos haos.qcow2.XXXXXX)"
        xz --decompress --stdout ${haosImage} >"''${disk_temp}"
        qemu-img check --format=qcow2 "''${disk_temp}"
        qemu-img resize --format=qcow2 "''${disk_temp}" 32G
        chmod 0600 "''${disk_temp}"
        mv "''${disk_temp}" ${haosDisk}
        disk_temp=""
      fi

      if [[ ! -e ${haosConfigDisk} ]]; then
        config_temp="$(mktemp --tmpdir=/srv/haos config.img.XXXXXX)"
        truncate --size=32M "''${config_temp}"
        mkfs.vfat -n CONFIG "''${config_temp}"
        mmd -i "''${config_temp}" ::/network
        mcopy -i "''${config_temp}" ${haosNetwork} ::/network/my-network
        chmod 0600 "''${config_temp}"
        mv "''${config_temp}" ${haosConfigDisk}
        config_temp=""
      fi

      qemu-img check --format=qcow2 ${haosDisk}
      virsh --connect qemu:///system define ${haosDomain}
      virsh --connect qemu:///system autostart haos

      case "$(virsh --connect qemu:///system domstate haos)" in
        "shut off" | "crashed")
          virsh --connect qemu:///system start haos
          ;;
        paused)
          virsh --connect qemu:///system resume haos
          ;;
      esac
    '';
  };
}
