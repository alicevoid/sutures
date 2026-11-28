{
  pkgs,
  ...
}:

# Usage: pinball [table]
# Force a monitor: VPX_LAYOUT_OUTPUT=eDP-1 pinball
{
  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "pinball";
      runtimeInputs = with pkgs; [
        python3
        xrandr
      ];
      text = ''
        exec python3 ${./vpx-layout.py} \
          nix --extra-experimental-features 'nix-command flakes' \
          run github:haylinmoore/pinball.nix -- "$@"
      '';
    })
  ];
}
