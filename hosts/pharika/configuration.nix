{ pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  networking.hostName = "pharika";

  users.users.alice.openssh.authorizedKeys.keyFiles = [
    ./keys/athreos.pub
    ./keys/kunoros.pub
    ./keys/ephara.pub # agents on ephara read the mindvirus vault over SSH
  ];

  users.users.alice.linger = true;

  # Split-horizon DNS: *.pvc.tools resolves to pharika, so devices skip the router's NAT hairpin.
  #   On the host, so house DNS does not depend on k3s. Each device sets it by hand, because the
  #   Xfinity gateway cannot hand out a DNS server. LAN here; the tailnet instance is below.
  services.dnsmasq = {
    enable = true;
    resolveLocalQueries = false; # Tailscale owns pharika's own resolv.conf; leave it be
    settings = {
      address = [ "/pvc.tools/10.0.0.141" ];
      server = [
        "1.1.1.1"
        "9.9.9.9"
      ];
      no-resolv = true;
      # bind-dynamic: binds when the interface comes up
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

  # The firewall is off (server.nix); these apply if it is turned on.
  networking.firewall.allowedUDPPorts = [ 53 ];
  networking.firewall.allowedTCPPorts = [ 53 ];

  # LAN on bridge br0 with a static IP. Same name as on ephara, so Cilium's devices = [ "br0" ]
  #   fits both nodes.
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

  # Nightly backup to ephara's pool: PVCs, the k3s datastore and token, and the mindvirus vault.
  #   SQLite files get a .backup copy first, because a raw copy of a live SQLite file can be torn.
  #   Metrics and logs are skipped. Restore: copy a PVC folder back with the app scaled to 0, or
  #   use the sqlite/ dump.
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

      # Stop unless the NFS mount is there. ls triggers the automount; -t nfs4 skips the autofs entry.
      ls "$dest" >/dev/null
      findmnt -n -t nfs4 --mountpoint "$dest" >/dev/null || { echo "$dest is not the NFS mount. Stop."; exit 1; }

      # 1. SQLite copies (PVCs and the k3s datastore)
      rm -rf "$work"; mkdir -p "$work/sqlite"
      find "$storage" /var/lib/rancher/k3s/server/db -type f \( -name '*.db' -o -name '*.sqlite' -o -name '*.sqlite3' \) |
        while read -r f; do
          [ "$(head -c 15 "$f")" = "SQLite format 3" ] || continue
          rel=''${f#/var/lib/rancher/k3s/}
          mkdir -p "$work/sqlite/$(dirname "$rel")"
          sqlite3 "$f" ".backup '$work/sqlite/$rel'"
        done

      # 2. PVC folders
      rsync -aH --numeric-ids --delete \
        --exclude '*_monitoring_prometheus-*' \
        --exclude '*_monitoring_storage-loki-*' \
        --exclude '*_monitoring_alertmanager-*' \
        "$storage/" "$dest/storage/"

      # 3. SQLite copies and the cluster token (needed to restore the datastore)
      rsync -a --delete "$work/sqlite/" "$dest/sqlite/"
      install -D -m 600 /var/lib/rancher/k3s/server/token "$dest/k3s/token"

      # 4. The mindvirus vault as plain Markdown
      mkdir -p "$dest/vaults"
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
