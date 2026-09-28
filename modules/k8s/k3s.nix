{ pkgs, ... }:

# Single-node k3s cluster (control-plane + workloads on one box).
# Imported via modules/k8s/default.nix (wired to pharika in flake.nix).
# State lives in /var/lib/rancher/k3s (persistent ext4 root, no extra config).
{
  services.k3s = {
    enable = true;
    role = "server";
    # Make the kubeconfig readable by non-root so `kubectl` works over SSH
    # without sudo. Fine on a single-user homelab box.
    extraFlags = [ "--write-kubeconfig-mode=0644" ];
  };

  # server.nix already sets networking.firewall.enable = true (lists merge).
  networking.firewall = {
    # Trust the CNI bridge so pods can reach the API server and CoreDNS.
    # Skipping this is the classic "DNS doesn't work inside pods" gotcha.
    trustedInterfaces = [ "cni0" ];
    allowedTCPPorts = [
      6443 # Kubernetes API server
      80 # Traefik ingress (HTTP) — Grafana etc.
      443 # Traefik ingress (HTTPS)
    ];
  };

  # On-box admin tooling. `services.k3s` already puts the bundled `k3s`
  # (and `k3s kubectl`) on PATH; these are the friendlier standalone tools.
  environment.systemPackages = with pkgs; [
    kubectl
    kubernetes-helm
    k9s
  ];

  # So standalone kubectl/k9s/helm find the cluster automatically.
  # (Applies to new login shells — reconnect SSH after the first switch.)
  environment.variables.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
}
