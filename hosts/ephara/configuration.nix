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

  # ZFS: pool "tank", a mirror of the two 14 TB drives
  #   hostId: random, never change (ZFS uses it to tell which host owns a pool)
  boot.supportedFilesystems = [ "zfs" ];
  networking.hostId = "9bd9aba7";
  boot.zfs.forceImportRoot = false; # root is ext4; never force-import a pool another host used
  #   Import tank at boot. Datasets mount through zfs-mount.service, not fstab, so a missing
  #   pool never stops the boot (the nofail rule).
  boot.zfs.extraPools = [ "tank" ];
  services.zfs.autoScrub.enable = true; # monthly
  #   Short by-id names for the NVMe ZFS partitions (/dev/disk/by-id/ephara-l2arc, ephara-slog).
  #   The pool import scans only /dev/disk/by-id and keeps a stored path that it finds there,
  #   so zpool status shows these names, not nvme-...-part4.
  services.udev.extraRules = ''
    ENV{ID_PART_ENTRY_NAME}=="ephara-l2arc|ephara-slog", SYMLINK+="disk/by-id/$env{ID_PART_ENTRY_NAME}"
  '';

  # nscd: the resolvconf hook restarts it on every resolv.conf change. At boot NetworkManager
  #   and Tailscale rewrite that file several times in seconds, nscd hits the start limit and
  #   stays down. Without nscd, DynamicUser services (matterjs-server) cannot look up their user.
  systemd.services.nscd.startLimitIntervalSec = 0;

  # Folder layout on /data (MIGRATION, "Storage reference", and JELLYFIN "Target layout").
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
      #   media/watch: streamed media (Jellyfin). movies/ and shows/ are Radarr's and Sonarr's root
      #   folders. anime/, oddities/ and extras/ are managed by hand and not listed here.
      for d in media media/watch media/watch/movies media/watch/shows media/music media/books \
               media/audiobooks downloads downloads/incomplete downloads/complete; do
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

  # Snapshots (sanoid): read-only points in time. A delete or ransomware cannot reach older ones.
  #   tank itself (media, downloads) gets none: it can be downloaded again, and churn would fill them.
  #   tank/vaults gets none: it is empty and reserved. The vault lives on pharika and is in pvc-backup.
  #   Browse: ls /data/<dataset>/.zfs/snapshot/   List: zfs list -t snapshot
  services.sanoid = {
    enable = true;
    templates = {
      backup = {
        hourly = 0;
        daily = 30;
        monthly = 12;
        daily_hour = 4; # after pvc-backup (02:30), ephara-pvc-backup (02:45) and the HA copy (03:00)
        autosnap = true;
        autoprune = true;
      };
      shared = {
        hourly = 0;
        daily = 14;
        monthly = 0;
        autosnap = true;
        autoprune = true;
      };
    };
    datasets = {
      "tank/shared".useTemplate = [ "shared" ];
      "tank/backups" = {
        useTemplate = [ "backup" ];
        recursive = true;
      };
    };
  };

  # Nightly copy of Home Assistant's state to the pool (03:00).
  #   The recorder database gets a consistent SQLite .backup copy. A raw copy of a live SQLite file
  #   can be torn. The rest is a plain rsync. sanoid snapshots tank/backups at 04:00.
  systemd.services.hass-backup = {
    description = "Copy Home Assistant state to /data/backups/homeassistant";
    unitConfig = {
      RequiresMountsFor = "/data/backups/homeassistant";
      ConditionPathIsMountPoint = "/data/backups/homeassistant";
    };
    path = [
      pkgs.rsync
      pkgs.sqlite
    ];
    serviceConfig.Type = "oneshot";
    script = ''
      set -euo pipefail
      dest=/data/backups/homeassistant
      sqlite3 /var/lib/hass/home-assistant_v2.db ".backup '$dest/home-assistant_v2.db.tmp'"
      mv "$dest/home-assistant_v2.db.tmp" "$dest/home-assistant_v2.db"
      rsync -a --delete --exclude 'home-assistant_v2.db*' /var/lib/hass/ "$dest/hass/"
      date -Is > "$dest/LAST_SUCCESS"
    '';
  };
  systemd.timers.hass-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "03:00";
      Persistent = true;
    };
  };

  # Nightly copy of ephara's k3s PVCs (local-path on the NVMe) to the pool (02:45).
  #   Same method as pvc-backup on pharika: SQLite files get a consistent .backup copy first,
  #   then the PVC folders are copied as they are. Skipped: caches (transcodes, images).
  #   tank/backups/ephara is a child of tank/backups, so sanoid snapshots it at 04:00.
  #   Restore: copy a PVC folder back with the app scaled to 0, or use the sqlite/ dump.
  systemd.services.ephara-pvc-backup = {
    description = "Copy ephara's k3s PVCs to /data/backups/ephara";
    unitConfig = {
      RequiresMountsFor = "/data/backups/ephara";
      ConditionPathIsMountPoint = "/data/backups/ephara";
    };
    path = [
      pkgs.rsync
      pkgs.sqlite
      pkgs.findutils
      pkgs.coreutils
    ];
    serviceConfig.Type = "oneshot";
    script = ''
      set -euo pipefail
      dest=/data/backups/ephara
      work=/var/tmp/ephara-pvc-backup
      storage=/var/lib/rancher/k3s/storage

      # 1. Consistent copies of every SQLite database in the PVCs
      rm -rf "$work"; mkdir -p "$work/sqlite"
      find "$storage" -type f \( -name '*.db' -o -name '*.sqlite' -o -name '*.sqlite3' \) |
        while read -r f; do
          [ "$(head -c 15 "$f")" = "SQLite format 3" ] || continue
          rel=''${f#"$storage"/}
          mkdir -p "$work/sqlite/$(dirname "$rel")"
          sqlite3 "$f" ".backup '$work/sqlite/$rel'"
        done

      # 2. The PVC folders, as they are
      rsync -aH --numeric-ids --delete \
        --exclude '*_jellyfin_jellyfin-cache' \
        "$storage/" "$dest/storage/"

      # 3. The SQLite copies
      rsync -a --delete "$work/sqlite/" "$dest/sqlite/"

      rm -rf "$work"
      date -Is > "$dest/LAST_SUCCESS"
    '';
  };
  systemd.timers.ephara-pvc-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "02:45";
      Persistent = true;
    };
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
