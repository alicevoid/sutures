{ ... }:

# Karakeep (http://pharika:3000) — bookmark / omni-capture app (ex-Hoarder).
#   Three containers in the `karakeep` namespace:
#     web          - the Next.js app + workers (UI, port 3000)
#     chrome       - headless Chromium; crawls saved links for titles,
#                    previews, favicons and archived copies
#     meilisearch  - full-text search index over everything (this is what
#                    makes the search bar work)
#
#   ROUTING NOTE: same constraint as memos.nix — the Grafana Ingress is
#   host-less and owns "/" on Traefik's :80, so instead of an Ingress the web
#   Service is a LoadBalancer. k3s's servicelb (klipper) binds 3000 onto the
#   host, so http://pharika:3000 hits it directly. chrome/meilisearch are
#   internal-only (ClusterIP). Upgrade path later: real hostname + HTTPS via
#   the Tailscale operator, then drop the open port.
#
#   SECRETS: NEXTAUTH_SECRET and MEILI_MASTER_KEY must NOT live in this public
#   repo (they'd land in the world-readable nix store). They come from an
#   out-of-band k8s Secret named `karakeep-secrets` created directly on pharika
#   (like grafana-admin), so they only ever live in the cluster datastore:
#
#     kubectl create namespace karakeep   # or let this manifest create it first
#     kubectl -n karakeep create secret generic karakeep-secrets \
#       --from-literal=nextauth-secret="$(openssl rand -base64 36)" \
#       --from-literal=meili-master-key="$(openssl rand -base64 36)"
#
#   Create it before (or right after) the first rebuild, or the pods won't
#   start. The master key must match between the web and meilisearch pods —
#   they both read it from this one Secret, so they always agree.
#
#   AI tagging is intentionally OFF. Karakeep auto-tags via an LLM only if
#   OPENAI_API_KEY (or an Ollama endpoint) is set — see the commented env on
#   the web container for where to wire it in later.

let
  ns = "karakeep";
  webPort = 3000;

  # Pinned for reproducible rebuilds. Bump deliberately:
  #   - app   : latest release at https://github.com/karakeep-app/karakeep/releases
  #   - meili : Meilisearch is index-format-sensitive; use the version Karakeep's
  #             upstream docker-compose pins for this app release (currently v1.41.0).
  webImage = "ghcr.io/karakeep-app/karakeep:0.33.2";
  meiliImage = "getmeili/meilisearch:v1.41.0";
  # Karakeep ships its own Chromium image with remote-debugging baked in; it
  # isn't index-sensitive and upstream only publishes a floating `release` tag.
  chromeImage = "ghcr.io/karakeep-app/karakeep-chrome:release";

  secretName = "karakeep-secrets";
in
{
  # Open the LoadBalancer port on the host (tailnet-reachable).
  networking.firewall.allowedTCPPorts = [ webPort ];

  services.k3s.manifests.karakeep.content = [
    {
      apiVersion = "v1";
      kind = "Namespace";
      metadata.name = ns;
    }

    # --- Storage ----------------------------------------------------------
    # Web app's SQLite DB + uploaded/archived assets (images, PDFs, videos).
    # 50Gi because 1GB video uploads are allowed (see MAX_ASSET_SIZE_MB).
    {
      apiVersion = "v1";
      kind = "PersistentVolumeClaim";
      metadata = {
        name = "karakeep-data";
        namespace = ns;
      };
      spec = {
        accessModes = [ "ReadWriteOnce" ];
        storageClassName = "local-path";
        resources.requests.storage = "50Gi";
      };
    }
    # Meilisearch's search index.
    {
      apiVersion = "v1";
      kind = "PersistentVolumeClaim";
      metadata = {
        name = "meili-data";
        namespace = ns;
      };
      spec = {
        accessModes = [ "ReadWriteOnce" ];
        storageClassName = "local-path";
        resources.requests.storage = "2Gi";
      };
    }

    # --- Meilisearch (internal) -------------------------------------------
    {
      apiVersion = "apps/v1";
      kind = "Deployment";
      metadata = {
        name = "meilisearch";
        namespace = ns;
      };
      spec = {
        replicas = 1;
        strategy.type = "Recreate"; # RWO volume: tear down before re-creating
        selector.matchLabels.app = "meilisearch";
        template = {
          metadata.labels.app = "meilisearch";
          spec = {
            containers = [
              {
                name = "meilisearch";
                image = meiliImage;
                env = [
                  {
                    name = "MEILI_MASTER_KEY";
                    valueFrom.secretKeyRef = {
                      name = secretName;
                      key = "meili-master-key";
                    };
                  }
                  {
                    name = "MEILI_NO_ANALYTICS";
                    value = "true";
                  }
                ];
                ports = [ { containerPort = 7700; } ];
                volumeMounts = [
                  {
                    name = "meili";
                    mountPath = "/meili_data";
                  }
                ];
                resources = {
                  requests = {
                    cpu = "100m";
                    memory = "256Mi";
                  };
                  limits = {
                    cpu = "500m";
                    memory = "512Mi";
                  };
                };
              }
            ];
            volumes = [
              {
                name = "meili";
                persistentVolumeClaim.claimName = "meili-data";
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
        name = "meilisearch";
        namespace = ns;
      };
      spec = {
        type = "ClusterIP";
        selector.app = "meilisearch";
        ports = [
          {
            port = 7700;
            targetPort = 7700;
          }
        ];
      };
    }

    # --- Headless Chrome (internal) ---------------------------------------
    # Flags mirror upstream's docker-compose `command:`. The image's entrypoint
    # already enables remote debugging on 0.0.0.0:9222, so these are only the
    # extra rendering flags. No PVC — it's stateless.
    {
      apiVersion = "apps/v1";
      kind = "Deployment";
      metadata = {
        name = "chrome";
        namespace = ns;
      };
      spec = {
        replicas = 1;
        selector.matchLabels.app = "chrome";
        template = {
          metadata.labels.app = "chrome";
          spec = {
            containers = [
              {
                name = "chrome";
                image = chromeImage;
                args = [
                  "--disable-gpu"
                  "--disable-dev-shm-usage"
                  "--hide-scrollbars"
                  "--disable-blink-features=AutomationControlled"
                  "--window-size=1440,900"
                ];
                ports = [ { containerPort = 9222; } ];
                resources = {
                  requests = {
                    cpu = "100m";
                    memory = "256Mi";
                  };
                  # Chrome is the OOM risk; cap it so a heavy page can't
                  # starve the box.
                  limits = {
                    cpu = "1";
                    memory = "1Gi";
                  };
                };
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
        name = "chrome";
        namespace = ns;
      };
      spec = {
        type = "ClusterIP";
        selector.app = "chrome";
        ports = [
          {
            port = 9222;
            targetPort = 9222;
          }
        ];
      };
    }

    # --- Karakeep web (exposed) -------------------------------------------
    {
      apiVersion = "apps/v1";
      kind = "Deployment";
      metadata = {
        name = "karakeep";
        namespace = ns;
      };
      spec = {
        replicas = 1;
        strategy.type = "Recreate"; # RWO data volume
        selector.matchLabels.app = "karakeep";
        template = {
          metadata.labels.app = "karakeep";
          spec = {
            containers = [
              {
                name = "web";
                image = webImage;
                env = [
                  {
                    name = "DATA_DIR";
                    value = "/data"; # SQLite DB + assets live here
                  }
                  {
                    # The address you reach the app at; used for auth callbacks.
                    # Update this if/when it gets a real hostname.
                    name = "NEXTAUTH_URL";
                    value = "http://pharika:3000";
                  }
                  {
                    name = "NEXTAUTH_SECRET";
                    valueFrom.secretKeyRef = {
                      name = secretName;
                      key = "nextauth-secret";
                    };
                  }
                  {
                    name = "MEILI_ADDR";
                    value = "http://meilisearch:7700";
                  }
                  {
                    name = "MEILI_MASTER_KEY";
                    valueFrom.secretKeyRef = {
                      name = secretName;
                      key = "meili-master-key";
                    };
                  }
                  {
                    name = "BROWSER_WEB_URL";
                    value = "http://chrome:9222";
                  }
                  {
                    # Allow up to 1GB uploads (videos). Default is 50.
                    name = "MAX_ASSET_SIZE_MB";
                    value = "1024";
                  }
                  # --- AI auto-tagging (OFF) ---------------------------------
                  # Karakeep only auto-tags/summarizes if an inference backend
                  # is configured. To enable later, add ONE of:
                  #   { name = "OPENAI_API_KEY"; valueFrom.secretKeyRef = {
                  #       name = secretName; key = "openai-api-key"; }; }
                  # ...or point at a local Ollama:
                  #   { name = "OLLAMA_BASE_URL"; value = "http://ollama:11434"; }
                  #   { name = "INFERENCE_TEXT_MODEL"; value = "<model>"; }
                  # (and add the key to the karakeep-secrets Secret).
                ];
                ports = [ { containerPort = webPort; } ];
                volumeMounts = [
                  {
                    name = "data";
                    mountPath = "/data";
                  }
                ];
                resources = {
                  requests = {
                    cpu = "250m";
                    memory = "512Mi";
                  };
                  limits = {
                    cpu = "1";
                    memory = "1Gi";
                  };
                };
              }
            ];
            volumes = [
              {
                name = "data";
                persistentVolumeClaim.claimName = "karakeep-data";
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
        name = "karakeep";
        namespace = ns;
      };
      spec = {
        # Kept as LoadBalancer for now so http://pharika:3000 (tailnet) still
        # works as a fallback while we try out the subdomain path below. The
        # IngressRoute routes to this same Service via its ClusterIP. HARDENING
        # LATER: flip to ClusterIP, drop `webPort` from the firewall, and set
        # NEXTAUTH_URL to https://karakeep.pvc.tools once auth is in front.
        type = "LoadBalancer";
        selector.app = "karakeep";
        ports = [
          {
            port = webPort;
            targetPort = webPort;
          }
        ];
      };
    }

    # Subdomain path: https://karakeep.pvc.tools via Traefik + the `le` wildcard
    # cert (see traefik.nix). Runs in parallel with the LoadBalancer above.
    #
    # NOTE: Karakeep auth (NextAuth) bakes the origin into redirects via
    # NEXTAUTH_URL, still set to http://pharika:3000 above. So logging in via the
    # LoadBalancer works, but logging in via https://karakeep.pvc.tools may
    # redirect-loop until NEXTAUTH_URL is switched. For now use the subdomain to
    # verify ROUTING + TLS; fix NEXTAUTH_URL when we cut over to the subdomain for
    # real (in the hardening/auth increment). No Authelia middleware yet.
    {
      apiVersion = "traefik.io/v1alpha1";
      kind = "IngressRoute";
      metadata = {
        name = "karakeep";
        namespace = ns;
      };
      spec = {
        entryPoints = [ "websecure" ]; # :443 only
        routes = [
          {
            match = "Host(`karakeep.pvc.tools`)";
            kind = "Rule";
            services = [
              {
                name = "karakeep";
                port = webPort;
              }
            ];
          }
        ];
        tls = {
          certResolver = "le";
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
