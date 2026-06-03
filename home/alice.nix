{
  pkgs,
  config,
  inputs,
  ...
}:

{
  home.username = "alice";
  home.homeDirectory = "/home/alice";
  home.stateVersion = "25.05";

  # User packages (moved from environment.systemPackages / users.users.alice.packages)
  home.packages = with pkgs; [
    neovim
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
  ];

  # Zsh customization lives here; programs.zsh.enable stays in common.nix
  programs.zsh = {
    enable = true;
    oh-my-zsh = {
      enable = true;
      theme = "lambda";
    };
    # future: shellAliases, initExtra for your .zshrc stuff, etc.
  };

  # NVChad config symlink — add this once you move your lua files into the repo
  xdg.configFile."nvim".source =
    config.lib.file.mkOutOfStoreSymlink "/home/alice/Documents/nix-config/home/modules/nvim";

  programs.home-manager.enable = true;
}
