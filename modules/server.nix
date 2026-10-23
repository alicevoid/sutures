{
  config,
  pkgs,
  ...
}:

# Server Modules: 
#   ALL servers get these 
#   ...WARNING: this is a BAD IDEA ZONE! brought2u by yours truly

{
  # SSH
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # Firewall
  networking.firewall.enable = false;

  # mDNS publishing:
  #   NOTE: This is enabled already (see common.nix)

  services.avahi = {
    openFirewall = true;
    publish = {
      enable = true;
      addresses = true;
    };
  };

  # Console 
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
  };

  # Storage Cleanup
  nix.settings.auto-optimise-store = true;
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # SSD 
  services.fstrim.enable = true;

  virtualisation.libvirtd = {
    enable = true;
    dbus.enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = true;
      swtpm.enable = true;
    };
  };

  services.cockpit = {
    enable = true;
    port = 8010;
    plugins = with pkgs; [
      cockpit-machines
      cockpit-zfs
    ];
    allowed-origins = [ "*" ];
    settings.WebService = {
      ProtocolHeader = "X-Forwarded-Proto";
      ForwardedForHeader = "X-Forwarded-For";
      AllowUnencrypted = true;
    };
  };

  # Fix libvirt-dbus not having access to libvirtd.
  # https://github.com/cockpit-project/cockpit-machines/issues/832
  # https://search.nixos.org/options?channel=26.05&query=libvirt&type=options#show=option%253Avirtualisation.libvirtd.enable
  # https://github.com/NixOS/nixpkgs/blob/cd4ea8d57de16f4810bc5f14207bac45fbf19f67/nixos/modules/virtualisation/libvirtd.nix#L448
  users.users.libvirtdbus.extraGroups = [ "libvirtd" ];

  environment.systemPackages = with pkgs; [
    virt-manager
  ];

}
