{ ... }:

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
  users.users.alice.openssh.authorizedKeys.keyFiles = [ ./keys/athreos.pub ];

  # Split-horizon DNS for *.pvc.tools:
  #   LAN devices resolve pvc.tools -> pharika (not the WAN IP) so they skip the hairpin.
  #   host-level on purpose — house DNS shouldn't die with k3s. hand it out via DHCP.
  services.dnsmasq = {
    enable = true;
    resolveLocalQueries = false; # Tailscale owns pharika's own resolv.conf; leave it be
    settings = {
      address = [ "/pvc.tools/10.0.0.141" ]; # pvc.tools + all subdomains -> LAN IP
      server = [ "1.1.1.1" "9.9.9.9" ]; # upstream for everything else
      no-resolv = true;
      # LAN iface only; bind-dynamic copes with eno2's DHCP addr at boot
      interface = "eno2";
      bind-dynamic = true;
      domain-needed = true;
      bogus-priv = true;
    };
  };

  # open :53 (dnsmasq listens on eno2 only)
  networking.firewall.allowedUDPPorts = [ 53 ];
  networking.firewall.allowedTCPPorts = [ 53 ];

  # never change
  system.stateVersion = "26.05";
}
