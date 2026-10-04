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

  # Pin the *.pvc.tools apps to pharika's TAILNET IP so my laptops reach them
  # over the encrypted tailnet instead of the public WAN IP. This dodges the
  # Xfinity NAT-hairpin at home AND works identically when roaming. /etc/hosts
  # is consulted before any resolver (nsswitch `files` ahead of `dns`), so this
  # wins over Tailscale MagicDNS and is immune to the DHCP/MagicDNS dependency
  # chain. (The LAN-wide dnsmasq split-horizon lives on pharika for non-tailnet
  # devices: hosts/pharika/configuration.nix.)
  networking.hosts."100.100.169.0" = [
    "auth.pvc.tools"
    "memos.pvc.tools"
    "karakeep.pvc.tools"
    "grafana.pvc.tools"
    "traefik.pvc.tools"
  ];

  # TODO:
  #   look into power mgmt / TLP defaults
  #   look into touchpad tweaks... if you swing that way... pervert
  # (e.g. power management, tlp, backlight, touchpad tweaks).
}
