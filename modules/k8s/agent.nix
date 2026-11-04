{ config, ... }:

# k3s agent. Never import the server-only modules (default.nix) here.
#   The join token (pharika's /var/lib/rancher/k3s/server/agent-token) comes from secrets/ephara.yaml.

{
  imports = [ ./node.nix ];

  sops.secrets.k3s-agent-token.sopsFile = ../../secrets/ephara.yaml;

  services.k3s = {
    enable = true;
    role = "agent";
    serverAddr = "https://10.0.0.141:6443";
    tokenFile = config.sops.secrets.k3s-agent-token.path;
    extraFlags = [
      "--node-ip=10.0.0.65"
      "--node-label=pvc.tools/storage=true"
    ];
  };
}
