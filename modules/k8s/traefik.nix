{ ... }:

# =============================================================================
# traefik.nix — give k3s's built-in Traefik the ability to get real HTTPS certs
# =============================================================================
#
# WHAT THIS DOES
#   Teaches the Traefik that already ships with k3s how to fetch free Let's
#   Encrypt certificates for *.pvc.tools, so our apps can be served over HTTPS.
#   We don't install anything new (no cert-manager) — we just hand Traefik some
#   extra settings via a "HelmChartConfig", which layers our values on top of
#   k3s's built-in Traefik without replacing it.
#
# HOW THE CERT IS PROVED
#   Let's Encrypt needs proof you own pvc.tools. We use the "DNS-01" method:
#   Traefik asks Porkbun (our DNS host) to create a temporary TXT record, and
#   Let's Encrypt checks for it. This needs NO open/inbound ports, so it works
#   right now over the tailnet, before anything is exposed to the internet.
#
# NOTHING HERE IS DISABLED
#   Every line below is active config — there are no commented-out lines you need
#   to turn on. The ONLY thing you'll ever toggle is the single STAGING line near
#   the bottom (see "GOING TO PRODUCTION"), and for now it should stay as-is.
#
# -----------------------------------------------------------------------------
# BEFORE YOU REBUILD — one-time setup (both required)
# -----------------------------------------------------------------------------
#   1. In Porkbun: turn ON "API Access" for the pvc.tools domain, and create an
#      API key + secret key. (Without the per-domain toggle, the API refuses the
#      calls even with valid keys.)
#
#   2. Put those keys into the cluster as a Secret (kept out of this public repo,
#      exactly like grafana-admin / karakeep-secrets). Run on pharika:
#
#        kubectl -n kube-system create secret generic traefik-porkbun \
#          --from-literal=api-key='pk1_...' \
#          --from-literal=secret-api-key='sk1_...'
#
# -----------------------------------------------------------------------------
# AFTER YOU REBUILD — quick sanity check
# -----------------------------------------------------------------------------
#   Changing Traefik restarts it. Traefik is the SHARED front door, so if a bad
#   value made it crashloop, only http://pharika/ (Grafana) would blip — the
#   tailnet apps on their own ports (memos:5230, karakeep:3000) don't go through
#   Traefik and stay up. Confirm Traefik came back cleanly:
#
#        kubectl -n kube-system rollout status deploy/traefik
#        kubectl -n kube-system logs deploy/traefik | grep -iE 'acme|porkbun|error'
#
# -----------------------------------------------------------------------------
# GOING TO PRODUCTION (do this LATER, not now)
# -----------------------------------------------------------------------------
#   We start against Let's Encrypt's STAGING server so mistakes don't count
#   against the real rate limits. Staging certs are untrusted, so browsers show a
#   warning — that warning is EXPECTED and actually means it's working.
#
#   Once a staging cert issues cleanly, switch to real certs by DELETING the one
#   line marked "STAGING" at the very bottom, then force Traefik to re-request:
#
#        kubectl -n kube-system exec deploy/traefik -- rm -f /data/acme.json
#        kubectl -n kube-system rollout restart deploy/traefik
# =============================================================================

{
  services.k3s.manifests.traefik-config.content = {
    apiVersion = "helm.cattle.io/v1";
    kind = "HelmChartConfig";
    metadata = {
      name = "traefik";
      namespace = "kube-system";
    };

    # Everything inside valuesContent is plain YAML that gets merged into the
    # Traefik Helm chart's settings.
    spec.valuesContent = ''
      # --- Porkbun credentials -------------------------------------------------
      # Hand Traefik the Porkbun API keys (read from the Secret you created
      # above) so it can create the DNS TXT records during the cert challenge.
      env:
        - name: PORKBUN_API_KEY
          valueFrom:
            secretKeyRef:
              name: traefik-porkbun
              key: api-key
        - name: PORKBUN_SECRET_API_KEY
          valueFrom:
            secretKeyRef:
              name: traefik-porkbun
              key: secret-api-key
        # Porkbun can be slow to publish the TXT record; wait up to 600s for it
        # to appear before giving up on the challenge.
        - name: PORKBUN_PROPAGATION_TIMEOUT
          value: "600"

      # --- Keep certs across restarts ------------------------------------------
      # Store the issued certs (acme.json) on a small persistent disk so Traefik
      # reuses them after a restart instead of asking Let's Encrypt every time
      # (which would quickly hit rate limits).
      persistence:
        enabled: true
        storageClass: local-path
        size: 128Mi
        path: /data

      # Let's Encrypt requires acme.json to be private (chmod 600). This tiny
      # startup container sets that permission before Traefik reads the file.
      deployment:
        initContainers:
          - name: volume-permissions
            image: busybox:latest
            command: ["sh", "-c", "touch /data/acme.json && chmod -v 600 /data/acme.json"]
            volumeMounts:
              - name: data
                mountPath: /data
      podSecurityContext:
        fsGroup: 65532
        fsGroupChangePolicy: "OnRootMismatch"

      # --- The certificate resolver named "le" ---------------------------------
      # This defines the resolver our apps point at with `tls.certResolver = le`
      # (see the IngressRoutes in memos.nix / karakeep.nix).
      additionalArguments:
        # Contact address for the Let's Encrypt account (gets cert-expiry
        # warnings). Uses the pvc.tools forwarding alias, not a personal address.
        - "--certificatesresolvers.le.acme.email=admin@pvc.tools"
        # Where issued certs are saved (on the persistent disk above).
        - "--certificatesresolvers.le.acme.storage=/data/acme.json"
        # Prove ownership via a Porkbun DNS record (the DNS-01 method).
        - "--certificatesresolvers.le.acme.dnschallenge.provider=porkbun"
        # Check for the TXT record against public DNS, not the cluster's resolver.
        - "--certificatesresolvers.le.acme.dnschallenge.resolvers=1.1.1.1:53,8.8.8.8:53"
        # STAGING (keep for now; delete this ONE line to switch to real certs):
        - "--certificatesresolvers.le.acme.caserver=https://acme-staging-v02.api.letsencrypt.org/directory"
    '';
  };
}
