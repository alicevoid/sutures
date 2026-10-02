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
              # one_factor = password only (lowest friction to get going).
              # Bump to two_factor once everyone has enrolled a TOTP app.
              policy: one_factor
              subject:
                - group:friends
                - group:admins

        # Session cookie shared across *.pvc.tools -> single sign-on.
        session:
          cookies:
            - domain: pvc.tools
              authelia_url: https://auth.pvc.tools
              default_redirection_url: https://memos.pvc.tools
              name: authelia_session
              same_site: lax
              inactivity: 1h
              expiration: 8h
              remember_me: 1M

        # Brute-force protection: lock an account briefly after repeated failures.
        regulation:
          max_retries: 3
          find_time: 2m
          ban_time: 5m

        storage:
          local:
            path: /data/db.sqlite3

        # Filesystem notifier (no SMTP yet): password-reset / 2FA-enrolment links
        # get written to this file. Read them with:
        #   kubectl -n authelia exec deploy/authelia -- cat /data/notifications.txt
        notifier:
          filesystem:
            filename: /data/notifications.txt
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
                args = [ "--config" "/config/configuration.yml" ];
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
