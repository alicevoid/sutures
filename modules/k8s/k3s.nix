{ pkgs, ... }:


# k3s Cluster 
#   Currently designed for Single-node (see pharika in flake)  
#   State lives in /var/lib/rancher/k3s (persistent ext4 root, no extra config).

{

  # k3s 
  services.k3s = {
    enable = true;
    role = "server";
    
    # `kubectl` readable by non-root for SSH access
    extraFlags = [ "--write-kubeconfig-mode=0644" ]; # ... I hope this doesn't have any unintended consequences hhahaaaa....
  };

  # Firewall (enabled in server.nix)
  networking.firewall = {

    # Trust the CNI bridge so pods can reach the API server and CoreDNS.
    trustedInterfaces = [ "cni0" ];
    allowedTCPPorts = [
      6443 # Kubernetes API server
      80 # Traefik ingress (HTTP) 
      443 # Traefik ingress (HTTPS)
    ];
  };

  # Environment pkgs
  environment.systemPackages = with pkgs; [
    kubectl
    kubernetes-helm
    k9s
  ];

  # So standalone kubectl/k9s/helm find the cluster automatically.
  environment.variables.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";

  # In-cluster split-horizon DNS (the third horizon, after laptop /etc/hosts and
  # the LAN dnsmasq). Pods must resolve *.pvc.tools to pharika's LAN IP, NOT the
  # public WAN IP — otherwise server-side calls between apps NAT-hairpin-fail from
  # inside. Concretely: OIDC back-channel, e.g. Grafana's pod POSTing to
  # https://auth.pvc.tools/api/oidc/token, times out against the WAN IP.
  #   k3s imports any `*.server` key in the `coredns-custom` ConfigMap as an extra
  #   CoreDNS server block. 10.0.0.141 = pharika eno2, where Traefik serves :443
  #   with the valid wildcard cert (same target the laptop pins + LAN dnsmasq use).
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
          10.0.0.141 auth.pvc.tools memos.pvc.tools karakeep.pvc.tools grafana.pvc.tools traefik.pvc.tools
          fallthrough
        }
        forward . /etc/resolv.conf
      }
    '';
  };
}
