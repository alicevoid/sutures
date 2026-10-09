{ pkgs, ... }:

# ArgoCD: the one app-layer thing Nix keeps.
#   Bootstraps argo-cd (Helm) and declares the root app-of-apps Application pointing at the
#   staples repo. From there Argo reconciles every workload from git, so the cluster stops
#   drifting from its source of truth (see notes/k8s/ARGOCD.md). Workloads live in staples,
#   not here. Boundary: Nix owns the substrate (k3s, Traefik controller, this bootstrap);
#   Argo owns the workloads + routes. One owner per resource.

let
  ns = "argocd";
  staplesRepo = "https://github.com/alicevoid/staples";
in
{
  # argocd CLI for driving the cluster. Use --core (talks to the k8s API via KUBECONFIG, no
  # server login). It needs the kube context namespace = argocd:
  #   install -Dm600 /etc/rancher/k3s/k3s.yaml ~/.kube/config
  #   export KUBECONFIG=$HOME/.kube/config && kubectl config set-context --current --namespace=argocd
  environment.systemPackages = [ pkgs.argocd ];

  services.k3s.autoDeployCharts.argo-cd = {
    repo = "https://argoproj.github.io/argo-helm";
    name = "argo-cd";
    version = "10.10.1"; # Argo CD v3.5.4
    # Fixed-output hash: to bump, change version, set hash = "", rebuild, paste back what nix prints.
    hash = "sha256-Q9XSEoLJAHEAHBRRCIMfcf8Bcutd/htr0GE3QJ2PbF4=";
    targetNamespace = ns;
    createNamespace = true;
    values = {
      # Release name is "argo-cd", so without this the chart doubles the prefix into
      # "argo-cd-argocd-server". Pin the fullname to the conventional "argocd-server" etc.
      fullnameOverride = "argocd";

      # Single-node homelab: skip the HA replicas, keep it lean.
      redis-ha.enabled = false;
      controller.replicas = 1;
      server.replicas = 1;
      repoServer.replicas = 1;
      applicationSet.replicas = 1;

      # Run argocd-server plaintext (no edge TLS yet). Reach the UI over an ssh tunnel:
      #   ssh -L 9090:localhost:9090 pharika 'kubectl -n argocd port-forward svc/argocd-server 9090:80'
      # then http://localhost:9090. (A future argocd.pvc.tools route would retire the tunnel.)
      configs.params."server.insecure" = true;
    };
  };

  # Root app-of-apps. Keep identical to staples/bootstrap/root.yaml; this addon is what applies
  # it on the cluster (the single Nix -> Argo handoff). Argo then reconciles apps/ -> the rest.
  # Self-heal on, prune off: a new file in apps/ spawns its child Application; removing one does
  # not auto-delete it.
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
