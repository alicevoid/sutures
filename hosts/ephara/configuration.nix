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

  # LAN bridge br0 (same shape as pharika, so Cilium's devices = [ "br0" ] fits both nodes)
  #   NetworkManager owns it (not networking.interfaces): NM learns the Thread route
  #   (Route Information in the Google TV's router advertisements) that Matter needs.
  #   Same MAC as the NIC, so the router keeps giving out 10.0.0.65.
  networking.networkmanager.ensureProfiles.profiles = {
    br0 = {
      connection = {
        id = "br0";
        type = "bridge";
        interface-name = "br0";
        autoconnect-priority = 100;
      };
      bridge = {
        stp = false;
        mac-address = "18:66:da:3d:14:f7";
      };
      ipv4.method = "auto";
      ipv6.method = "auto";
    };
    br0-port = {
      connection = {
        id = "br0-port";
        type = "ethernet";
        interface-name = "enp0s31f6";
        controller = "br0";
        port-type = "bridge";
        autoconnect-priority = 100;
      };
    };
  };

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
  boot.zfs.forceImportRoot = false; # root is ext4; never force-import a pool another host used
  services.zfs.autoScrub.enable = true; # monthly

  # nscd: the resolvconf hook restarts it on every resolv.conf change. At boot NetworkManager
  #   and Tailscale rewrite that file several times in seconds, nscd hits the start limit and
  #   stays down. Without nscd, DynamicUser services (matterjs-server) cannot look up their user.
  systemd.services.nscd.startLimitIntervalSec = 0;

  boot.kernelParams = [
    "ahci.mobile_lpm_policy=1" # SATA link power saving off (part of the 2026-10-23 link-drop fix)
    "zfs.zfs_arc_max=6442450944" # 6 GiB ARC cap, leaves RAM for k3s, HA and Jellyfin
  ];

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
