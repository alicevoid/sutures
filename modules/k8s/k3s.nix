{ pkgs, ... }:


# k3s server (pharika). Agents use agent.nix.

{

  services.k3s = {
    enable = true;
    role = "server";
    
    extraFlags = [
      "--write-kubeconfig-mode=0644"
      # The wired address. Without it k3s can pick the Wi-Fi address.
      "--node-ip=10.0.0.141"
      "--flannel-backend=none"
      "--disable-network-policy"
      "--disable-kube-proxy"
      "--disable=servicelb"
      "--disable=traefik"
    ];
  };

  # The firewall is off (server.nix); these apply if it is turned on.
  networking.firewall = {
    allowedTCPPorts = [
      6443 # Kubernetes API server
      80 # Gateway API (Cilium Envoy, HTTP)
      443 # Gateway API (Cilium Envoy, HTTPS)
    ];
  };

  environment.systemPackages = with pkgs; [
    kubectl
    kubernetes-helm
    k9s
  ];
  environment.shellAliases.k = "kubectl";

  environment.variables.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";

  # Pods resolve these *.pvc.tools names to pharika's LAN IP. Otherwise they get the WAN IP and
  #   app-to-app calls hang on the NAT hairpin. k3s loads any *.server key here into CoreDNS.
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
