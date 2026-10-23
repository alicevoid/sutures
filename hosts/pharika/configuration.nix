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

  # never change
  system.stateVersion = "26.05";
}
