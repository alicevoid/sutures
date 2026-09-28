{
  config,
  pkgs,
  ...
}:

# Laptop class — a graphical desktop plus laptop-specific bits.
# Applied to athreos and kunoros.
{
  imports = [ ./desktop.nix ];

  # Laptop-only configuration goes here going forward
  # (e.g. power management, tlp, backlight, touchpad tweaks).
}
