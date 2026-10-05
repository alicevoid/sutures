{ ... }:

# Karakeep (ex-Hoarder) — bookmark / omni-capture:
#   web (UI :3000) + chrome (headless crawler) + meilisearch (search index)
#   gated subdomain karakeep.pvc.tools + un-gated tailnet LoadBalancer :3000
#
#   NOTE: needs a `karakeep-secrets` Secret (nextauth-secret, meili-master-key,
#         oauth-client-secret). AI auto-tagging off (no inference backend set).

let
  ns = "karakeep";
  webPort = 3000;

  # pinned; bump deliberately. meili is index-format-sensitive -> match karakeep's
  # upstream compose version (v1.41.0); chrome only ships a floating `release` tag.
  webImage = "ghcr.io/karakeep-app/karakeep:0.33.2";
  meiliImage = "getmeili/meilisearch:v1.41.0";
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

    # Storage: sqlite + assets. 50Gi since 1GB uploads are allowed (MAX_ASSET_SIZE_MB)
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

    # Meilisearch (internal)
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

    # Headless Chrome (internal, stateless) — crawls saved links.
    #   flags mirror upstream compose; the image already enables debug on :9222
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
                  # chrome is the OOM risk; cap it
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

    # Karakeep web (exposed)
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
                    # must match the public hostname or NextAuth callbacks redirect-loop
                    name = "NEXTAUTH_URL";
                    value = "https://karakeep.pvc.tools";
                  }
                  {
                    name = "NEXTAUTH_SECRET";
                    valueFrom.secretKeyRef = {
                      name = secretName;
                      key = "nextauth-secret";
                    };
                  }
                  # OIDC SSO via Authelia. secret from karakeep-secrets.
                  #   karakeep's own login stays on as break-glass (don't disable it)
                  {
                    name = "OAUTH_WELLKNOWN_URL";
                    value = "https://auth.pvc.tools/.well-known/openid-configuration";
                  }
                  {
                    name = "OAUTH_CLIENT_ID";
                    value = "karakeep";
                  }
                  {
                    name = "OAUTH_CLIENT_SECRET";
                    valueFrom.secretKeyRef = {
                      name = secretName;
                      key = "oauth-client-secret";
                    };
                  }
                  {
                    name = "OAUTH_PROVIDER_NAME";
                    value = "Authelia";
                  }
                  # link the OIDC identity to an existing account by email
                  {
                    name = "OAUTH_ALLOW_DANGEROUS_EMAIL_ACCOUNT_LINKING";
                    value = "true";
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
                    # allow up to 1GB uploads
                    name = "MAX_ASSET_SIZE_MB";
                    value = "1024";
                  }
                  # AI auto-tagging (off) — enable by setting an inference backend:
                  #   { name = "OPENAI_API_KEY"; valueFrom.secretKeyRef = { name = secretName; key = "openai-api-key"; }; }
                  #   ...or OLLAMA_BASE_URL + INFERENCE_TEXT_MODEL (+ the key in karakeep-secrets)
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
        # LoadBalancer: klipper binds :3000 on the host -> un-gated tailnet fallback
        #   TODO: flip to ClusterIP + drop the firewall port once the subdomain's trusted
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

    # Gated subdomain: karakeep.pvc.tools (le cert + Authelia).
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
        name = "karakeep";
        namespace = ns;
      };
      spec = {
        entryPoints = [ "websecure" ]; # :443 only
        routes = [
          {
            match = "Host(`karakeep.pvc.tools`)";
            kind = "Rule";
            middlewares = [ { name = "authelia"; namespace = ns; } ];
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
