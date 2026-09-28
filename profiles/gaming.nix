{
  config,
  pkgs,
  ...
}:

# Gaming profile — a SPECIALISATION, not an always-on module.
# Including this file does NOT enable Steam; it builds a "gaming" variant of
# the system that you switch into on demand:
#
#   activate:   sudo /run/current-system/specialisation/gaming/bin/switch-to-configuration switch
#   deactivate: sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch
#
# Steam needs system-level plumbing (FHS env + 32-bit GPU drivers), which is
# why it lives here rather than an ephemeral `nix shell`.
{
  specialisation.gaming.configuration = {
    programs.steam.enable = true;
    hardware.graphics.enable32Bit = true;

    # Streaming/recording, available while gaming is active.
    environment.systemPackages = with pkgs; [
      obs-studio
    ];
  };
}
