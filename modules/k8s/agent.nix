{ ... }:

# k3s agent: a worker node that joins pharika's server.
#   Gets Cilium from the server (cluster-wide chart). Server-only parts (Cilium chart, Gateway API
#   CRDs, Argo bootstrap, coredns-custom) stay in default.nix and must never be imported here.
#   The join token is a root-only file copied by hand from pharika
#   (/var/lib/rancher/k3s/server/agent-token). It moves into SOPS with the other secrets.

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
