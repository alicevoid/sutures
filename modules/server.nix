{
  config,
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

  # Firewall
  networking.firewall.enable = true;

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
