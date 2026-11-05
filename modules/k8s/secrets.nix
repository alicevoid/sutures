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
#   restart: rolled out when that Secret's content changes, for apps that read it only at start.

let
  # name -> { namespace; keys (single values); files (whole files); labels; restart }
  k8sSecrets = {
    gluetun-pia = {
      namespace = "downloads"; # made by the Argo app downloads; must exist before this unit runs
      keys = [ "username" "password" ];
      restart = [ "deploy/qbit-public" ]; # gluetun reads the login only at start
    };
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
      restart = [ "deploy/authelia" ];
    };
  };

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
  ) k8sSecrets;

  applyOne =
    name: s:
    let
      fromFiles = lib.concatMapStringsSep " " (
        key: "--from-file=${key}=${config.sops.secrets.${secretName name key}.path}"
      ) ((s.keys or [ ]) ++ (s.files or [ ]));
      labels = lib.concatStringsSep " " (lib.mapAttrsToList (k: v: "${k}=${v}") (s.labels or { }));
      paths = map (key: config.sops.secrets.${secretName name key}.path) ((s.keys or [ ]) ++ (s.files or [ ]));
    in
    ''
      echo "applying ${s.namespace}/${name}"
      kubectl create secret generic ${name} -n ${s.namespace} ${fromFiles} --dry-run=client -o yaml \
        ${lib.optionalString (labels != "") "| kubectl label --local -f - ${labels} -o yaml"} \
        | kubectl apply --server-side --force-conflicts --field-manager=sops-nix -f -
    ''
    + lib.optionalString (s ? restart) ''
      new=$(cat ${lib.concatStringsSep " " paths} | sha256sum | cut -d' ' -f1)
      old=$(cat "$STATE_DIRECTORY/${name}" 2>/dev/null || true)
      if [ -n "$old" ] && [ "$old" != "$new" ]; then
        ${lib.concatMapStrings (d: "kubectl -n ${s.namespace} rollout restart ${d}
") s.restart}
      fi
      echo "$new" > "$STATE_DIRECTORY/${name}"
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
      StateDirectory = "k8s-secrets"; # last-applied hashes, for restart
    };
    script = ''
      set -euo pipefail
      for _ in $(seq 1 60); do kubectl get --raw /readyz >/dev/null 2>&1 && break; sleep 5; done
      ${lib.concatStrings (lib.mapAttrsToList applyOne k8sSecrets)}
    '';
  };
}
