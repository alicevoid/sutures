{ pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # host
  networking.hostName = "pharika";

  # Static Ethernet Stuff (not needed? lol)
  # networking.networkmanager.unmanaged = [ "eno2" ];
  # networking.interfaces.eno2.ipv4.addresses = [{
  #   address = "10.0.0.3";
  #   prefixLength = 24;
  # }];
  # networking.defaultGateway = {
  #   address = "10.0.0.1";
  #   interface = "eno2";
  # };
  # networking.nameservers = [ "1.1.1.1" "9.9.9.9" ];

  # SSH keyFiles
  users.users.alice.openssh.authorizedKeys.keyFiles = [
    ./keys/athreos.pub
    ./keys/kunoros.pub
    ./keys/ephara.pub # agents on ephara read the mindvirus vault over SSH
  ];

  users.users.alice.linger = true;

  # Split-horizon DNS for *.pvc.tools:
  #   LAN devices resolve pvc.tools -> pharika (not the WAN IP) so they skip the hairpin.
  #   host-level on purpose: house DNS shouldn't die with k3s. Set per device (the Xfinity gateway can't hand it out).
  services.dnsmasq = {
    enable = true;
    resolveLocalQueries = false; # Tailscale owns pharika's own resolv.conf; leave it be
    settings = {
      address = [ "/pvc.tools/10.0.0.141" ]; # pvc.tools + all subdomains -> LAN IP
      server = [
        "1.1.1.1"
        "9.9.9.9"
      ]; # upstream for everything else
      no-resolv = true;
      # LAN iface only; bind-dynamic copes with eno2's DHCP addr at boot
      interface = "br0";
      bind-dynamic = true;
      domain-needed = true;
      bogus-priv = true;
    };
  };

  systemd.services.dnsmasq-tailnet = {
    description = "dnsmasq for tailnet split DNS (*.pvc.tools)";
    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.dnsmasq}/bin/dnsmasq -k --user=dnsmasq -C ${pkgs.writeText "dnsmasq-tailnet.conf" ''
        interface=tailscale0
        except-interface=lo
        bind-dynamic
        no-resolv
        no-hosts
        pid-file=
        local=/pvc.tools/
        address=/pvc.tools/100.100.169.0
      ''}";
      Restart = "on-failure";
    };
  };

  # open :53 (dnsmasq listens on eno2 + tailscale0)
  networking.firewall.allowedUDPPorts = [ 53 ];
  networking.firewall.allowedTCPPorts = [ 53 ];

  # NOTE(diamond): enslave the ethernet interface, so that the VM bridge interface
  # becomes the master which dominates all virtual machines.
  networking.bridges.br0.interfaces = [ "eno2" ];
  networking.interfaces.br0.macAddress = "8c:16:45:e1:56:e7";
  networking.interfaces.br0.ipv4.addresses = [
    {
      address = "10.0.0.141";
      prefixLength = 24;
    }
  ];
  networking.interfaces.eno2.useDHCP = false;
  networking.defaultGateway = {
    address = "10.0.0.1";
    interface = "br0";
  };
  networking.nameservers = [ "10.0.0.1" ];
  networking.dhcpcd.extraConfig = "clientid";

  # Nightly PVC backup to ephara's ZFS pool (02:30). ephara snapshots it at 04:00 (sanoid).
  #   NFS export /data/backups/pharika (no_root_squash for this host only, so file owners survive).
  #   SQLite files get a consistent .backup copy first. A raw copy of a live SQLite file can be torn.
  #   Skipped: prometheus, loki, alertmanager (metrics and logs, rolled over in days) and the old
  #   traefik PVC. Restore: copy a PVC folder back with the app scaled to 0, or use the sqlite/ dump.
  #   Also copies /srv/vaults/mindvirus (the vault lives only on pharika; ephara reads it over SSH).
  boot.supportedFilesystems = [ "nfs" ];
  fileSystems."/mnt/ephara-backups" = {
    device = "10.0.0.65:/data/backups/pharika";
    fsType = "nfs";
    options = [
      "nfsvers=4.2"
      "hard"
      "noauto"
      "x-systemd.automount"
      "x-systemd.idle-timeout=600"
      "x-systemd.mount-timeout=30"
      "nofail"
      "_netdev"
    ];
  };

  systemd.services.pvc-backup = {
    description = "Back up k3s PVCs and cluster state to ephara";
    path = [
      pkgs.rsync
      pkgs.sqlite
      pkgs.util-linux
      pkgs.findutils
      pkgs.coreutils
    ];
    serviceConfig.Type = "oneshot";
    script = ''
      set -euo pipefail
      dest=/mnt/ephara-backups
      work=/var/tmp/pvc-backup
      storage=/var/lib/rancher/k3s/storage

      # Never write to the local folder: the NFS mount must be there.
      ls "$dest" >/dev/null   # triggers the automount
      #   -t nfs4: findmnt also lists the autofs mount on the same path
      findmnt -n -t nfs4 --mountpoint "$dest" >/dev/null || { echo "$dest is not the NFS mount. Stop."; exit 1; }

      # 1. Consistent copies of every SQLite database (PVCs and the k3s datastore)
      rm -rf "$work"; mkdir -p "$work/sqlite"
      find "$storage" /var/lib/rancher/k3s/server/db -type f \( -name '*.db' -o -name '*.sqlite' -o -name '*.sqlite3' \) |
        while read -r f; do
          [ "$(head -c 15 "$f")" = "SQLite format 3" ] || continue
          rel=''${f#/var/lib/rancher/k3s/}
          mkdir -p "$work/sqlite/$(dirname "$rel")"
          sqlite3 "$f" ".backup '$work/sqlite/$rel'"
        done

      # 2. The PVC folders, as they are
      rsync -aH --numeric-ids --delete \
        --exclude '*_monitoring_prometheus-*' \
        --exclude '*_monitoring_storage-loki-*' \
        --exclude '*_monitoring_alertmanager-*' \
        --exclude '*_kube-system_traefik' \
        "$storage/" "$dest/storage/"

      # 3. The SQLite copies and the cluster token (needed to restore the datastore)
      rsync -a --delete "$work/sqlite/" "$dest/sqlite/"
      install -D -m 600 /var/lib/rancher/k3s/server/token "$dest/k3s/token"

      # 4. The mindvirus vault as plain Markdown (livesync-bridge's copy, easy to restore)
      rsync -a --delete /srv/vaults/mindvirus/ "$dest/vaults/mindvirus/"

      rm -rf "$work"
      date -Is > "$dest/LAST_SUCCESS"
    '';
  };
  systemd.timers.pvc-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "02:30";
      Persistent = true;
    };
  };

  # never change
  system.stateVersion = "26.05";
}
