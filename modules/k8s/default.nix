{ ... }:

# All Kubernetes (k3s) config for pharika lives under modules/k8s/.
# Wired into the `pharika` system in flake.nix as `./modules/k8s`.
{
  imports = [
    ./k3s.nix # single-node cluster
    ./observability.nix # LGTM stack (Loki/Grafana/Tempo/Metrics)
  ];
}
