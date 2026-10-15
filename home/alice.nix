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

  programs.zsh = {
    enable = true;
    oh-my-zsh = {
      enable = true;
      theme = "lambda";
    };
    # pharika: pt = tmux session "main", pa = claude agent view
    shellAliases = {
      pt = "ssh -t pharika tmux new -A -s main";
      pa = "ssh -t pharika claude agents";
    };
  };

  # tmux config settings
  programs.tmux = {
    enable = true;
    prefix = "C-Space";
    escapeTime = 10;
    mouse = true;
    historyLimit = 50000;
    baseIndex = 1;
    focusEvents = true;
    terminal = "tmux-256color";
    extraConfig = ''
      # true color
      set -as terminal-features ",*:RGB"
      # Shift+Enter = new line in the Claude prompt
      set -s extended-keys on
      set -as terminal-features ",*:extkeys"
      # let Claude notifications and titles through
      set -g allow-passthrough on
      # copy to the local clipboard (OSC 52), if the terminal supports it
      set -g set-clipboard on
    '';
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
