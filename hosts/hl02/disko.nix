# Disk-Layout hl02: eine SSD (Samsung 860 EVO 250 GB).
# ESP + ext4-Root, kein Swap-Partition — Swap kommt bei Bedarf als Datei.
{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/disk/by-id/ata-Samsung_SSD_860_EVO_250GB_S3YJNX0KA39733N";
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
