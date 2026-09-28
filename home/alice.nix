{
  pkgs,
  config,
  inputs,
  ...
}:

{
  imports = [ ./modules/nixvim ];

  home.username = "alice";
  home.homeDirectory = "/home/alice";
  home.stateVersion = "25.05";

  home.packages = with pkgs; [
    firefox
    vscode
    obsidian
    git
    git-extras
    gh
    claude-code
    python3
    wl-clipboard
    filezilla
    wireshark
    unzip
    ffmpeg
    pngquant
    htop
    zoom-us
    grim
  ];

  programs.zsh = {
    enable = true;
    oh-my-zsh = {
      enable = true;
      theme = "lambda";
    };
  };

  services.flameshot = {
    enable = true;
    settings.General = {
      showStartupLaunchMessage = false;
    };
  };

  # SSH client aliases.
  # Uses Tailscale MagicDNS names (lowercased tailnet names, NOT LAN IPs), so
  # nothing here leaks network topology in this public repo. These `Host`
  # entries also give `ssh <tab>` completion for each machine.
  programs.ssh = {
    enable = true;
    matchBlocks = {
      pharika = {
        hostname = "pharika";
        user = "alice";
      };
      athreos = {
        hostname = "athreos";
        user = "alice";
      };
      # kunoros not yet on the tailnet — add once it joins.
    };
  };

  programs.home-manager.enable = true;
}
