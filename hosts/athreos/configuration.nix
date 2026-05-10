{ config, pkgs, ... }:

{
  networking.hostName = "athreOS";
  system.stateVersion = "25.05";


  services.xserver.desktopManager.gnome.extraGSettingsOverrides = ''
    [org.gnome.mutter]
    experimental-features=['scale-monitor-framebuffer']
  '';
}
