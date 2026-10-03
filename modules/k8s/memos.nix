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
        # Kept as LoadBalancer for now so http://pharika:5230 (tailnet) still
        # works as a fallback while we try out the subdomain path below. A
        # LoadBalancer Service still has a ClusterIP underneath, so the
        # IngressRoute can route to it unchanged. HARDENING LATER: flip this to
        # ClusterIP and drop `port` from the firewall once subdomains + auth are
        # proven.
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

    # Subdomain path: https://memos.pvc.tools via Traefik + the `le` wildcard cert
    # (see traefik.nix), gated by Authelia (see authelia.nix). Runs in parallel
    # with the LoadBalancer above (tailnet pharika:5230 stays open, un-gated).

    # ForwardAuth middleware: Traefik asks Authelia to authorize each request.
    # Defined in THIS namespace so no cross-namespace Traefik permission is needed
    # — the address is just a cluster-DNS URL to the Authelia service.
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
        entryPoints = [ "websecure" "web" ]; # :443 only — avoids the host-less Grafana ingress on :80
        routes = [
          {
            match = "Host(`memos.pvc.tools`)";
            kind = "Rule";
            #middlewares = [ { name = "authelia"; namespace = ns; } ];
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
          # Request ONE wildcard cert and reuse it for every subdomain, instead
          # of a separate cert per host (keeps us well under rate limits).
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
