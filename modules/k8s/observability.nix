{ ... }:

# Observability stack for pharika's single-node k3s cluster: full LGTM.
#   L(oki)    - logs, collected by Alloy, stored on-box
#   G(rafana) - single UI (bundled in kube-prometheus-stack)
#   T(empo)   - traces, OTLP receivers on 4317/4318 (apps push directly)
#   M(etrics) - Prometheus, via kube-prometheus-stack
#
# Everything lands in the `monitoring` namespace and is deployed by k3s's
# built-in Helm controller from the HelmChart CRs generated here. Chart
# tarballs are fetched at BUILD time and pinned by `hash` (fixed-output
# derivations), so a rebuild is reproducible. To bump a chart: change
# `version`, set `hash = "";`, rebuild, and paste the hash nix prints back.
#
# Persistent volumes use k3s's default `local-path` provisioner (data under
# /var/lib/rancher/k3s/storage on the ext4 root).
#
# NOTE ON SECRETS: `values` set here land unencrypted in the world-readable
# nix store, and this is a public repo- so NO secrets go in `values`.
# Grafana's admin login comes from a k8s Secret named `grafana-admin` created
# directly on pharika (one-time `kubectl create secret`, see README/memory),
# so the password lives only in the cluster datastore, never in git or nix.

let
  ns = "monitoring";
  localPath = "local-path"; # k3s built-in dynamic provisioner
in
{
  services.k3s.autoDeployCharts = {

    # ---- Metrics + Grafana + Alerting ------------------------------------
    kube-prometheus-stack = {
      repo = "https://prometheus-community.github.io/helm-charts";
      name = "kube-prometheus-stack";
      version = "91.8.1";
      hash = "sha256-qT+Q0q7C7/UTYPh5KJE46xxp8CH8dOuMNE+ECh3qrRs=";
      targetNamespace = ns;
      createNamespace = true;
      values = {
        # Grafana is our single pane of glass for L, G, T and M.
        grafana = {
          # Admin login comes from the out-of-band `grafana-admin` Secret
          # (keys admin-user / admin-password), NOT from this repo. Create it
          # on pharika before this chart starts, or Grafana won't schedule.
          admin = {
            existingSecret = "grafana-admin";
            userKey = "admin-user";
            passwordKey = "admin-password";
          };
          # Serve under the public hostname so login POSTs / redirects use the
          # right origin when reached via https://grafana.pvc.tools (through
          # Traefik + Authelia). Without this Grafana rejects cross-host logins
          # with "origin not allowed". (http://pharika/ still serves the UI, but
          # log in via the subdomain from now on.)
          env = {
            GF_SERVER_ROOT_URL = "https://grafana.pvc.tools";
            GF_SERVER_DOMAIN = "grafana.pvc.tools";

            # --- OIDC SSO via Authelia (generic_oauth) ---------------------------
            # One login: Authelia is the identity provider, Grafana delegates to it.
            # Non-secret settings here; the client SECRET comes from the grafana-oauth
            # k8s Secret via envValueFrom below (never in this public repo). Grafana's
            # own admin login (grafana-admin Secret) stays as a break-glass fallback.
            GF_AUTH_GENERIC_OAUTH_ENABLED = "true";
            GF_AUTH_GENERIC_OAUTH_NAME = "Authelia";
            GF_AUTH_GENERIC_OAUTH_CLIENT_ID = "grafana";
            GF_AUTH_GENERIC_OAUTH_SCOPES = "openid profile email groups";
            GF_AUTH_GENERIC_OAUTH_AUTH_URL = "https://auth.pvc.tools/api/oidc/authorization";
            GF_AUTH_GENERIC_OAUTH_TOKEN_URL = "https://auth.pvc.tools/api/oidc/token";
            GF_AUTH_GENERIC_OAUTH_API_URL = "https://auth.pvc.tools/api/oidc/userinfo";
            GF_AUTH_GENERIC_OAUTH_LOGIN_ATTRIBUTE_PATH = "preferred_username";
            GF_AUTH_GENERIC_OAUTH_GROUPS_ATTRIBUTE_PATH = "groups";
            GF_AUTH_GENERIC_OAUTH_NAME_ATTRIBUTE_PATH = "name";
            GF_AUTH_GENERIC_OAUTH_USE_PKCE = "true";
            GF_AUTH_GENERIC_OAUTH_AUTH_STYLE = "InHeader";
            GF_AUTH_GENERIC_OAUTH_ALLOW_SIGN_UP = "true";
            # Authelia 'admins' group -> Grafana Admin, everyone else -> Viewer.
            GF_AUTH_GENERIC_OAUTH_ROLE_ATTRIBUTE_PATH = "contains(groups[*], 'admins') && 'Admin' || 'Viewer'";
          };
          # Client secret kept out of the repo (create the grafana-oauth Secret).
          envValueFrom = {
            GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET.secretKeyRef = {
              name = "grafana-oauth";
              key = "client-secret";
            };
          };
          persistence = {
            enabled = true;
            storageClassName = localPath;
            size = "5Gi";
          };
          # Prometheus is auto-added as the default datasource; wire the rest.
          additionalDataSources = [
            {
              name = "Loki";
              type = "loki";
              uid = "loki";
              access = "proxy";
              url = "http://loki.${ns}.svc:3100";
            }

            # TEMPORARILY DISABLED TEMPO: useless until we actually need traces & hogs RAM lol

            # {
              # name = "Tempo";
              # type = "tempo";
              # uid = "tempo";
              # access = "proxy";
              # url = "http://tempo.${ns}.svc:3100";
              # jsonData.tracesToLogsV2.datasourceUid = "loki";
            # }
          ];
        };

        prometheus.prometheusSpec = {
          retention = "10d";
          # Pick up ServiceMonitors/PodMonitors/Rules from *any* chart, not
          # just ones labelled with this Helm release. Without this you'd
          # silently miss metrics from loki/tempo/alloy etc.
          serviceMonitorSelectorNilUsesHelmValues = false;
          podMonitorSelectorNilUsesHelmValues = false;
          ruleSelectorNilUsesHelmValues = false;
          probeSelectorNilUsesHelmValues = false;
          resources.requests = {
            cpu = "200m";
            memory = "512Mi";
          };
          storageSpec.volumeClaimTemplate.spec = {
            storageClassName = localPath;
            accessModes = [ "ReadWriteOnce" ];
            resources.requests.storage = "20Gi";
          };
        };

        alertmanager.alertmanagerSpec.storage.volumeClaimTemplate.spec = {
          storageClassName = localPath;
          accessModes = [ "ReadWriteOnce" ];
          resources.requests.storage = "5Gi";
        };
      };
    };

    # ---- Logs: storage ----------------------------------------------------
    loki = {
      repo = "https://grafana.github.io/helm-charts";
      name = "loki";
      version = "7.3.0";
      hash = "sha256-BKM59xLXcKH1mfBfwKWjzeGOQ5FOSa5qSfcXG+hrzAk=";
      targetNamespace = ns;
      createNamespace = true;
      values = {
        deploymentMode = "SingleBinary"; # one pod, right for a single node
        loki = {
          auth_enabled = false;
          commonConfig.replication_factor = 1;
          schemaConfig.configs = [
            {
              from = "2024-04-01";
              store = "tsdb";
              object_store = "filesystem";
              schema = "v13";
              index = {
                prefix = "loki_index_";
                period = "24h";
              };
            }
          ];
          storage.type = "filesystem";
          limits_config.retention_period = "168h"; # 7d
          compactor = {
            retention_enabled = true;
            delete_request_store = "filesystem";
          };
        };
        singleBinary = {
          replicas = 1;
          persistence = {
            enabled = true;
            storageClass = localPath;
            size = "10Gi";
          };
        };
        # Zero out the microservice / scale-out components and heavy extras.
        read.replicas = 0;
        write.replicas = 0;
        backend.replicas = 0;
        chunksCache.enabled = false;
        resultsCache.enabled = false;
        gateway.enabled = false;
        lokiCanary.enabled = false;
        test.enabled = false;
        minio.enabled = false;
      };
    };

    # ---- Logs: collection -------------------------------------------------
    # Alloy runs as a DaemonSet and tails pod logs via the k8s API, then
    # pushes to Loki. No host log-path mounts needed.
    alloy = {
      repo = "https://grafana.github.io/helm-charts";
      name = "alloy";
      version = "1.13.0";
      hash = "sha256-v92my3cMNSZESJe5y1pPszcRxgjTZNnnhX7GmaL/9Ps=";
      targetNamespace = ns;
      createNamespace = true;
      values = {
        alloy.configMap.content = ''
          discovery.kubernetes "pods" {
            role = "pod"
          }

          discovery.relabel "pod_logs" {
            targets = discovery.kubernetes.pods.targets

            rule {
              source_labels = ["__meta_kubernetes_namespace"]
              target_label  = "namespace"
            }
            rule {
              source_labels = ["__meta_kubernetes_pod_name"]
              target_label  = "pod"
            }
            rule {
              source_labels = ["__meta_kubernetes_pod_container_name"]
              target_label  = "container"
            }
            rule {
              source_labels = ["__meta_kubernetes_namespace", "__meta_kubernetes_pod_container_name"]
              separator     = "/"
              target_label  = "job"
            }
          }

          loki.source.kubernetes "pods" {
            targets    = discovery.relabel.pod_logs.output
            forward_to = [loki.write.default.receiver]
          }

          loki.write "default" {
            endpoint {
              url = "http://loki.${ns}.svc:3100/loki/api/v1/push"
            }
          }
        '';
      };
    };

    # ---- Traces -----------------------------------------------------------

            # TEMPORARILY DISABLED TEMPO: useless until we actually need traces & hogs RAM lol

    # Single-binary Tempo with OTLP receivers. Instrumented apps send spans
    # straight to tempo.${ns}.svc:4317 (gRPC) or :4318 (HTTP).
    # tempo = {
      # repo = "https://grafana.github.io/helm-charts";
      # name = "tempo";
      # version = "1.24.4";
      # hash = "sha256-8fbjGNW8o7UJfLZ2B3eWzfgTW+ssH3HE0UYUzPmwCBs=";
      # targetNamespace = ns;
      # createNamespace = true;
      # values = {
        # tempo = {
          # retention = "168h"; # 7d block retention
          # storage.trace = {
            # backend = "local";
            # local.path = "/var/tempo/traces";
            # wal.path = "/var/tempo/wal";
          # };
          # receivers.otlp.protocols = {
            # grpc.endpoint = "0.0.0.0:4317";
            # http.endpoint = "0.0.0.0:4318";
          # };
        # };
        # persistence = {
          # enabled = true;
          # storageClassName = localPath;
          # size = "10Gi";
        # };
      # };
    # };
  };

  # ---- Grafana: https://grafana.pvc.tools via Traefik + Authelia ------------
  # Host-based IngressRoute on :443 with the `le` wildcard cert, gated by the
  # Authelia ForwardAuth middleware (defined here in the monitoring namespace —
  # same per-namespace pattern as memos/karakeep).
  #
  # NOTE: this REPLACED an older host-less Ingress (HOSTS=`*`) that routed ALL
  # port-80 traffic to Grafana — which meant any `http://<anything>.pvc.tools`
  # served the Grafana login (it hijacked auth.pvc.tools etc.). That's gone; the
  # web (:80) entrypoint now just redirects to :443 (see traefik.nix). Reach
  # Grafana only at https://grafana.pvc.tools now.
  services.k3s.manifests.grafana-route.content = [
    {
      apiVersion = "traefik.io/v1alpha1";
      kind = "Middleware";
      metadata = {
        name = "authelia";
        namespace = ns;
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
        name = "grafana";
        namespace = ns;
      };
      spec = {
        entryPoints = [ "websecure" ];
        routes = [
          {
            match = "Host(`grafana.pvc.tools`)";
            kind = "Rule";
            middlewares = [ { name = "authelia"; namespace = ns; } ];
            services = [
              {
                name = "kube-prometheus-stack-grafana";
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
