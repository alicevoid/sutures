{
  config,
  pkgs,
  ...
}:

# Laptop Modules: 
#   imports desktop stuff
#   laptop config stuff goes here if I ever actually care enough

{
  imports = [ ./desktop.nix ];

  # TODO:
  #   look into power mgmt / TLP defaults
  #   look into touchpad tweaks... if you swing that way... pervert
  # (e.g. power management, tlp, backlight, touchpad tweaks).
}
