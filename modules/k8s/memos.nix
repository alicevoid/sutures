{ ... }:

# Memos (http://pharika:5230)
#   ROUTING NOTE: the Grafana Ingress is host-less and owns "/" on Traefik's
#   :80, and Memos can't run under a subpath — so instead of an Ingress we give
#   Memos a LoadBalancer Service. k3s's built-in servicelb (klipper) binds that
#   port straight onto the host, so http://pharika:5230 hits it directly.
#   (Upgrade path later: give it a real hostname + Ingress once you set up
#   per-service DNS, then drop the open port.)

let
  ns = "memos";
  port = 5230;
in
{
  # Open the LoadBalancer port on the host (tailnet-reachable).
  networking.firewall.allowedTCPPorts = [ port ];

  services.k3s.manifests.memos.content = [
    {
      apiVersion = "v1";
      kind = "Namespace";
      metadata.name = ns;
    }

    {
      apiVersion = "v1";
      kind = "PersistentVolumeClaim";
      metadata = {
        name = "memos-data";
        namespace = ns;
      };
      spec = {
        accessModes = [ "ReadWriteOnce" ];
        storageClassName = "local-path";
        resources.requests.storage = "2Gi";
      };
    }

    {
      apiVersion = "apps/v1";
      kind = "Deployment";
      metadata = {
        name = "memos";
        namespace = ns;
      };
      spec = {
        replicas = 1;
        # Recreate (not RollingUpdate): the RWO volume can't attach to two
        # pods at once, so tear the old one down before starting the new one.
        strategy.type = "Recreate";
        selector.matchLabels.app = "memos";
        template = {
          metadata.labels.app = "memos";
          spec = {
            containers = [
              {
                name = "memos";
                # :stable is a moving tag — pin to a version (e.g.
                # neosmemo/memos:0.24.0) when you want reproducible upgrades.
                image = "neosmemo/memos:stable";
                # Recent images don't bake in a default port, so an unset port
                # resolves to 0 and Memos binds nowhere ("running on port 0").
                # Set it (and mode/data-dir) explicitly via MEMOS_* env.
                env = [
                  {
                    name = "MEMOS_MODE";
                    value = "prod";
                  }
                  {
                    name = "MEMOS_PORT";
                    value = toString port;
                  }
                  {
                    name = "MEMOS_DATA";
                    value = "/var/opt/memos";
                  }
                ];
                ports = [ { containerPort = port; } ];
                volumeMounts = [
                  {
                    name = "data";
                    mountPath = "/var/opt/memos"; # Memos' default data dir
                  }
                ];
              }
            ];
            volumes = [
              {
                name = "data";
                persistentVolumeClaim.claimName = "memos-data";
              }
            ];
          };
        };
      };
    }

    {
      apiVersion = "v1";
      kind = "Service";
      metadata = {
        name = "memos";
        namespace = ns;
      };
      spec = {
        type = "LoadBalancer";
        selector.app = "memos";
        ports = [
          {
            port = port;
            targetPort = port;
          }
        ];
      };
    }
  ];
}
