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

  # ZFS: pool "tank" on the 14 TB drives (replaces the mdadm mirror)
  #   hostId: random, never change (ZFS uses it to tell which host owns a pool)
  boot.supportedFilesystems = [ "zfs" ];
  networking.hostId = "9bd9aba7";
  boot.zfs.forceImportRoot = false; # root is ext4; never force-import a pool another host used
  #   Import tank at boot. Datasets mount through zfs-mount.service, not fstab, so a missing
  #   pool never stops the boot (the nofail rule).
  boot.zfs.extraPools = [ "tank" ];
  services.zfs.autoScrub.enable = true; # monthly

  # nscd: the resolvconf hook restarts it on every resolv.conf change. At boot NetworkManager
  #   and Tailscale rewrite that file several times in seconds, nscd hits the start limit and
  #   stays down. Without nscd, DynamicUser services (matterjs-server) cannot look up their user.
  systemd.services.nscd.startLimitIntervalSec = 0;

  # Folder layout on /data (MIGRATION Step 5): one folder per type of content, not per app.
  #   media/ and downloads/ live in the same dataset (tank), so hard links and moves stay instant.
  #   A service, not systemd.tmpfiles: tmpfiles runs before the pool mounts and would create the
  #   folders on the root fs under the mountpoint.
  systemd.services.data-layout = {
    description = "Create the /data folder layout on the ZFS pool";
    after = [ "zfs-mount.service" ];
    wants = [ "zfs-mount.service" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig = {
      RequiresMountsFor = "/data";
      ConditionPathIsMountPoint = "/data";
    };
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      for d in media media/movies media/shows media/music media/books media/audiobooks \
               downloads downloads/incomplete downloads/complete; do
        install -d -m 2775 -o root -g media "/data/$d"
      done
      chown alice:users /data/vaults
    '';
  };

  boot.kernelParams = [
    "ahci.mobile_lpm_policy=1" # SATA link power saving off (part of the 2026-10-23 link-drop fix)
    "zfs.zfs_arc_max=6442450944" # 6 GiB ARC cap, leaves RAM for k3s, HA and Jellyfin
  ];

  # NFS server (NFSv4 only). Exports are datasets of the pool:
  #   /data          athreos over Tailscale, whole pool (crossmnt: also the child datasets), root squashed
  #   /data/shared   the cluster nodes, for csi-driver-nfs (no_root_squash: its controller makes and
  #                  deletes PVC folders as root)
  #   /data/backups/pharika   pharika only, for the nightly PVC backup (keeps file owners)
  services.nfs.server = {
    enable = true;
    exports = ''
      /data                  100.82.173.116(rw,sync,no_subtree_check,crossmnt,root_squash)
      /data/shared           10.0.0.141(rw,sync,no_subtree_check,no_root_squash) 10.0.0.65(rw,sync,no_subtree_check,no_root_squash)
      /data/backups/pharika  10.0.0.141(rw,sync,no_subtree_check,no_root_squash)
    '';
  };
  services.nfs.settings.nfsd.vers3 = false;
  # Export only when the pool is mounted. Otherwise it would export the empty folders on the root fs.
  systemd.services.nfs-server = {
    after = [ "zfs-mount.service" ];
    unitConfig.ConditionPathIsMountPoint = "/data/shared";
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
