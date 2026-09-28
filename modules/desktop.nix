{
  config,
  pkgs,
  ...
}:

# Graphical workstation base — GNOME desktop, audio, printing, screenshots.
# Imported by laptop.nix. Servers (server.nix) do NOT get this.
{
  # GNOME
  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # keyd — capslock->escape, and Alt+SysRq for a flameshot screenshot
  services.keyd = {
    enable = true;
    keyboards = {
      default = {
        ids = [ "*" ];
        settings = {
          main = {
            capslock = "escape";
          };
          alt = {
            sysrq = "command(systemd-run --user --machine=alice@.host --collect -- ${pkgs.flameshot}/bin/flameshot gui)";
          };
        };
      };
    };
  };

  # Printing
  services.printing.enable = true;

  # Audio
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Misc desktop
  services.flatpak.enable = true;
  gtk.iconCache.enable = true;
}
