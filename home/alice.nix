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

  # zsh config settings
  programs.zsh = {
    enable = true;
    oh-my-zsh = {
      enable = true;
      theme = "lambda";
    };
    shellAliases = {
      pt = "ssh pharika";
      et = "ssh ephara";
    };
    initContent = lib.mkMerge [
      (lib.mkBefore ''
        if [[ -z $TMUX && -z $SSH_CONNECTION && -t 0 && -t 1 ]] && (( $+commands[tmux] )); then
          tmux new -A -s main && exit
        fi
      '')
      ''
        _reset_term_modes() {
          printf '\e[?1000l\e[?1002l\e[?1003l\e[?1005l\e[?1006l\e[?1015l\e[?1004l\e[<99u'
        }
        autoload -Uz add-zsh-hook
        add-zsh-hook precmd _reset_term_modes
      ''
    ];
  };

  # tmux config settings
  programs.tmux = {
    enable = true;
    prefix = "C-b";
    keyMode = "vi";
    escapeTime = 10;
    mouse = true;
    historyLimit = 50000;
    baseIndex = 1;
    focusEvents = true;
    terminal = "tmux-256color";
    extraConfig = ''
      # true color
      set -as terminal-features ",*:RGB"
      # Shift+Enter = new line in Claude prompt
      set -s extended-keys on
      set -as terminal-features ",*:extkeys"
      # let Claude notifications and titles through
      set -g allow-passthrough on
      # copy to the local clipboard (OSC 52), if the terminal supports it
      set -g set-clipboard on
      # copy mode keys
      bind -T copy-mode-vi v   send -X begin-selection
      bind -T copy-mode-vi C-v send -X rectangle-toggle
      bind -T copy-mode-vi y   send -X copy-selection-and-cancel
    '';
  };

  programs.git = {
    enable = true;
    ignores = [ "**/.claude/settings.local.json" ];
    settings = {
      user.name = "alicevoid";
      user.email = "amelia.pvc@gmail.com";
      pull.rebase = false;
      merge = {
        autoStash = true;
        conflictStyle = "zdiff3";
        tool = "nvimdiff";
      };
      mergetool.keepBackup = false;
      alias.up = "!git pull --no-edit -X theirs; git diff --name-only --diff-filter=U | grep -q . && git mergetool";
    };
  };

  # Ghostty: desktops only
  programs.ghostty = lib.mkIf osConfig.services.desktopManager.gnome.enable {
    enable = true;
    settings = {
      font-family = "Adwaita Mono";
      font-size = 11;
      theme = "light:Adwaita,dark:Adwaita Dark";
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
      kunoros = {
        hostname = "kunoros";
        user = "alice";
      };
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
