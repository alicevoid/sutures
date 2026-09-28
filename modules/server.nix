{
  config,
  pkgs,
  ...
}:

# Server class - headless base. No desktop, no audio.
# Applied to pharika.
{
  # SSH (hardened: keys only)
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # Firewall on by default for servers
  networking.firewall.enable = true;

  # Advertise this host over mDNS (base avahi is in common.nix) so the
  # laptops can reach it as <hostname>.local.
  services.avahi = {
    openFirewall = true;
    publish = {
      enable = true;
      addresses = true;
    };
  };

  # Console (headless TTY)
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
  };

  # Nix store hygiene — automatic GC + store optimisation
  nix.settings.auto-optimise-store = true;
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # SSD trim
  services.fstrim.enable = true;
}
