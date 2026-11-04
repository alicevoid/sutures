{ ... }:

# k3s agent. Never import the server-only modules (default.nix) here.
#   The join token is a root-only file copied by hand from pharika's
#   /var/lib/rancher/k3s/server/agent-token.

{
  imports = [ ./node.nix ];

  services.k3s = {
    enable = true;
    role = "agent";
    serverAddr = "https://10.0.0.141:6443";
    tokenFile = "/var/lib/rancher/k3s/agent-token";
    extraFlags = [
      "--node-ip=10.0.0.65"
      "--node-label=pvc.tools/storage=true"
    ];
  };
}
