{ ... }:

# Authelia:
#   SSO login-wall + OIDC provider for *.pvc.tools. config here is non-secret;
#   who-can-log-in + OIDC/SMTP/session secrets live in the authelia-secrets Secret.

let
  ns = "authelia";
  image = "ghcr.io/authelia/authelia:4.39.28"; # pin; bump deliberately
in
{
  services.k3s.manifests.authelia.content = [

    # Namespace
    {
      apiVersion = "v1";
      kind = "Namespace";
      metadata.name = ns;
    }

    # Storage (sqlite db + notifier file)
    {
      apiVersion = "v1";
      kind = "PersistentVolumeClaim";
      metadata = {
        name = "authelia-data";
        namespace = ns;
      };
      spec = {
        accessModes = [ "ReadWriteOnce" ];
        storageClassName = "local-path";
        resources.requests.storage = "1Gi";
      };
    }

    # Config (non-secret; secrets come via AUTHELIA_*_FILE env)
    {
      apiVersion = "v1";
      kind = "ConfigMap";
      metadata = {
        name = "authelia-config";
        namespace = ns;
      };
      data."configuration.yml" = ''
        theme: auto

        server:
          address: tcp://0.0.0.0:9091

        log:
          level: info

        totp:
          issuer: pvc.tools

        # who can log in: users_database.yml lives in the Secret, mounted at /secrets
        authentication_backend:
          file:
            path: /secrets/users_database.yml

        # who reaches what. default deny; first matching rule wins
        access_control:
          default_policy: deny
          rules:
            - domain:
                - memos.pvc.tools
                - karakeep.pvc.tools
                - grafana.pvc.tools
                - traefik.pvc.tools
              # password + TOTP — a leaked password alone can't get in
              policy: two_factor
              subject:
                - group:friends
                - group:admins

        # SSO cookie across *.pvc.tools. tuned "quiet" (remembered device -> ~3 months)
        session:
          # Redis session store so restarts don't log everyone out (cluster-internal, no pw)
          redis:
            host: redis.authelia.svc.cluster.local
            port: 6379
          cookies:
            - domain: pvc.tools
              authelia_url: https://auth.pvc.tools
              # no default_redirection_url: a direct login stays on the portal
              #   (app-initiated logins still return via `rd`)
              name: authelia_session
              same_site: lax
              inactivity: 7d       # session dies after a week of no use
              expiration: 1d       # lifetime of a NON-remembered cookie
              remember_me: 3M      # "remember me" box ticked -> 3 months

        # brute-force lockout
        regulation:
          max_retries: 3
          find_time: 2m
          ban_time: 5m

        storage:
          local:
            path: /data/db.sqlite3

        # SMTP notifier (SMTP2GO) — enrol/reset emails for self-service. only the pw is secret
        notifier:
          smtp:
            address: 'submission://mail.smtp2go.com:2525' # 2525 dodges ISP blocking of 25/587
            username: 'auth.pvc.tools' # the SMTP2GO SMTP user (their usernames are globally unique)
            sender: 'Authelia <no-reply@pvc.tools>'
            subject: '[Authelia] {title}'
      '';
    }

    # Deployment
    {
      apiVersion = "apps/v1";
      kind = "Deployment";
      metadata = {
        name = "authelia";
        namespace = ns;
      };
      spec = {
        replicas = 1;
        strategy.type = "Recreate"; # RWO volume
        selector.matchLabels.app = "authelia";
        template = {
          metadata.labels.app = "authelia";
          spec = {
            enableServiceLinks = false; # k8s injects AUTHELIA_* svc vars -> Authelia eats them as config -> boom
            securityContext.fsGroup = 1000; # let it write the PVC regardless of uid
            containers = [
              {
                name = "authelia";
                inherit image;
                # second --config pulls the OIDC block (hmac/jwks/clients) from the
                # Secret, out of this public repo. NOTE: /secrets/oidc.yml must exist
                # before a rebuild or Authelia won't start.
                args = [
                  "--config"
                  "/config/configuration.yml"
                  "--config"
                  "/secrets/oidc.yml"
                ];
                env = [
                  # secrets from files
                  {
                    name = "AUTHELIA_SESSION_SECRET_FILE";
                    value = "/secrets/session-secret";
                  }
                  {
                    name = "AUTHELIA_STORAGE_ENCRYPTION_KEY_FILE";
                    value = "/secrets/storage-encryption-key";
                  }
                  {
                    name = "AUTHELIA_IDENTITY_VALIDATION_RESET_PASSWORD_JWT_SECRET_FILE";
                    value = "/secrets/jwt-secret";
                  }
                  # SMTP pw — add smtp-password to authelia-secrets before a rebuild
                  {
                    name = "AUTHELIA_NOTIFIER_SMTP_PASSWORD_FILE";
                    value = "/secrets/smtp-password";
                  }
                ];
                ports = [ { containerPort = 9091; } ];
                volumeMounts = [
                  {
                    name = "config";
                    mountPath = "/config";
                  }
                  {
                    name = "secrets";
                    mountPath = "/secrets";
                    readOnly = true;
                  }
                  {
                    name = "data";
                    mountPath = "/data";
                  }
                ];
                resources = {
                  requests = {
                    cpu = "50m";
                    memory = "64Mi";
                  };
                  limits = {
                    cpu = "500m";
                    memory = "256Mi";
                  };
                };
              }
            ];
            volumes = [
              {
                name = "config";
                configMap.name = "authelia-config";
              }
              {
                name = "secrets";
                secret.secretName = "authelia-secrets";
              }
              {
                name = "data";
                persistentVolumeClaim.claimName = "authelia-data";
              }
            ];
          };
        };
      };
    }

    # Service (Traefik + forwardAuth reach Authelia here)
    {
      apiVersion = "v1";
      kind = "Service";
      metadata = {
        name = "authelia";
        namespace = ns;
      };
      spec = {
        type = "ClusterIP";
        selector.app = "authelia";
        # :80 so the middleware URL can omit the port; forward to 9091
        ports = [
          {
            port = 80;
            targetPort = 9091;
          }
        ];
      };
    }

    # Redis — Authelia's session store (survives restarts; appendonly + PVC)
    {
      apiVersion = "v1";
      kind = "PersistentVolumeClaim";
      metadata = {
        name = "redis-data";
        namespace = ns;
      };
      spec = {
        accessModes = [ "ReadWriteOnce" ];
        storageClassName = "local-path";
        resources.requests.storage = "1Gi";
      };
    }
    {
      apiVersion = "apps/v1";
      kind = "Deployment";
      metadata = {
        name = "redis";
        namespace = ns;
      };
      spec = {
        replicas = 1;
        strategy.type = "Recreate"; # RWO volume
        selector.matchLabels.app = "redis";
        template = {
          metadata.labels.app = "redis";
          spec = {
            securityContext.fsGroup = 999; # redis uid in the alpine image
            containers = [
              {
                name = "redis";
                image = "redis:7-alpine";
                args = [ "--appendonly" "yes" ];
                ports = [ { containerPort = 6379; } ];
                volumeMounts = [
                  {
                    name = "data";
                    mountPath = "/data";
                  }
                ];
                resources = {
                  requests = {
                    cpu = "25m";
                    memory = "32Mi";
                  };
                  limits = {
                    cpu = "200m";
                    memory = "128Mi";
                  };
                };
              }
            ];
            volumes = [
              {
                name = "data";
                persistentVolumeClaim.claimName = "redis-data";
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
        name = "redis";
        namespace = ns;
      };
      spec = {
        type = "ClusterIP";
        selector.app = "redis";
        ports = [
          {
            port = 6379;
            targetPort = 6379;
          }
        ];
      };
    }

    # Login portal: auth.pvc.tools (no gate on this one)
    {
      apiVersion = "traefik.io/v1alpha1";
      kind = "IngressRoute";
      metadata = {
        name = "authelia";
        namespace = ns;
      };
      spec = {
        entryPoints = [ "websecure" ];
        routes = [
          {
            match = "Host(`auth.pvc.tools`)";
            kind = "Rule";
            services = [
              {
                name = "authelia";
                port = 80;
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
