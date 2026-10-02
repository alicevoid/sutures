{ ... }:

# Traefik TLS — issue a real wildcard *.pvc.tools cert from Let's Encrypt using
# the DNS-01 challenge against Porkbun. No cert-manager, no extra charts: we just
# layer a HelmChartConfig over k3s's ALREADY-RUNNING bundled `traefik` HelmChart
# (in kube-system). IngressRoutes then reference the resolver as
# `tls.certResolver = le` (see memos.nix / karakeep.nix).
#
# WHY DNS-01: it proves ownership by writing a TXT record — needs NO inbound
# ports — so certs issue over the tailnet today, before any public exposure.
#
# BLAST-RADIUS NOTE: this reconfigures the SHARED ingress. If the traefik pod
# crashloops on a bad value, the Grafana ingress (http://pharika/) blips — but
# the LoadBalancer apps (memos:5230, karakeep:3000) DON'T go through Traefik, so
# tailnet access to those is unaffected. After a rebuild, check:
#   kubectl -n kube-system rollout status deploy/traefik
#
# SECRET (out of repo, like grafana-admin / karakeep-secrets): Porkbun API creds
# live in a k8s Secret in kube-system. Create ONCE on pharika BEFORE rebuilding:
#   kubectl -n kube-system create secret generic traefik-porkbun \
#     --from-literal=api-key='pk1_...' \
#     --from-literal=secret-api-key='sk1_...'
# Also toggle API ACCESS = ON for pvc.tools in Porkbun's domain settings, or the
# API rejects the calls even with valid keys.
#
# STAGING FIRST: the caserver line below points at Let's Encrypt STAGING to avoid
# burning prod rate limits while iterating (browsers will show an "untrusted"
# warning — that's expected and means it's WORKING). Once a staging cert issues
# cleanly, DELETE the caserver line to switch to prod, then force a re-issue:
#   kubectl -n kube-system exec deploy/traefik -- rm -f /data/acme.json  # or:
#   kubectl -n kube-system rollout restart deploy/traefik

{
  services.k3s.manifests.traefik-config.content = {
    apiVersion = "helm.cattle.io/v1";
    kind = "HelmChartConfig";
    metadata = {
      name = "traefik";
      namespace = "kube-system";
    };
    # valuesContent is a raw YAML string merged into the traefik chart's values.
    spec.valuesContent = ''
      # Porkbun API creds for lego's DNS-01 solver, from the out-of-band Secret.
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
        # Porkbun's DNS propagation is sometimes slow; give lego room before it
        # polls for the TXT record (seconds).
        - name: PORKBUN_PROPAGATION_TIMEOUT
          value: "600"

      # Persist acme.json so issued certs survive Traefik restarts (prevents
      # re-issuing and hitting rate limits). Tiny PVC on the local-path class.
      persistence:
        enabled: true
        storageClass: local-path
        size: 128Mi
        path: /data

      # acme.json MUST be chmod 600 or Traefik refuses to load it.
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

      # The ACME resolver named 'le' (referenced by IngressRoutes).
      additionalArguments:
        # TODO: set an email you're OK having in a PUBLIC repo (gets LE expiry
        # notices). Consider a dedicated alias rather than your primary address.
        - "--certificatesresolvers.le.acme.email="admin@pvc.tools"
        - "--certificatesresolvers.le.acme.storage=/data/acme.json"
        - "--certificatesresolvers.le.acme.dnschallenge.provider=porkbun"
        # Resolve the TXT check against public DNS, not the cluster's resolver.
        - "--certificatesresolvers.le.acme.dnschallenge.resolvers=1.1.1.1:53,8.8.8.8:53"
        # STAGING — DELETE this one line to switch to production once it works:
        - "--certificatesresolvers.le.acme.caserver=https://acme-staging-v02.api.letsencrypt.org/directory"
    '';
  };
}
