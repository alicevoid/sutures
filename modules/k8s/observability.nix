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
            {
              name = "Tempo";
              type = "tempo";
              uid = "tempo";
              access = "proxy";
              url = "http://tempo.${ns}.svc:3100";
              jsonData.tracesToLogsV2.datasourceUid = "loki";
            }
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
    # Single-binary Tempo with OTLP receivers. Instrumented apps send spans
    # straight to tempo.${ns}.svc:4317 (gRPC) or :4318 (HTTP).
    tempo = {
      repo = "https://grafana.github.io/helm-charts";
      name = "tempo";
      version = "1.24.4";
      hash = "sha256-8fbjGNW8o7UJfLZ2B3eWzfgTW+ssH3HE0UYUzPmwCBs=";
      targetNamespace = ns;
      createNamespace = true;
      values = {
        tempo = {
          retention = "168h"; # 7d block retention
          storage.trace = {
            backend = "local";
            local.path = "/var/tempo/traces";
            wal.path = "/var/tempo/wal";
          };
          receivers.otlp.protocols = {
            grpc.endpoint = "0.0.0.0:4317";
            http.endpoint = "0.0.0.0:4318";
          };
        };
        persistence = {
          enabled = true;
          storageClassName = localPath;
          size = "10Gi";
        };
      };
    };
  };

  # ---- Ingress: reach Grafana over the tailnet without port-forwarding ----
  # k3s bundles Traefik as its ingress controller. This host-less Ingress
  # routes all HTTP :80 traffic to Grafana, so any name that resolves to
  # pharika works: http://pharika/ (Tailscale MagicDNS) or pharika.local.
  # (Plain HTTP is fine here — Tailscale already encrypts the transport.)
  services.k3s.manifests.grafana-ingress.content = {
    apiVersion = "networking.k8s.io/v1";
    kind = "Ingress";
    metadata = {
      name = "grafana";
      namespace = ns;
      annotations."traefik.ingress.kubernetes.io/router.entrypoints" = "web";
    };
    spec = {
      ingressClassName = "traefik";
      rules = [
        {
          http.paths = [
            {
              path = "/";
              pathType = "Prefix";
              backend.service = {
                name = "kube-prometheus-stack-grafana";
                port.number = 80;
              };
            }
          ];
        }
      ];
    };
  };
}
