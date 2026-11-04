{
  config,
  lib,
  pkgs,
  ...
}:

# Kubernetes Secrets from sutures/secrets/cluster/, applied by pharika at each switch.
#   Single values: secrets/cluster/<name>.yaml (one entry per key).
#   Whole files:   secrets/cluster/<name>.<key>.bin (sops binary, one opaque blob).
#   Argo never touches Secrets. Removing one here does not delete it: kubectl delete it by hand.

let
  # name -> { namespace; keys (single values); files (whole files); labels }
  k8sSecrets = {
    grafana-oauth = {
      namespace = "monitoring";
      keys = [ "client-secret" ];
    };
    grafana-admin = {
      namespace = "monitoring";
      keys = [ "admin-user" "admin-password" ];
    };
    karakeep-secrets = {
      namespace = "karakeep";
      keys = [ "meili-master-key" "nextauth-secret" "oauth-client-secret" ];
    };
    argocd-oidc = {
      namespace = "argocd";
      keys = [ "client-secret" ];
      labels."app.kubernetes.io/part-of" = "argocd"; # ArgoCD only reads labelled Secrets
    };
    porkbun-api-credentials = {
      namespace = "cert-manager";
      keys = [ "api-key" "secret-key" ];
    };
    couchdb-secrets = {
      namespace = "obsidian";
      keys = [ "username" "password" ];
    };
    livesync-bridge-config = {
      namespace = "obsidian";
      files = [ "config.json" ];
    };
    alertmanager-config = {
      namespace = "monitoring";
      files = [ "alertmanager.yaml" ];
    };
    authelia-secrets = {
      namespace = "authelia";
      keys = [ "jwt-secret" "session-secret" "smtp-password" "storage-encryption-key" ];
      files = [ "oidc.yml" "users_database.yml" ];
    };
  };

  # Applied today. Each one moves here after its switch is verified.
  migrated = [
    "grafana-oauth"
    "grafana-admin"
    "karakeep-secrets"
    "argocd-oidc"
    "porkbun-api-credentials"
    "couchdb-secrets"
    "livesync-bridge-config"
    "alertmanager-config"
  ];

  active = lib.filterAttrs (name: _: lib.elem name migrated) k8sSecrets;
  dir = ../../secrets/cluster;
  secretName = name: key: "k8s/${name}/${key}";

  sopsEntries = lib.concatMapAttrs (
    name: s:
    lib.listToAttrs (
      map (key: {
        name = secretName name key;
        value = {
          sopsFile = dir + "/${name}.yaml";
          inherit key;
        };
      }) (s.keys or [ ])
      ++ map (key: {
        name = secretName name key;
        value = {
          sopsFile = dir + "/${name}.${key}.bin";
          format = "binary";
        };
      }) (s.files or [ ])
    )
  ) active;

  applyOne =
    name: s:
    let
      fromFiles = lib.concatMapStringsSep " " (
        key: "--from-file=${key}=${config.sops.secrets.${secretName name key}.path}"
      ) ((s.keys or [ ]) ++ (s.files or [ ]));
      labels = lib.concatStringsSep " " (lib.mapAttrsToList (k: v: "${k}=${v}") (s.labels or { }));
    in
    ''
      echo "applying ${s.namespace}/${name}"
      kubectl create secret generic ${name} -n ${s.namespace} ${fromFiles} --dry-run=client -o yaml \
        ${lib.optionalString (labels != "") "| kubectl label --local -f - ${labels} -o yaml"} \
        | kubectl apply --server-side --force-conflicts --field-manager=sops-nix -f -
    '';
in
{
  sops.secrets = sopsEntries;

  systemd.services.k8s-secrets = {
    description = "Apply Kubernetes Secrets from sops";
    after = [ "k3s.service" ];
    wants = [ "k3s.service" ];
    wantedBy = [ "multi-user.target" ];
    onFailure = [ "notify-failure@%n.service" ];
    # re-run at switch only when an encrypted file's content (or the list) changes
    restartTriggers = lib.mapAttrsToList (_: v: builtins.hashFile "sha256" v.sopsFile) sopsEntries;
    environment.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
    path = [ pkgs.kubectl ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail
      for _ in $(seq 1 60); do kubectl get --raw /readyz >/dev/null 2>&1 && break; sleep 5; done
      ${lib.concatStrings (lib.mapAttrsToList applyOne active)}
    '';
  };
}
