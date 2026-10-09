{ pkgs, ... }:

# ArgoCD — the one app-layer thing Nix keeps:
#   bootstraps argo-cd (Helm) + declares the root app-of-apps Application that points at
#   the `staples` repo. From there Argo continuously reconciles every workload from git,
#   so the cluster stops drifting from its source of truth (the whole reason for the move;
#   see k8s/ARGOCD.md). Workloads themselves live in `staples`, NOT here.
#
#   Boundary: Nix owns the cluster substrate (k3s, Traefik controller, this bootstrap);
#   Argo owns the workloads + routes. One owner per resource — they never fight.

let
  ns = "argocd";
  staplesRepo = "https://github.com/alicevoid/staples";
in
{
  # argocd CLI, for the migration runbook. Use it in `--core` mode (talks straight to the
  # k8s API via KUBECONFIG, no argocd-server login/tunnel needed): `argocd app diff memos --core`.
  environment.systemPackages = [ pkgs.argocd ];

  services.k3s.autoDeployCharts.argo-cd = {
    repo = "https://argoproj.github.io/argo-helm";
    name = "argo-cd";
    version = "10.10.1"; # Argo CD v3.5.4
    # Fixed-output hash (same dance as observability.nix): to bump, change `version`,
    # set `hash = "";`, rebuild, paste back the hash nix prints.
    hash = "sha256-Q9XSEoLJAHEAHBRRCIMfcf8Bcutd/htr0GE3QJ2PbF4=";
    targetNamespace = ns;
    createNamespace = true;
    values = {
      # Release name is "argo-cd", so without this the chart doubles the prefix into
      # "argo-cd-argocd-server" etc. Pin the fullname so resources are the conventional
      # "argocd-server", "argocd-repo-server", ... (matches upstream docs + the runbook).
      fullnameOverride = "argocd";

      # Single-node homelab: skip the HA replicas, keep it lean.
      redis-ha.enabled = false;
      controller.replicas = 1;
      server.replicas = 1;
      repoServer.replicas = 1;
      applicationSet.replicas = 1;

      # Traefik terminates TLS at the edge; run argocd-server plaintext behind it so we
      # don't fight over double-TLS. Reach the UI via port-forward during the migration:
      #   kubectl -n argocd port-forward svc/argocd-server 8080:443
      configs.params."server.insecure" = true;
    };
  };

  # Root app-of-apps. MUST stay identical to staples/bootstrap/root.yaml — this Nix addon
  # is what actually applies it (the single Nix -> Argo handoff). Everything downstream
  # (apps/ -> manifests/ + charts/) is reconciled by Argo from the staples repo.
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
      # Auto-sync the app-of-apps so adding/removing files in staples/apps/ propagates to
      # the child Application objects. prune OFF so a removed app file never auto-deletes.
      # The CHILD Applications are what gate real workload changes (manual during migration).
      syncPolicy.automated = {
        prune = false;
        selfHeal = true;
      };
    };
  };
}
