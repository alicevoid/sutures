{ pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # boot
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # host
  networking.hostName = "pharika";
  time.timeZone = "America/Los_Angeles";
  i18n.defaultLocale = "en_US.UTF-8";

  # console
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
  };

  # wifi NetworkManager
  networking.networkmanager.enable = true;
  # networking.networkmanager.unmanaged = [ "eno2" ];

  # static ethernet
  # networking.interfaces.eno2.ipv4.addresses = [{
  #   address = "10.0.0.3";
  #   prefixLength = 24;
  # }];
  # networking.defaultGateway = {
  #   address = "10.0.0.1";
  #   interface = "eno2";
  # };
  # networking.nameservers = [ "1.1.1.1" "9.9.9.9" ];

  # firewall
  networking.firewall.enable = true;

  # mdns -> pharika.local
  services.avahi = {
    enable = true;
    openFirewall = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
    };
  };

  # nix daemon
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.auto-optimise-store = true;
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # user
  users.users.alice = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    openssh.authorizedKeys.keyFiles = [ ./keys/athreos.pub ];
  };

  # ssh
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # packages
  environment.systemPackages = with pkgs; [
    git
    vim
    curl
    pciutils
    usbutils
    k3s
  ];

  # ssd trim
  services.fstrim.enable = true;

  # never change
  system.stateVersion = "26.05";
}
