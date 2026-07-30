# Disk-Layout hl03: Root auf der LITEON 256 GB.
# Nicht von disko angefasst:
# - Samsung 840 PRO 120 GB (S12PNEACB03826W): wird in Phase 3 als
#   /srv-Datenplatte (Nextcloud-Daten, Postgres) eingerichtet.
# - 1 TB EXCERIA PLUS (vermutlich USB, trägt aktuell den PBS-Datastore!):
#   wird erst NACH der letzten PBS-Vollsicherung und bewusster Entscheidung
#   über den Datastore-Verbleib als restic-Ziel neu formatiert.
{
  disko.devices.disk.main = {
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
}
