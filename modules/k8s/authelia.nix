{ ... }:

# =============================================================================
# authelia.nix — self-hosted SSO / access gate for the *.pvc.tools apps
# =============================================================================
#
# WHAT THIS DOES
#   Authelia is the login wall that sits in front of the public apps. Traefik
#   asks Authelia "is this request allowed?" (via a ForwardAuth middleware, see
#   memos.nix / karakeep.nix); if the user isn't logged in, Traefik bounces them
#   to https://auth.pvc.tools to sign in, then a cookie scoped to .pvc.tools
#   gives single-sign-on across every subdomain. This is what makes the apps
#   "friends-only" instead of open to the whole internet.
#
#   Config lives in git (declare, don't click). Access rules are in the
#   ConfigMap below; WHO can log in (usernames + hashed passwords) lives in an
#   out-of-repo Secret, because this repo is public.
#
# -----------------------------------------------------------------------------
# BEFORE YOU REBUILD — one-time secret setup (out of the repo)
# -----------------------------------------------------------------------------
#   1. Generate a password hash for your first (admin) user. Once the image is
#      pullable you can do this in-cluster:
#        kubectl -n authelia run hash --rm -it --restart=Never \
#          --image=ghcr.io/authelia/authelia:4.39.28 -- \
#          authelia crypto hash generate argon2 --password 'YOUR_PASSWORD'
#      Copy the "$argon2id$..." line it prints.
#
#   2. Write a users database file locally (NOT in the repo), e.g. users.yml:
#        users:
#          alice:
#            disabled: false
#            displayname: "Alice"
#            password: "$argon2id$v=19$m=65536,t=3,p=4$...."   # from step 1
#            email: "admin@pvc.tools"
#            groups:
#              - admins
#              - friends
#      (Add friends the same way, with just `- friends`.)
#
#   3. Create the Secret with three random secrets + that users file:
#        kubectl create namespace authelia 2>/dev/null
#        kubectl -n authelia create secret generic authelia-secrets \
#          --from-literal=session-secret="$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 64)" \
#          --from-literal=storage-encryption-key="$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 64)" \
#          --from-literal=jwt-secret="$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 64)" \
#          --from-file=users_database.yml=./users.yml
#      Then you can shred ./users.yml locally — it now lives in the cluster.
#
# -----------------------------------------------------------------------------
# AFTER YOU REBUILD — verify (over the tailnet, nothing public yet)
# -----------------------------------------------------------------------------
#   kubectl -n authelia rollout status deploy/authelia
#   kubectl -n authelia logs deploy/authelia | tail -30     # watch for config errors
#   curl -I --resolve auth.pvc.tools:443:10.0.0.141 https://auth.pvc.tools/
#     -> should return the Authelia login page (200), valid cert.
#   Then hit a protected app and confirm it redirects to the login:
#   curl -sS -o /dev/null -w '%{http_code} %{redirect_url}\n' \
#     --resolve karakeep.pvc.tools:443:10.0.0.141 https://karakeep.pvc.tools/
# =============================================================================

let
  ns = "authelia";
  image = "ghcr.io/authelia/authelia:4.39.28"; # pin; bump deliberately
in
{
  services.k3s.manifests.authelia.content = [

    # 1) Namespace --------------------------------------------------------------
    {
      apiVersion = "v1";
      kind = "Namespace";
      metadata.name = ns;
    }

    # 2) Persistent storage (SQLite session/device DB + notifier file) ----------
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

    # 3) Config (non-secret) ----------------------------------------------------
    # Secrets (session secret, storage encryption key, jwt secret) are NOT here —
    # they come from the authelia-secrets Secret via AUTHELIA_*_FILE env vars.
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

        # WHO can log in: usernames + argon2 password hashes live in the
        # out-of-repo Secret, mounted at /secrets/users_database.yml.
        authentication_backend:
          file:
            path: /secrets/users_database.yml

        # WHO can reach WHAT. default deny = nobody unless a rule allows them.
        # Rules are evaluated top-down; first match wins. "friends not the world."
        access_control:
          default_policy: deny
          rules:
            - domain:
                - memos.pvc.tools
                - karakeep.pvc.tools
                - grafana.pvc.tools
                - traefik.pvc.tools
              # two_factor = password + TOTP. This is what stops an unknown device
              # with only a leaked/guessed password: it can't pass without the
              # authenticator code. Users enrol a TOTP app on first login.
              # (All four apps share this tier: friends + admins.)
              policy: two_factor
              subject:
                - group:friends
                - group:admins

        # Session cookie shared across *.pvc.tools -> single sign-on. Tuned for
        # "quiet": a remembered device stays signed in for ~3 months, so you log
        # in (with TOTP) roughly once a quarter per device.
        session:
          # Keep sessions in Redis (see the redis Deployment below) instead of
          # in-memory, so an Authelia restart/upgrade does NOT log everyone out —
          # the #1 source of silent friction before. Redis is cluster-internal
          # (ClusterIP, never firewalled out), so no password is configured.
          redis:
            host: redis.authelia.svc.cluster.local
            port: 6379
          cookies:
            - domain: pvc.tools
              authelia_url: https://auth.pvc.tools
              default_redirection_url: https://memos.pvc.tools
              name: authelia_session
              same_site: lax
              inactivity: 7d       # session dies after a week of no use
              expiration: 1d       # lifetime of a NON-remembered cookie
              remember_me: 3M      # "remember me" box ticked -> 3 months

        # Brute-force protection: lock an account briefly after repeated failures.
        regulation:
          max_retries: 3
          find_time: 2m
          ban_time: 5m

        storage:
          local:
            path: /data/db.sqlite3

        # SMTP notifier (dedicated provider = SMTP2GO) — sends TOTP-enrolment and
        # password-reset emails so friends can self-serve in the portal (no more
        # fishing codes out of a file / the admin CLI). Only the PASSWORD is secret;
        # it comes from the authelia-secrets Secret via
        # AUTHELIA_NOTIFIER_SMTP_PASSWORD_FILE (see the Deployment env). host +
        # username + sender are non-secret. `username` must MATCH the SMTP user you
        # create in SMTP2GO (Settings → Users). Swap address+username for a different
        # provider — the rest is identical.
        notifier:
          smtp:
            address: 'submission://mail.smtp2go.com:2525' # 2525 = SMTP2GO's recommended STARTTLS port (dodges ISP blocking of 25/587)
            username: 'auth.pvc.tools' # <- must equal the SMTP2GO SMTP username (globally unique across all SMTP2GO)
            sender: 'Authelia <no-reply@pvc.tools>'
            subject: '[Authelia] {title}'
      '';
    }

    # 4) Deployment -------------------------------------------------------------
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
            # Kubernetes otherwise injects env vars for every Service in this ns
            # (AUTHELIA_SERVICE_PORT, AUTHELIA_PORT_80_TCP_*, ...). Authelia reads
            # ALL `AUTHELIA_*` env vars as config, so those collide with our
            # server.address and it refuses to start. Turn the injection off.
            enableServiceLinks = false;
            # Let the process write the PVC regardless of its runtime uid.
            securityContext.fsGroup = 1000;
            containers = [
              {
                name = "authelia";
                inherit image;
                # Base (non-secret) config from the ConfigMap, PLUS the OIDC block
                # — hmac secret, JWKS private key, and client definitions — from an
                # out-of-repo file inside the authelia-secrets Secret. Authelia merges
                # multiple --config files, so no OIDC secret ever touches this public
                # repo. ⚠️ /secrets/oidc.yml MUST exist (add it to authelia-secrets)
                # BEFORE this rebuild, or Authelia won't start.
                args = [
                  "--config"
                  "/config/configuration.yml"
                  "--config"
                  "/secrets/oidc.yml"
                ];
                env = [
                  # Secrets pulled from files (Authelia strips trailing newline).
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
                  # SMTP (SMTP2GO) password — add `smtp-password` to authelia-secrets
                  # BEFORE this rebuild, or Authelia won't start (missing file).
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

    # 5) Service (internal; Traefik + the forwardAuth middleware reach it here) --
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
        # Expose on :80 so the middleware URL can omit the port; forward to 9091.
        ports = [
          {
            port = 80;
            targetPort = 9091;
          }
        ];
      };
    }

    # 5b) Redis — Authelia's session store -------------------------------------
    # Sessions used to live in Authelia's memory, so every restart logged everyone
    # out. Redis makes them survive restarts/upgrades. append-only persistence +
    # a small PVC means sessions also survive Redis itself being rescheduled.
    # Cluster-internal only (ClusterIP), so it runs without a password.
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

    # 6) The login portal itself: https://auth.pvc.tools (NO forwardAuth on it) --
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
