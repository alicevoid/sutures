{
  config,
  pkgs,
  inputs,
  ...
}:

{
  # Experimental Features (Flakes)
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

  # GNOME
  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # keyd
  services.keyd = {
    enable = true;
    keyboards = {
      default = {
        ids = [ "*" ];
        settings = {
          main = {
            capslock = "escape";
          };
        };
      };
    };
  };

  # Printing
  services.printing.enable = true;

  # Audio
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # User
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
    firefox
    vscode
    vim
    obsidian
    git
    git-extras
    gh
    claude-code
    python3
    nvchad
    wl-clipboard
    filezilla
    wireshark
    unzip
  ];

  # Misc
  services.flatpak.enable = true;
  gtk.iconCache.enable = true;

  # Zsh
  programs.zsh = {
    enable = true;
    ohMyZsh = {
      enable = true;
      theme = "lambda"; # default, we'll change this
    };
  };

  # nvchad setup
  nixpkgs.overlays = [
    (final: prev: {
      nvchad = inputs.nix4nvchad.packages."${pkgs.system}".nvchad;
    })
  ];

}
