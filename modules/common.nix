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
    btop
    claude-code
    curl
    dig
    ffmpeg
    findutils
    fzf
    gh
    ghostty.terminfo # lets ghostty ssh in
    git
    git-extras
    pciutils
    pngquant
    python3
    ripgrep
    tmux
    tldr
    unzip
    usbutils
    vim
  ];

  # TLS trust: eMudhra CA key compromise (Oct 2026, Mozilla bug 2083449)
  #   NOTE: Temporary. Removes the emSign roots from the system CA bundle.
  #   NOTE: G3 anchors the compromised intermediates. C1 and C3 follow Mozilla bug 2083709.
  #   TODO: Remove this block when nixpkgs cacert is 3.131.1 or later.
  security.pki.caCertificateBlacklist = [
    "emSign ECC Root CA - G3"
    "emSign ECC Root CA - C3"
    "emSign Root CA - C1"
  ];

  # Zsh
  programs.zsh.enable = true;

  # Nix Helper 
  programs.nh = {
    enable = true;
    flake = "/home/alice/sutures";
  };

  # firefox settings
  programs.firefox = {
    enable = true;
    policies.DNSOverHTTPS.ExcludedDomains = [ "pvc.tools" ];
  };
}
