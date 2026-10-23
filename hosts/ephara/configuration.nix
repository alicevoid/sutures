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

  # SATA link power saving off (part of the 2026-10-23 link-drop fix)
  boot.kernelParams = [ "ahci.mobile_lpm_policy=1" ];

  # Drive health
  services.smartd.enable = true;

  environment.systemPackages = with pkgs; [
    smartmontools
    wget
  ];

  # never change
  system.stateVersion = "26.05";
}
