{
  config,
  lib,
  pkgs,
  ...
}:

# Server Modules: 
#   ALL servers get these 
#   ...WARNING: this is a BAD IDEA ZONE! brought2u by yours truly

{
  # SSH
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # Firewall (nftables). Off by default. A host turns it on once its rules are tested, by setting
  #   both networking.firewall.enable and networking.nftables.enable.
  #   Never flush the whole ruleset: Cilium, kube and Tailscale keep their own tables.
  #   Reverse path "loose": "strict" drops Tailscale and Cilium traffic.
  #   tailscale0 is trusted: every tailnet device is Alice's.
  networking.firewall = {
    enable = lib.mkDefault false;
    checkReversePath = "loose";
    trustedInterfaces = [ "tailscale0" ];
  };
  networking.nftables.flushRuleset = false;
  services.tailscale.openFirewall = true;

  # mDNS publishing:
  #   NOTE: This is enabled already (see common.nix)

  services.avahi = {
    openFirewall = true;
    publish = {
      enable = true;
      addresses = true;
    };
  };

  # Console 
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
  };

  # Storage Cleanup
  nix.settings.auto-optimise-store = true;
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # SSD 
  services.fstrim.enable = true;
}
