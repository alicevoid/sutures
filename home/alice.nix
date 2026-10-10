{
  pkgs,
  config,
  lib,
  osConfig,
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
    claude-code
    wl-clipboard
    filezilla
    wireshark
    unzip
    ffmpeg
    pngquant
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

  # SSH Client Aliases (Tailscale MagicDNS)
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
      # TODO: put kunoros on tailnet 
    };
  };

  # pharika only: a private kubeconfig whose context defaults to the argocd namespace, so
  # `argocd --core` (and kubectl) just work in any new shell. The system KUBECONFIG is
  # root-owned and namespace-less, which is what blocks core mode. Re-copied each rebuild,
  # so it also self-heals if the k3s client cert ever rotates.
  home.sessionVariables = lib.mkIf (osConfig.networking.hostName == "pharika") {
    KUBECONFIG = "${config.home.homeDirectory}/.kube/config";
  };
  home.activation.argocdKubeconfig = lib.mkIf (osConfig.networking.hostName == "pharika") (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ -f /etc/rancher/k3s/k3s.yaml ]; then
        $DRY_RUN_CMD install -Dm600 /etc/rancher/k3s/k3s.yaml "${config.home.homeDirectory}/.kube/config"
        $DRY_RUN_CMD ${pkgs.kubectl}/bin/kubectl --kubeconfig="${config.home.homeDirectory}/.kube/config" config set-context --current --namespace=argocd
      fi
    ''
  );

  programs.home-manager.enable = true;
}
