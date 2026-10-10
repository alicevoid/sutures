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

  # pvc.tools apps -> pharika's tailnet IP
  #   so the laptops skip the Xfinity hairpin at home (and it works roaming too)
  #   /etc/hosts beats MagicDNS; non-tailnet devices get this via dnsmasq on pharika
  networking.hosts."100.100.169.0" = [
    "auth.pvc.tools"
    "memos.pvc.tools"
    "karakeep.pvc.tools"
    "grafana.pvc.tools"
    "traefik.pvc.tools"
    "argocd.pvc.tools"
  ];

  # TODO:
  #   look into power mgmt / TLP defaults
  #   look into touchpad tweaks... if you swing that way... pervert
  # (e.g. power management, tlp, backlight, touchpad tweaks).
}
