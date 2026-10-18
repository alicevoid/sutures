{ pkgs, ... }:

# Cilium: CNI, kube-proxy replacement, and the Gateway API implementation.
#   Replaces flannel, servicelb and Traefik (disabled in k3s.nix). Routes live in staples.

let
  gatewayApiVersion = "v1.6.3";

  gatewayApiCrds =
    pkgs.runCommand "gateway-api-${gatewayApiVersion}-experimental-crds.yaml"
      {
        nativeBuildInputs = [ pkgs.yq-go ];
        src = pkgs.fetchurl {
          url = "https://github.com/kubernetes-sigs/gateway-api/releases/download/${gatewayApiVersion}/experimental-install.yaml";
          hash = "sha256-cvVJ/1dBbi4QhcW+Fxj1+GEIqnWsObS8J8HHrvFJcSc=";
        };
      }
      ''
        yq 'select(.kind == "CustomResourceDefinition")' $src > $out
      '';
in
{
  environment.systemPackages = with pkgs; [
    cilium-cli
    hubble
  ];

  services.k3s.manifests.gateway-api-crds.source = gatewayApiCrds;

  services.k3s.autoDeployCharts.cilium = {
    repo = "https://helm.cilium.io";
    name = "cilium";
    version = "1.20.3";
    hash = "sha256-CAWlJzEYxDbJdyu5Vm2H7FWNiyXMLOXcMpGOzdNvLHw=";
    targetNamespace = "kube-system";
    extraFieldDefinitions.spec.bootstrap = true;

    values = {
      k8sServiceHost = "127.0.0.1";
      k8sServicePort = 6444;
      kubeProxyReplacement = true;

      ipam.mode = "kubernetes";
      routingMode = "tunnel";
      tunnelProtocol = "vxlan";
      devices = [ "eno2" ];

      cni = {
        binPath = "/var/lib/rancher/k3s/data/cni";
        confPath = "/var/lib/rancher/k3s/agent/etc/cni/net.d";
      };

      operator = {
        replicas = 1;
        prometheus.serviceMonitor.enabled = true;
        dashboards = {
          enabled = true;
          namespace = "monitoring";
        };
      };

      gatewayAPI = {
        enabled = true;
        gatewayClass.create = "true";
        hostNetwork = {
          enabled = true;
          nodes.matchLabels."kubernetes.io/hostname" = "pharika";
        };
      };

      envoy = {
        prometheus.serviceMonitor.enabled = true;
        securityContext.capabilities = {
          keepCapNetBindService = true;
          envoy = [
            "NET_ADMIN"
            "SYS_ADMIN"
            "NET_BIND_SERVICE"
          ];
        };
      };

      prometheus = {
        enabled = true;
        serviceMonitor.enabled = true;
      };

      dashboards = {
        enabled = true;
        namespace = "monitoring";
      };

      hubble = {
        relay.enabled = true;
        ui.enabled = true;
        metrics = {
          enabled = [
            "dns"
            "drop"
            "tcp"
            "flow"
            "httpV2"
          ];
          serviceMonitor.enabled = true;
          dashboards = {
            enabled = true;
            namespace = "monitoring";
          };
        };
      };
    };
  };
}
