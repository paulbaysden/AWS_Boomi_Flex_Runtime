locals {
  cfg      = yamldecode(file(var.config_file))
  ctx      = local.cfg.kubernetes.kube_context
  ns       = local.cfg.kubernetes.namespace
  pvc_name = local.cfg.storage.claim_name
  tls_mode = local.cfg.ingress.tls_mode
  efs_name = local.cfg.efs.name

  tags = {
    "app"        = "boomi-flex-runtime"
    "managed-by" = "terraform"
    "namespace"  = local.ns
  }
}

check "tls_mode_valid" {
  assert {
    condition     = contains(["tls_before_runtime", "end_to_end"], local.tls_mode)
    error_message = "ingress.tls_mode must be either tls_before_runtime or end_to_end."
  }
}

provider "aws" {
  region  = local.cfg.aws.region
  profile = local.cfg.aws.profile != "" ? local.cfg.aws.profile : null
}

provider "kubernetes" {
  config_path    = local.cfg.kubernetes.kubeconfig_path
  config_context = local.ctx
}

# Step 2: dedicated namespace (one runtime per namespace)
resource "kubernetes_namespace_v1" "flex" {
  metadata {
    name = local.ns
    labels = {
      "app.kubernetes.io/part-of" = "boomi-flex-runtime"
    }
  }
}

# Step 3: static PersistentVolume backed by the EFS access point.
# The CSI driver must be installed first (aws_eks_addon.efs_csi or pre-existing).
resource "kubernetes_persistent_volume_v1" "flex" {
  metadata {
    name = "${local.ns}-efs-pv"
  }

  spec {
    capacity = {
      storage = local.cfg.storage.capacity
    }
    access_modes                     = ["ReadWriteMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = ""

    persistent_volume_source {
      csi {
        driver        = "efs.csi.aws.com"
        volume_handle = "${aws_efs_file_system.flex.id}::${aws_efs_access_point.flex.id}"
      }
    }
  }

  depends_on = [
    aws_efs_access_point.flex,
    aws_eks_addon.efs_csi,
  ]
}

resource "kubernetes_persistent_volume_claim_v1" "flex" {
  metadata {
    name      = local.pvc_name
    namespace = kubernetes_namespace_v1.flex.metadata[0].name
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = ""
    volume_name        = kubernetes_persistent_volume_v1.flex.metadata[0].name

    resources {
      requests = {
        storage = local.cfg.storage.capacity
      }
    }
  }
}

# Step 8: runtimectl install.
# The token goes in through the environment, not the command string, so it isn't logged with the command.
# runtimectl takes --token as a flag, so the token is briefly visible in the process list on this host.
resource "null_resource" "runtime_install" {
  count = var.run_install ? 1 : 0

  triggers = {
    namespace    = local.ns
    kube_context = local.ctx
  }

  depends_on = [kubernetes_persistent_volume_claim_v1.flex]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]

    environment = {
      FLEX_INSTALL_TOKEN = var.install_token == null ? "" : var.install_token
      FLEX_KUBE_CONTEXT  = local.ctx
      FLEX_RUNTIMECTL    = local.cfg.runtimectl.binary_path
    }

    command = <<-EOT
      set -euo pipefail
      if [ -z "$FLEX_INSTALL_TOKEN" ]; then
        echo "install_token is required (set TF_VAR_install_token)" >&2
        exit 1
      fi
      "$FLEX_RUNTIMECTL" install \
        --token="$FLEX_INSTALL_TOKEN" \
        --kube-context="$FLEX_KUBE_CONTEXT"
    EOT
  }
}

# Step 5c: end-to-end TLS only. Waits for the runtime to create its Service and CA bundle,
# then applies the BackendTLSPolicy from the docs.
# Requires the Gateway API CRDs to be installed in the cluster.
resource "null_resource" "backend_tls_policy" {
  count = local.tls_mode == "end_to_end" ? 1 : 0

  triggers = {
    namespace    = local.ns
    kube_context = local.ctx
  }

  depends_on = [null_resource.runtime_install]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]

    environment = {
      FLEX_KUBE_CONTEXT = local.ctx
      FLEX_NAMESPACE    = local.ns
    }

    command = <<-EOT
      set -euo pipefail

      for i in $(seq 1 60); do
        if kubectl --context "$FLEX_KUBE_CONTEXT" -n "$FLEX_NAMESPACE" get configmap boomi-runtime-ca >/dev/null 2>&1 \
          && kubectl --context "$FLEX_KUBE_CONTEXT" -n "$FLEX_NAMESPACE" get service ingress-gateway >/dev/null 2>&1; then
          break
        fi
        if [ "$i" -eq 60 ]; then
          echo "Timed out waiting for ingress-gateway Service and boomi-runtime-ca ConfigMap" >&2
          exit 1
        fi
        sleep 10
      done

      kubectl --context "$FLEX_KUBE_CONTEXT" apply -f - <<'YAML'
apiVersion: gateway.networking.k8s.io/v1
kind: BackendTLSPolicy
metadata:
  name: ingress-gateway
  namespace: ${local.ns}
spec:
  targetRefs:
    - group: ""
      kind: Service
      name: ingress-gateway
      sectionName: https
  validation:
    caCertificateRefs:
      - group: ""
        kind: ConfigMap
        name: boomi-runtime-ca
    hostname: ingress-gateway.${local.ns}.svc.cluster.local
YAML
    EOT
  }
}
