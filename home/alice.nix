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
  ];

  programs.zsh = {
    enable = true;
    oh-my-zsh = {
      enable = true;
      theme = "lambda";
    };
  };

  programs.home-manager.enable = true;
}
