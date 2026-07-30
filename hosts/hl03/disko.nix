# Disk-Layout hl03: Root auf der LITEON 256 GB, /srv auf der Samsung 840 PRO.
# Die Samsung darf erst nach Entfernen der NAS-Replikation und des
# pve03-HA-Ziels formatiert werden.
#
# Die 1-TB-EXCERIA mit dem bestehenden PBS-Datastore wird ausdrücklich nicht
# von disko verwaltet. Sie wird in configuration.nix anhand ihrer vorhandenen
# Dateisystem-UUID eingehängt.
{
  disko.devices.disk = {
    main = {
      type = "disk";
      device = "/dev/disk/by-id/ata-LITEON_L8H-256V2G-HP_002628100X62";
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

    srv = {
      type = "disk";
      device = "/dev/disk/by-id/ata-Samsung_SSD_840_PRO_Series_S12PNEACB03826W";
      content = {
        type = "gpt";
        partitions.data = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/srv";
          };
        };
      };
    };
  };
}
