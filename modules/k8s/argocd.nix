{ pkgs, ... }:

# ArgoCD bootstrap: the argo-cd chart and the root app-of-apps that points at staples.
#   Nix owns the substrate (k3s, Cilium, this bootstrap). Argo owns every workload and route.

let
  ns = "argocd";
  staplesRepo = "https://github.com/alicevoid/staples";
in
{
  # Use the CLI with --core (no server login). It needs the kube context namespace set to argocd.
  environment.systemPackages = [ pkgs.argocd ];

  services.k3s.autoDeployCharts.argo-cd = {
    repo = "https://argoproj.github.io/argo-helm";
    name = "argo-cd";
    version = "10.10.1"; # Argo CD v3.5.4
    # To bump: change version, set hash = "", rebuild, paste the hash nix prints.
    hash = "sha256-Q9XSEoLJAHEAHBRRCIMfcf8Bcutd/htr0GE3QJ2PbF4=";
    targetNamespace = ns;
    createNamespace = true;
    values = {
      # Without this the release name "argo-cd" doubles the prefix ("argo-cd-argocd-server").
      fullnameOverride = "argocd";

      # No HA replicas.
      redis-ha.enabled = false;
      controller.replicas = 1;
      server.replicas = 1;
      repoServer.replicas = 1;
      applicationSet.replicas = 1;

      configs.params."server.insecure" = true;

      configs.cm = {
        url = "https://argocd.pvc.tools";
        "oidc.config" = ''
          name: Authelia
          issuer: https://auth.pvc.tools
          clientID: argocd
          clientSecret: $argocd-oidc:client-secret
          requestedScopes: [openid, profile, email, groups]
        '';

        # The chart's default exclusions minus EndpointSlice, because staples writes EndpointSlices
        #   for backends outside the cluster (Home Assistant). Argo tracks by annotation, so it never
        #   claims controller-made slices. On a chart bump, diff this against the chart's default.
        "resource.exclusions" = ''
          ### Endpoints stay excluded (control-plane made); EndpointSlice is managed for external backends
          - apiGroups:
            - ""
            kinds:
            - Endpoints
          ### Internal Kubernetes resources excluded reduce the number of watched events
          - apiGroups:
            - coordination.k8s.io
            kinds:
            - Lease
          ### Internal Kubernetes Authz/Authn resources excluded reduce the number of watched events
          - apiGroups:
            - authentication.k8s.io
            - authorization.k8s.io
            kinds:
            - SelfSubjectReview
            - TokenReview
            - LocalSubjectAccessReview
            - SelfSubjectAccessReview
            - SelfSubjectRulesReview
            - SubjectAccessReview
          ### Intermediate Certificate Request excluded reduce the number of watched events
          - apiGroups:
            - certificates.k8s.io
            kinds:
            - CertificateSigningRequest
          - apiGroups:
            - cert-manager.io
            kinds:
            - CertificateRequest
          ### Cilium internal resources excluded reduce the number of watched events and UI Clutter
          - apiGroups:
            - cilium.io
            kinds:
            - CiliumIdentity
            - CiliumEndpoint
            - CiliumEndpointSlice
          ### Kyverno intermediate and reporting resources excluded reduce the number of watched events and improve performance
          - apiGroups:
            - kyverno.io
            - reports.kyverno.io
            - wgpolicyk8s.io
            kinds:
            - PolicyReport
            - ClusterPolicyReport
            - EphemeralReport
            - ClusterEphemeralReport
            - AdmissionReport
            - ClusterAdmissionReport
            - BackgroundScanReport
            - ClusterBackgroundScanReport
            - UpdateRequest
        '';
      };

      configs.rbac = {
        "policy.default" = "";
        "policy.csv" = "g, admins, role:admin";
        scopes = "[groups]";
      };
    };
  };

  # Root app-of-apps. Keep identical to staples/bootstrap/root.yaml.
  #   Prune is off: removing a file from apps/ does not delete its Application.
  services.k3s.manifests.argocd-root.content = {
    apiVersion = "argoproj.io/v1alpha1";
    kind = "Application";
    metadata = {
      name = "root";
      namespace = ns;
    };
    spec = {
      project = "default";
      source = {
        repoURL = staplesRepo;
        targetRevision = "main";
        path = "apps";
      };
      destination = {
        server = "https://kubernetes.default.svc";
        namespace = ns;
      };
      syncPolicy.automated = {
        prune = false;
        selfHeal = true;
      };
    };
  };
}
