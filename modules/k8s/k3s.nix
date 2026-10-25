{ pkgs, ... }:


# k3s Cluster 
#   Currently designed for Single-node (see pharika in flake)  
#   State lives in /var/lib/rancher/k3s (persistent ext4 root, no extra config).

{

  # k3s 
  services.k3s = {
    enable = true;
    role = "server";
    
    # kubectl readable by non-root (SSH access)
    extraFlags = [
      "--write-kubeconfig-mode=0644"
      "--flannel-backend=none"
      "--disable-network-policy"
      "--disable-kube-proxy"
      "--disable=servicelb"
      "--disable=traefik"
    ];
  };

  # Firewall (disabled in server.nix; these rules apply if it is turned on)
  networking.firewall = {
    allowedTCPPorts = [
      6443 # Kubernetes API server
      80 # Gateway API (Cilium Envoy, HTTP)
      443 # Gateway API (Cilium Envoy, HTTPS)
    ];
  };

  # Environment pkgs
  environment.systemPackages = with pkgs; [
    kubectl
    kubernetes-helm
    k9s
  ];
  environment.shellAliases.k = "kubectl";

  # So standalone kubectl/k9s/helm find the cluster automatically.
  environment.variables.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";

  # In-cluster DNS override:
  #   pods resolve *.pvc.tools -> pharika's LAN IP (not the WAN IP), else app-to-app
  #   calls hairpin and time out. k3s folds any *.server key here into CoreDNS.
  services.k3s.manifests.coredns-custom.content = {
    apiVersion = "v1";
    kind = "ConfigMap";
    metadata = {
      name = "coredns-custom";
      namespace = "kube-system";
    };
    data."pvc-tools.server" = ''
      pvc.tools:53 {
        hosts {
          10.0.0.141 auth.pvc.tools memos.pvc.tools karakeep.pvc.tools grafana.pvc.tools hubble.pvc.tools
          fallthrough
        }
        forward . /etc/resolv.conf
      }
    '';
  };
}
