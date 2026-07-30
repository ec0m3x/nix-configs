# Disk-Layout hl01: Root auf der M.2-SSD (SAMSUNG PM871b 256 GB).
# Die zweite SSD (Samsung 860 EVO 250 GB, S3YJNX0KB91294E) wird in Phase 4
# als /srv-Datenplatte (immich, paperless, NAS-Shares) eingerichtet —
# disko fasst sie hier bewusst nicht an.
{
  disko.devices.disk.main = {
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
}
