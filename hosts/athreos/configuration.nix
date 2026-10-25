{ config, pkgs, ... }:

{
  networking.hostName = "athreOS";

  # ephara's ZFS pool over NFS (Tailscale). Mounts on first access, unmounts after 10 idle minutes,
  #   so a laptop off the network never hangs on a stale mount.
  boot.supportedFilesystems = [ "nfs" ];
  fileSystems."/mnt/ephara" = {
    device = "100.75.158.9:/data";
    fsType = "nfs";
    options = [
      "nfsvers=4.2"
      "noauto"
      "x-systemd.automount"
      "x-systemd.idle-timeout=600"
      "x-systemd.mount-timeout=15"
      "nofail"
      "_netdev"
    ];
  };
  system.stateVersion = "25.05";
}

