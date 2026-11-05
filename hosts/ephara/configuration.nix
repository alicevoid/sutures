{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./homeassistant.nix
  ];

  networking.hostName = "ephara";

  users.users.alice.openssh.authorizedKeys.keyFiles = [
    ./keys/athreos.pub
    ./keys/kunoros.pub
    ./keys/pharika.pub # agents on pharika run checks on ephara
  ];

  # keeps alice's user services (tmux, background agents) running after logout
  users.users.alice.linger = true;

  # LAN bridge br0, same name as on pharika so Cilium's devices = [ "br0" ] fits both nodes.
  #   NetworkManager owns it because it learns the Thread route (from the Google TV's router
  #   advertisements) that Matter needs. The NIC's MAC keeps the DHCP lease on 10.0.0.65.
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

  # ZFS pool "tank": a mirror of the two 14 TB drives.
  #   hostId is random. Never change it: ZFS uses it to tell which host owns a pool.
  boot.supportedFilesystems = [ "zfs" ];
  networking.hostId = "9bd9aba7";
  boot.zfs.forceImportRoot = false; # root is ext4; never force-import a pool another host used
  #   Datasets mount through zfs-mount.service, not fstab, so a missing pool never stops the boot.
  boot.zfs.extraPools = [ "tank" ];
  services.zfs.autoScrub.enable = true; # monthly
  # Mail on pool events. Verbose also mails a clean scrub, which proves the route each month.
  services.zfs.zed.enableMail = true;
  services.zfs.zed.settings = {
    ZED_EMAIL_ADDR = [ "root" ];
    ZED_EMAIL_PROG = "${pkgs.msmtp}/bin/msmtp";
    ZED_EMAIL_OPTS = "@ADDRESS@";
    ZED_NOTIFY_INTERVAL_SECS = 3600;
    ZED_NOTIFY_VERBOSE = true;
  };
  #   Short by-id names for the NVMe cache partitions, so zpool status shows ephara-l2arc and
  #   ephara-slog in place of nvme-...-part4.
  services.udev.extraRules = ''
    ENV{ID_PART_ENTRY_NAME}=="ephara-l2arc|ephara-slog", SYMLINK+="disk/by-id/$env{ID_PART_ENTRY_NAME}"
  '';

  # NetworkManager and Tailscale rewrite resolv.conf several times at boot, and each rewrite
  #   restarts nscd. Without this, nscd hits the start limit and stays down, and DynamicUser
  #   services (matterjs-server) cannot look up their user.
  systemd.services.nscd.startLimitIntervalSec = 0;

  # Folder layout on /data. media/watch/ and media/downloads/ share one dataset, so hard links
  #   and moves are instant. A service, because systemd.tmpfiles runs before the pool mounts
  #   and would create the folders on the root fs.
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
      # anime/, anime-movies/, oddities/ and extras/ under media/watch are made by hand.
      for d in media media/watch media/watch/movies media/watch/shows media/music media/books \
               media/audiobooks media/downloads media/downloads/public media/downloads/tracker \
               media/downloads/own; do
        install -d -m 2775 -o root -g media "/data/$d"
      done
      chown alice:users /data/vaults
    '';
  };

  boot.kernelParams = [
    "ahci.mobile_lpm_policy=1" # SATA link power saving off; it caused link drops
    "zfs.zfs_arc_max=6442450944" # 6 GiB ARC cap, leaves RAM for k3s, HA and Jellyfin
    # No simpledrm boot framebuffer. When i915 takes over, simpledrm can leave a dead
    #   /dev/dri/by-path link that makes every container start fail ("mkdir ... file exists").
    "initcall_blacklist=simpledrm_platform_driver_init"
  ];

  # NFSv4 exports:
  #   /data                  athreos over Tailscale, root squashed
  #   /data/shared           the cluster nodes; no_root_squash because csi-driver-nfs makes PVC folders as root
  #   /data/backups/pharika  pharika's pvc-backup; no_root_squash keeps file owners
  services.nfs.server = {
    enable = true;
    exports = ''
      /data                  100.82.173.116(rw,sync,no_subtree_check,crossmnt,root_squash)
      /data/shared           10.0.0.141(rw,sync,no_subtree_check,no_root_squash) 10.0.0.65(rw,sync,no_subtree_check,no_root_squash)
      /data/backups/pharika  10.0.0.141(rw,sync,no_subtree_check,no_root_squash)
    '';
  };
  services.nfs.settings.nfsd.vers3 = false;
  # Export only when the pool is mounted, never the empty folders on the root fs.
  systemd.services.nfs-server = {
    after = [ "zfs-mount.service" ];
    unitConfig.ConditionPathIsMountPoint = "/data/shared";
  };

  # Snapshots. tank itself (media, downloads) gets none: it can be downloaded again, and the
  #   churn would fill them. Browse: ls /data/<dataset>/.zfs/snapshot/
  services.sanoid = {
    enable = true;
    templates = {
      backup = {
        hourly = 0;
        daily = 30;
        monthly = 12;
        daily_hour = 4; # after the 02:30, 02:45 and 03:00 backups
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

  # Home Assistant state to the pool. The recorder database gets a SQLite .backup copy,
  #   because a raw copy of a live SQLite file can be torn.
  systemd.services.hass-backup = {
    description = "Copy Home Assistant state to /data/backups/homeassistant";
    onFailure = [ "notify-failure@%n.service" ];
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

  # ephara's k3s PVCs to the pool, the same method as pvc-backup on pharika.
  #   Restore: copy a PVC folder back with the app scaled to 0, or use the sqlite/ dump.
  systemd.services.ephara-pvc-backup = {
    description = "Copy ephara's k3s PVCs to /data/backups/ephara";
    onFailure = [ "notify-failure@%n.service" ];
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

      # 1. SQLite copies
      rm -rf "$work"; mkdir -p "$work/sqlite"
      find "$storage" -type f \( -name '*.db' -o -name '*.sqlite' -o -name '*.sqlite3' \) |
        while read -r f; do
          [ "$(head -c 15 "$f")" = "SQLite format 3" ] || continue
          rel=''${f#"$storage"/}
          mkdir -p "$work/sqlite/$(dirname "$rel")"
          sqlite3 "$f" ".backup '$work/sqlite/$rel'"
        done

      # 2. PVC folders (not the Jellyfin cache or incomplete downloads)
      rsync -aH --numeric-ids --delete \
        --exclude '*_jellyfin_jellyfin-cache' \
        --exclude '*_downloads_incomplete' \
        "$storage/" "$dest/storage/"

      # 3. SQLite copies into place
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

  # Nightly decode check of new library files (partial and zero-filled files slipped in before).
  #   ctime, not mtime: an import's hard link updates ctime. A bad file fails the unit, so it mails.
  systemd.services.media-check = {
    description = "Check new files in /data/media/watch for read and decode errors";
    onFailure = [ "notify-failure@%n.service" ];
    unitConfig = {
      RequiresMountsFor = "/data";
      ConditionPathIsMountPoint = "/data";
    };
    path = [
      pkgs.ffmpeg-headless
      pkgs.findutils
      pkgs.coreutils
    ];
    serviceConfig = {
      Type = "oneshot";
      Nice = 19;
      IOSchedulingClass = "idle";
    };
    script = ''
      set -uo pipefail
      bad=0
      checked=0
      while IFS= read -r -d "" f; do
        checked=$((checked + 1))
        # Demux every byte, then decode the first and last 30 s. -map -0:t skips attachments (fonts).
        err=$(
          ffmpeg -v error -nostdin -i "$f" -map 0 -map -0:t -c copy -f null - 2>&1
          ffmpeg -v error -nostdin -t 30 -i "$f" -f null - 2>&1
          ffmpeg -v error -nostdin -sseof -30 -i "$f" -f null - 2>&1
        )
        if [ -n "$err" ]; then
          bad=$((bad + 1))
          echo "BAD: $f"
          printf '%s\n' "$err" | head -n 5 | sed 's/^/    /'
        fi
      done < <(find /data/media/watch -path /data/media/watch/.recycle -prune -o -type f \
        \( -iname '*.mkv' -o -iname '*.mp4' -o -iname '*.m4v' -o -iname '*.avi' -o -iname '*.ts' \) \
        -cmin -1560 -print0)
      echo "checked $checked files, $bad bad"
      [ "$bad" -eq 0 ]
    '';
  };
  systemd.timers.media-check = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "05:00"; # after the backups and sanoid (04:00)
      Persistent = true;
    };
  };

  services.smartd = {
    enable = true;
    notifications.mail = {
      enable = true;
      recipient = "root";
      sender = "no-reply@pvc.tools";
      mailer = "${pkgs.msmtp}/bin/msmtp";
    };
  };

  environment.systemPackages = with pkgs; [
    nvme-cli
    smartmontools
    wget
  ];

  # never change
  system.stateVersion = "26.05";
}
