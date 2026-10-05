{ ... }:

# Traefik TLS + Routing:
#   overlays k3s's bundled Traefik (HelmChartConfig)
#   wildcard LE cert via Porkbun DNS-01 (resolver "le"), :80 -> :443, dashboard behind Authelia
#
#   NOTE: needs a `traefik-porkbun` Secret (api-key / secret-api-key) in kube-system

{
  services.k3s.manifests.traefik-config.content = {
    apiVersion = "helm.cattle.io/v1";
    kind = "HelmChartConfig";
    metadata = {
      name = "traefik";
      namespace = "kube-system";
    };

    # valuesContent = plain YAML merged into the Traefik Helm chart values
    spec.valuesContent = ''
      # Porkbun creds (from the traefik-porkbun Secret) for the DNS-01 TXT records
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
        # Porkbun can be slow to publish the TXT; wait up to 600s
        - name: PORKBUN_PROPAGATION_TIMEOUT
          value: "600"
        # our wildcard parking CNAME makes lego write the challenge in the wrong
        # zone (-> "Invalid domain"); this keeps it in ours
        - name: LEGO_DISABLE_CNAME_SUPPORT
          value: "true"

      # keep acme.json across restarts (else we re-request + hit LE rate limits)
      persistence:
        enabled: true
        storageClass: local-path
        size: 128Mi
        path: /data

      # LE needs acme.json private (chmod 600); this init sets it pre-start
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

      # the "le" resolver the IngressRoutes point at
      additionalArguments:
        - "--certificatesresolvers.le.acme.email=admin@pvc.tools" # LE account (expiry warnings)
        - "--certificatesresolvers.le.acme.storage=/data/acme.json"
        - "--certificatesresolvers.le.acme.dnschallenge.provider=porkbun" # DNS-01
        # check the TXT against public DNS, not the cluster resolver
        - "--certificatesresolvers.le.acme.dnschallenge.resolvers=1.1.1.1:53,8.8.8.8:53"
        - "--api"
        - "--api.dashboard=true"
        # dashboard only via the Authelia-gated traefik.pvc.tools, never unauth
        - "--api.insecure=false"
        # all :80 -> :443 (nothing serves on :80; DNS-01 means we don't need it)
        - "--entrypoints.web.http.redirections.entrypoint.to=websecure"
        - "--entrypoints.web.http.redirections.entrypoint.scheme=https"
        - "--entrypoints.web.http.redirections.entrypoint.permanent=true"
    '';
  };

  # Traefik dashboard: traefik.pvc.tools (Authelia-gated) -> api@internal
  #   reach it at /dashboard/ once logged in
  services.k3s.manifests.traefik-dashboard.content = [
    {
      apiVersion = "traefik.io/v1alpha1";
      kind = "Middleware";
      metadata = {
        name = "authelia";
        namespace = "kube-system";
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
        name = "traefik-dashboard";
        namespace = "kube-system";
      };
      spec = {
        entryPoints = [ "websecure" ];
        routes = [
          {
            match = "Host(`traefik.pvc.tools`)";
            kind = "Rule";
            middlewares = [ { name = "authelia"; namespace = "kube-system"; } ];
            services = [
              {
                name = "api@internal";
                kind = "TraefikService";
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
