{
  config,
  pkgs,
  ...
}:

# Gaming Profile
#   activate:   sudo /run/current-system/specialisation/gaming/bin/switch-to-configuration switch
#   deactivate: sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch
{
  specialisation.gaming.configuration = {
    
    # steam stuff
    programs.steam.enable = true;
    hardware.graphics.enable32Bit = true;

    # env pkgs
    environment.systemPackages = with pkgs; [
      obs-studio
    ];
  };
}
