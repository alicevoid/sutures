{ ... }:

# Memos:
#   notes app. gated subdomain memos.pvc.tools + un-gated tailnet LoadBalancer :5230

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
        strategy.type = "Recreate"; # RWO volume can't attach to two pods at once
        selector.matchLabels.app = "memos";
        template = {
          metadata.labels.app = "memos";
          spec = {
            containers = [
              {
                name = "memos";
                image = "neosmemo/memos:stable"; # moving tag — pin a version for reproducible upgrades
                # NOTE: set MEMOS_PORT explicitly — unset binds port 0 ("running on port 0")
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
        # LoadBalancer: klipper binds :5230 on the host -> un-gated tailnet fallback
        #   TODO: flip to ClusterIP + drop the firewall port once the subdomain's trusted
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

    # Gated subdomain: memos.pvc.tools (le cert + Authelia).
    #   forwardAuth middleware is per-namespace to dodge cross-ns Traefik perms
    {
      apiVersion = "traefik.io/v1alpha1";
      kind = "Middleware";
      metadata = {
        name = "authelia";
        namespace = ns;
      };
      spec.forwardAuth = {
        address = "http://authelia.authelia.svc.cluster.local/api/authz/forward-auth";
        trustForwardHeader = true;
        authResponseHeaders = [ "Remote-User" "Remote-Groups" "Remote-Email" "Remote-Name" ];
      };
    }

    {
      apiVersion = "traefik.io/v1alpha1";
      kind = "IngressRoute";
      metadata = {
        name = "memos";
        namespace = ns;
      };
      spec = {
        entryPoints = [ "websecure" ]; # :443 only
        routes = [
          {
            match = "Host(`memos.pvc.tools`)";
            kind = "Rule";
            middlewares = [ { name = "authelia"; namespace = ns; } ];
            services = [
              {
                name = "memos";
                port = port;
              }
            ];
          }
        ];
        tls = {
          certResolver = "le";
          # one wildcard cert reused across subdomains (stays under LE rate limits)
          domains = [
            {
              main = "pvc.tools";
              sans = [ "*.pvc.tools" ];
            }
          ];
        };
      };
    }
  ];
}
