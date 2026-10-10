{
  config,
  pkgs,
  inputs,
  ...
}:

# Common Modules: 
#   Every Server should get these

{
  # Experimental Features 
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Bootloader 
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.configurationLimit = 3;

  # Networking
  networking.networkmanager.enable = true;

  # Tailscale 
  services.tailscale.enable = true;

  # mDNS local-network resolution:
  #   NOTE: Servers publish their names (see server.nix)

  services.avahi = {
    enable = true;
    nssmdns4 = true;
  };

  # Locale & timezone
  time.timeZone = "America/Los_Angeles";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # We're all just different flavors of alice :3c  
  users.users.alice = {
    isNormalUser = true;
    description = "alice";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    packages = with pkgs; [ ];
    shell = pkgs.zsh;
  };

  # Packages
  nixpkgs.config.allowUnfree = true;
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    python3
    gh
    git
    git-extras
    pciutils
    usbutils
  ];

  # Zsh 
  programs.zsh.enable = true;

  # Nix Helper 
  programs.nh = {
    enable = true;
    flake = "/home/alice/sutures";
  };
}
