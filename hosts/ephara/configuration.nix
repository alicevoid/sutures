{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./homeassistant.nix
  ];

  # host
  networking.hostName = "ephara";

  # SSH keyFiles
  users.users.alice.openssh.authorizedKeys.keyFiles = [
    ./keys/athreos.pub
    ./keys/kunoros.pub
  ];

  # keep alice's user manager up after logout, so background claude sessions + tmux live on
  users.users.alice.linger = true;

  # Mirror: mdadm RAID1 on the two 14 TB drives, ext4 at /data
  #   nofail: a missing drive must never stop the boot (no boot = no SSH)
  boot.swraid.enable = true;
  boot.swraid.mdadmConf = ''
    MAILADDR root
    ARRAY /dev/md0 metadata=1.2 UUID=b53f7929:574d55d5:ed63dcb3:1b474e3c
  '';
  fileSystems."/data".options = [
    "nofail"
    "x-systemd.device-timeout=10s"
  ];

  # ZFS: pool "tank" on the 14 TB drives (replaces the mdadm mirror)
  #   hostId: random, never change (ZFS uses it to tell which host owns a pool)
  boot.supportedFilesystems = [ "zfs" ];
  networking.hostId = "9bd9aba7";
  services.zfs.autoScrub.enable = true; # monthly

  boot.kernelParams = [
    "ahci.mobile_lpm_policy=1" # SATA link power saving off (part of the 2026-10-23 link-drop fix)
    "zfs.zfs_arc_max=6442450944" # 6 GiB ARC cap, leaves RAM for k3s, HA and Jellyfin
  ];

  # TEMPORARY (2026-10-25): offline root shrink from the initrd rescue shell (the USB boot loops).
  #   Boot once with rd.systemd.unit=rescue.target, run shrink-root.sh from the ESP.
  #   Remove this whole block after the shrink: emergencyAccess gives a root shell at the console.
  boot.initrd.systemd.emergencyAccess = true;
  boot.initrd.supportedFilesystems.vfat = true;
  boot.initrd.systemd.extraBin = {
    sgdisk = "${pkgs.gptfdisk}/bin/sgdisk";
    partprobe = "${pkgs.parted}/bin/partprobe";
    e2fsck = "${pkgs.e2fsprogs}/bin/e2fsck";
    resize2fs = "${pkgs.e2fsprogs}/bin/resize2fs";
    findmnt = "${pkgs.util-linux}/bin/findmnt";
    lsblk = "${pkgs.util-linux}/bin/lsblk";
  };

  # Drive health
  services.smartd.enable = true;

  environment.systemPackages = with pkgs; [
    nvme-cli # NVMe temperatures and throttle counters (health-check.sh)
    smartmontools
    wget
  ];

  # never change
  system.stateVersion = "26.05";
}
