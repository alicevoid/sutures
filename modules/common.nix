{
  config,
  pkgs,
  inputs,
  ...
}:

# Truly shared configuration — applied to EVERY host (laptops + servers).
# Anything graphical/desktop-only lives in desktop.nix; server-only in server.nix.
{
  # Experimental Features (Flakes)
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Bootloader (all hosts are systemd-boot / EFI)
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.configurationLimit = 3;

  # Networking
  networking.networkmanager.enable = true;

  # Tailscale (system daemon; run `sudo tailscale up` once to authenticate)
  services.tailscale.enable = true;

  # mDNS resolution: every host can resolve *.local (e.g. pharika.local).
  # Servers additionally *publish* their name — see server.nix.
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

  # User (base identity — shared everywhere)
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
    git-extras
    pciutils
    usbutils
  ];

  # Zsh (enable as system shell; user config owned by home-manager)
  programs.zsh.enable = true;

  # Nix Helper (nh)
  programs.nh = {
    enable = true;
    flake = "/home/alice/Documents/sutures";
  };
}
