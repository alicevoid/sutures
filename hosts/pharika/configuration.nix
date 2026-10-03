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

  # Split-horizon DNS for *.pvc.tools (kills the Xfinity NAT-hairpin).
  #   LAN clients that resolve pvc.tools to the PUBLIC WAN IP can't reach it
  #   from inside (Xfinity does no NAT loopback). So run a host-level resolver
  #   that answers pvc.tools -> pharika's LAN IP, and hand it to LAN clients via
  #   the gateway's DHCP DNS setting. External clients keep using public DNS ->
  #   the :443 port-forward, unchanged. (The laptops instead pin to pharika's
  #   tailnet IP in modules/laptop.nix, which is roam-proof and sidesteps this.)
  #
  #   Host-level, NOT a k8s pod on purpose: house DNS must survive k3s being down.
  #   Nothing else binds host :53 (CoreDNS is a cluster ClusterIP), so this is clean.
  services.dnsmasq = {
    enable = true;
    # Tailscale/MagicDNS owns pharika's own /etc/resolv.conf; leave it be.
    resolveLocalQueries = false;
    settings = {
      # pvc.tools AND every *.pvc.tools -> pharika's LAN IP.
      address = [ "/pvc.tools/10.0.0.141" ];
      # Upstream for everything else; don't read resolv.conf (points at MagicDNS).
      server = [ "1.1.1.1" "9.9.9.9" ];
      no-resolv = true;
      # Serve the LAN interface only. bind-dynamic tolerates eno2's DHCP address
      # appearing at boot and keeps this from being a wildcard open resolver
      # (the WAN forwards only :443 anyway).
      interface = "eno2";
      bind-dynamic = true;
      domain-needed = true;
      bogus-priv = true;
    };
  };

  # DNS on the firewall (dnsmasq itself only listens on eno2).
  networking.firewall.allowedUDPPorts = [ 53 ];
  networking.firewall.allowedTCPPorts = [ 53 ];

  # never change
  system.stateVersion = "26.05";
}
