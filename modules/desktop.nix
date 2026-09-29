{
  config,
  pkgs,
  ...
}:

# Desktop Modules:
#   For computers without touchpads and built-in monitors

{
  # Gnome
  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # keyd 
  #        caps -> escape 
  #   alt+prtsc -> flameshot
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

  # ...Other 
  services.flatpak.enable = true;
  gtk.iconCache.enable = true;
}
