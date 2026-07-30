# Disk-Layout hl01: Root auf der M.2-SSD (SAMSUNG PM871b 256 GB), /srv auf
# der Samsung 860 EVO 250 GB. Beide Platten bilden aktuell den Proxmox-ZFS-
# Mirror; dieses Layout darf erst nach dem vollständig erfüllten Phase-4-Gate
# angewendet werden.
{
  disko.devices.disk = {
    main = {
      type = "disk";
      device = "/dev/disk/by-id/ata-SAMSUNG_SSD_PM871b_M.2_2280_256GB_S3U0NE1K918382";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = ["umask=0077"];
            };
          };
          root = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
        };
      };
    };
    data = {
      type = "disk";
      device = "/dev/disk/by-id/ata-Samsung_SSD_860_EVO_250GB_S3YJNX0KB91294E";
      content = {
        type = "gpt";
        partitions.srv = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/srv";
            mountOptions = ["noatime"];
          };
        };
      };
    };
  };
}
