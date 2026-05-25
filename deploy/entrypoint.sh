#!/usr/bin/env bash
set -e

timestamp() {
  date +"%Y-%m-%d %T"
}

log() {
  local level="$1"
  local color="$2"
  shift 2
  echo -e "\033[${color}m ${level} [$(timestamp)] >> $* \033[0m" >&2
}

info() {
  log "INFO" "36" "$@"
}

warn() {
  log "WARN" "33" "$@"
}

error() {
  log "ERROR" "1;31" "$@"
}

die() {
  error "$@"
  exit 1
}

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || die "missing required command: ${cmd}"
}

is_true() {
  local value
  value="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  case "$value" in
    1|true|yes|y|on) return 0 ;;
    *) return 1 ;;
  esac
}

load_http_tools() {
  local tools_file="/root/.sealos/cloud/scripts/tools.sh"
  [ -f "$tools_file" ] || die "tools.sh not found in /root/.sealos/cloud/scripts"
  # shellcheck source=/dev/null
  source "$tools_file"
}

ensure_http_tool_fallbacks() {
  if ! declare -f bool_is_true >/dev/null 2>&1; then
    bool_is_true() {
      is_true "$1"
    }
  fi

  if ! declare -f read_yaml_file_path >/dev/null 2>&1; then
    read_yaml_file_path() {
      local path_expr="$1"
      local yaml_file="${GLOBAL_VALUES_FILE:-/root/.sealos/cloud/values/global.yaml}"
      local yq_bin="${YQ_BIN:-/root/.sealos/cloud/bin/yq}"

      [ -f "$yaml_file" ] || return 0
      if [ -x "$yq_bin" ]; then
        "$yq_bin" e -r "${path_expr} // \"\"" "$yaml_file" 2>/dev/null || true
        return 0
      fi
      if command -v yq >/dev/null 2>&1; then
        yq e -r "${path_expr} // \"\"" "$yaml_file" 2>/dev/null || true
        return 0
      fi
      return 0
    }
  fi

  if ! declare -f global_http_disable_https >/dev/null 2>&1; then
    global_http_disable_https() {
      local disable_https="${SEALOS_DISABLE_HTTPS:-}"
      if [ -z "$disable_https" ]; then
        disable_https="$(read_yaml_file_path '.global.http.disableHttps')"
      fi
      bool_is_true "${disable_https:-false}"
    }
  fi

  if ! declare -f global_http_external_url >/dev/null 2>&1; then
    global_http_external_url() {
      local host="$1"
      local path="${2:-}"
      local scheme="https"
      local port="${SEALOS_CLOUD_PORT:-}"

      if global_http_disable_https; then
        scheme="http"
        port="${SEALOS_HTTP_PORT:-}"
        [ -n "$port" ] || port="$(read_yaml_file_path '.global.http.httpPort')"
        [ -n "$port" ] || port="80"
      else
        [ -n "$port" ] || port="$(read_yaml_file_path '.global.http.httpsPort')"
        [ -n "$port" ] || port="443"
      fi

      if { [ "$scheme" = "http" ] && [ "$port" = "80" ]; } || { [ "$scheme" = "https" ] && [ "$port" = "443" ]; }; then
        printf '%s://%s%s' "$scheme" "$host" "$path"
      else
        printf '%s://%s:%s%s' "$scheme" "$host" "$port" "$path"
      fi
    }
  fi
}

required_resource_data() {
  local kind="$1"
  local namespace="$2"
  local name="$3"
  local key="$4"
  local decode="${5:-false}"
  local value

  value="$(kubectl get "$kind" "$name" -n "$namespace" -o "jsonpath={.data.${key}}" 2>/dev/null || true)"
  [ -n "$value" ] || die "missing required field: ${kind} ${namespace}/${name} data.${key}"

  if [ "$decode" = "true" ]; then
    printf '%s' "$value" | base64 --decode
    return
  fi

  printf '%s' "$value"
}

optional_resource_data() {
  local kind="$1"
  local namespace="$2"
  local name="$3"
  local key="$4"
  local decode="${5:-false}"
  local value

  value="$(kubectl get "$kind" "$name" -n "$namespace" -o "jsonpath={.data.${key}}" 2>/dev/null || true)"
  [ -n "$value" ] || return 0

  if [ "$decode" = "true" ]; then
    printf '%s' "$value" | base64 --decode
    return
  fi

  printf '%s' "$value"
}

append_set_string_if_present() {
  local value="$1"
  local key="$2"
  if [ -n "$value" ]; then
    HELM_COMMON_ARGS+=("--set-string" "${key}=${value}")
  fi
}

append_values_file_arg() {
  local file="$1"
  local label="$2"
  if [ -f "$file" ]; then
    info "Using ${label} Helm values from ${file}"
    HELM_COMMON_ARGS+=("-f" "$file")
  else
    warn "${label} values file ${file} not found, proceeding without it"
  fi
}

append_values_dir_args() {
  local values_dir="$1"
  local label="$2"
  local found="false"

  if [ ! -d "$values_dir" ]; then
    warn "${label} values directory ${values_dir} not found, proceeding without it"
    return 0
  fi

  for values_file in $(find "$values_dir" -maxdepth 1 -type f \( -name '*-values.yaml' -o -name '*-values.yml' \) | sort); do
    found="true"
    append_values_file_arg "$values_file" "$label"
  done

  if [ "$found" != "true" ]; then
    warn "${label} values directory ${values_dir} has no *-values.yaml files"
  fi
}

read_cert_tls_reject_unauthorized() {
  local cert_mode

  cert_mode="$(kubectl get configmap cert-config -n sealos-system -o jsonpath='{.data.CERT_MODE}' 2>/dev/null || true)"
  cert_mode="${CERT_MODE:-${cert_mode:-self-signed}}"
  cert_mode="$(printf '%s' "${cert_mode}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"

  case "$cert_mode" in
    https|acme|acmedns) printf '0' ;;
    *) printf '1' ;;
  esac
}

namespace_has_object_storage() {
  local namespace="$1"

  [ -n "$namespace" ] || return 1
  kubectl get svc "$OBJECT_STORAGE_SERVICE_NAME" -n "$namespace" >/dev/null 2>&1 || return 1
  kubectl get secret "$OBJECT_STORAGE_ADMIN_SECRET" -n "$namespace" >/dev/null 2>&1 || return 1
}

detect_object_storage_namespace() {
  local namespace
  local found_namespace=""

  for namespace in "${OBJECT_STORAGE_NAMESPACE:-}" objectstorage-system minio-system; do
    if namespace_has_object_storage "$namespace"; then
      printf '%s' "$namespace"
      return 0
    fi
  done

  if kubectl get tenants.minio.min.io -A >/dev/null 2>&1; then
    found_namespace="$(kubectl get tenants.minio.min.io -A --no-headers 2>/dev/null | awk '$2 == "object-storage" {print $1; exit}')"
    if namespace_has_object_storage "$found_namespace"; then
      printf '%s' "$found_namespace"
      return 0
    fi
  fi

  found_namespace="$(kubectl get secret -A --no-headers 2>/dev/null | awk '$2 == "object-storage-env-configuration" {print $1; exit}')"
  if namespace_has_object_storage "$found_namespace"; then
    printf '%s' "$found_namespace"
    return 0
  fi

  die "failed to discover base object storage namespace; expected service ${OBJECT_STORAGE_SERVICE_NAME} and secret ${OBJECT_STORAGE_ADMIN_SECRET}"
}

build_prometheus_token() {
  local config_namespace="${1:-$OBJECT_STORAGE_NAMESPACE}"
  local minio_config_env
  local minio_root_user
  local minio_root_password
  local symmetric_key
  local header
  local payload
  local base64_header
  local base64_payload
  local base64_signature
  local token

  minio_config_env="$(required_resource_data secret "$config_namespace" object-storage-env-configuration 'config\.env' true)"
  minio_root_user="$(echo "${minio_config_env}" | tr ' ' '\n' | grep '^MINIO_ROOT_USER=' | cut -d '=' -f 2)"
  minio_root_user=${minio_root_user//\"}
  minio_root_password="$(echo "${minio_config_env}" | tr ' ' '\n' | grep '^MINIO_ROOT_PASSWORD=' | cut -d '=' -f 2)"
  minio_root_password=${minio_root_password//\"}

  [ -n "$minio_root_user" ] || die "MINIO_ROOT_USER not found in ${config_namespace}/object-storage-env-configuration"
  [ -n "$minio_root_password" ] || die "MINIO_ROOT_PASSWORD not found in ${config_namespace}/object-storage-env-configuration"

  symmetric_key=${minio_root_password}
  header='{"alg":"HS256","typ":"JWT"}'
  payload='{"exp":4833872336,"iss":"prometheus","sub":"'"${minio_root_user}"'"}'

  base64_header=$(echo -n "${header}" | base64 | tr -d '\n=' | tr '/+' '_-')
  base64_payload=$(echo -n "${payload}" | base64 | tr -d '\n=' | tr '/+' '_-')
  base64_signature=$(echo -n "${base64_header}.${base64_payload}" | openssl dgst -binary -sha256 -hmac "${symmetric_key}" | base64 | tr -d '\n=' | tr '/+' '_-')
  token="${base64_header}.${base64_payload}.${base64_signature}"
  echo -n "${token}" | base64 | tr -d '\n'
}

adopt_resource_for_helm() {
  local kind="$1"
  local name="$2"
  local namespace="${3:-}"

  if [ -n "$namespace" ]; then
    kubectl get "$kind" "$name" -n "$namespace" >/dev/null 2>&1 || return 0
    kubectl label "$kind" "$name" -n "$namespace" app.kubernetes.io/managed-by=Helm --overwrite >/dev/null
    kubectl annotate "$kind" "$name" -n "$namespace" \
      meta.helm.sh/release-name="$RELEASE_NAME" \
      meta.helm.sh/release-namespace="$RELEASE_NAMESPACE" \
      --overwrite >/dev/null
    return 0
  fi

  kubectl get "$kind" "$name" >/dev/null 2>&1 || return 0
  kubectl label "$kind" "$name" app.kubernetes.io/managed-by=Helm --overwrite >/dev/null
  kubectl annotate "$kind" "$name" \
    meta.helm.sh/release-name="$RELEASE_NAME" \
    meta.helm.sh/release-namespace="$RELEASE_NAMESPACE" \
    --overwrite >/dev/null
}

adopt_existing_objectstorage_resources() {
  info "Adopting existing objectstorage API/RBAC/App resources into release=${RELEASE_NAME}/${RELEASE_NAMESPACE}"
  adopt_resource_for_helm crd objectstoragebuckets.objectstorage.sealos.io
  adopt_resource_for_helm crd objectstorageusers.objectstorage.sealos.io
  adopt_resource_for_helm clusterrole objectstorage-manager-role
  adopt_resource_for_helm clusterrolebinding objectstorage-manager-rolebinding
  adopt_resource_for_helm app objectstorage app-system
}

wait_for_objectorstorage_rollout() {
  local timeout="${ROLLOUT_TIMEOUT:-5m}"

  kubectl rollout status deployment/objectstorage-controller-manager -n "$RELEASE_NAMESPACE" --timeout="$timeout"
  kubectl rollout status deployment/object-storage-frontend -n "$RELEASE_NAMESPACE" --timeout="$timeout"
}

cleanup_legacy_objectstorage_resources() {
  if [ "${CLEANUP_LEGACY_OBJECTSTORAGE:-true}" != "true" ]; then
    warn "Skipping legacy objectstorage cleanup because CLEANUP_LEGACY_OBJECTSTORAGE=${CLEANUP_LEGACY_OBJECTSTORAGE}"
    return 0
  fi

  if [ "$RELEASE_NAMESPACE" = "objectstorage-system" ] || [ "$RELEASE_NAMESPACE" = "objectstorage-frontend" ]; then
    warn "Skipping legacy cleanup because release namespace is ${RELEASE_NAMESPACE}"
    return 0
  fi

  info "Cleaning legacy objectstorage frontend/controller resources while preserving base object storage tenant"
  kubectl delete namespace objectstorage-frontend --ignore-not-found >/dev/null 2>&1 || true

  if [ "$OBJECT_STORAGE_NAMESPACE" = "objectstorage-system" ]; then
    kubectl delete deployment objectstorage-controller-manager object-storage-monitor-deployment -n objectstorage-system --ignore-not-found >/dev/null 2>&1 || true
    kubectl delete svc object-storage-monitor objectstorage-controller-manager-metrics-service -n objectstorage-system --ignore-not-found >/dev/null 2>&1 || true
    kubectl delete ingress object-storage-monitor -n objectstorage-system --ignore-not-found >/dev/null 2>&1 || true
    kubectl delete configmap object-storage-monitor-config -n objectstorage-system --ignore-not-found >/dev/null 2>&1 || true
    kubectl delete secret object-storage-probe -n objectstorage-system --ignore-not-found >/dev/null 2>&1 || true
    kubectl delete vmprobe object-storage-cluster object-storage-bucket -n objectstorage-system --ignore-not-found >/dev/null 2>&1 || true
    kubectl delete serviceaccount objectstorage-controller-manager -n objectstorage-system --ignore-not-found >/dev/null 2>&1 || true
    kubectl delete role objectstorage-leader-election-role -n objectstorage-system --ignore-not-found >/dev/null 2>&1 || true
    kubectl delete rolebinding objectstorage-leader-election-rolebinding -n objectstorage-system --ignore-not-found >/dev/null 2>&1 || true
  elif [ "$OBJECT_STORAGE_NAMESPACE" != "objectstorage-system" ]; then
    kubectl delete namespace objectstorage-system --ignore-not-found >/dev/null 2>&1 || true
  fi

  kubectl delete clusterrole objectstorage-metrics-reader objectstorage-proxy-role --ignore-not-found >/dev/null 2>&1 || true
  kubectl delete clusterrolebinding objectstorage-proxy-rolebinding --ignore-not-found >/dev/null 2>&1 || true
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RELEASE_NAME=${RELEASE_NAME:-"objectorstorage"}
RELEASE_NAMESPACE=${RELEASE_NAMESPACE:-${NAMESPACE:-"objectorstorage-system"}}
OBJECT_STORAGE_NAMESPACE=${OBJECT_STORAGE_NAMESPACE:-}
OBJECT_STORAGE_SERVICE_NAME=${OBJECT_STORAGE_SERVICE_NAME:-"object-storage"}
OBJECT_STORAGE_SERVICE_PORT=${OBJECT_STORAGE_SERVICE_PORT:-"80"}
OBJECT_STORAGE_ADMIN_SECRET=${OBJECT_STORAGE_ADMIN_SECRET:-"object-storage-user-0"}
CHART_PATH=${CHART_PATH:-"${SCRIPT_DIR}/charts/objectstorage"}
HELM_OPTS=${HELM_OPTS:-""}
SEALOS_SYSTEM_NS=${SEALOS_SYSTEM_NS:-"sealos-system"}
SEALOS_CONFIG_CM=${SEALOS_CONFIG_CM:-"sealos-config"}
APP_VALUES_DIR=${APP_VALUES_DIR:-"/root/.sealos/cloud/values/apps/objectstorage"}
GLOBAL_VALUES_FILE=${GLOBAL_VALUES_FILE:-"/root/.sealos/cloud/values/global.yaml"}
CHART_APP_VALUES_FILE=${CHART_APP_VALUES_FILE:-"${CHART_PATH}/objectstorage-values.yaml"}

[ -d "$CHART_PATH" ] || die "chart directory not found: ${CHART_PATH}"

for cmd in helm kubectl base64 openssl; do
  require_cmd "$cmd"
done

HELM_COMMON_ARGS=()

load_http_tools
ensure_http_tool_fallbacks

append_values_file_arg "$GLOBAL_VALUES_FILE" "global"
append_values_file_arg "$CHART_APP_VALUES_FILE" "apps/objectstorage default"
append_values_dir_args "$APP_VALUES_DIR" "apps/objectstorage"
OBJECT_STORAGE_NAMESPACE="$(detect_object_storage_namespace)"

CLOUD_DOMAIN="${SEALOS_CLOUD_DOMAIN:-${cloudDomain:-$(required_resource_data configmap "$SEALOS_SYSTEM_NS" "$SEALOS_CONFIG_CM" cloudDomain)}}"
SEALOS_JWT_INTERNAL="${SEALOS_JWT_INTERNAL:-${jwtInternal:-$(required_resource_data configmap "$SEALOS_SYSTEM_NS" "$SEALOS_CONFIG_CM" jwtInternal)}}"
PROMETHEUS_TOKEN="${PROMETHEUS_TOKEN:-}"
if [ -z "$PROMETHEUS_TOKEN" ]; then
  PROMETHEUS_TOKEN="$(build_prometheus_token "$OBJECT_STORAGE_NAMESPACE")"
fi

SEALOS_CLOUD_PORT="${SEALOS_CLOUD_PORT:-${cloudPort:-$(read_yaml_file_path '.global.http.httpsPort')}}"
SEALOS_HTTP_PORT="${SEALOS_HTTP_PORT:-${httpPort:-$(read_yaml_file_path '.global.http.httpPort')}}"
SEALOS_CERT_SECRET_NAME="${SEALOS_CERT_SECRET_NAME:-${certSecretName:-$(read_yaml_file_path '.global.http.certSecretName')}}"
SEALOS_CERT_SECRET_NAME="${SEALOS_CERT_SECRET_NAME:-wildcard-cert}"

if global_http_disable_https; then
  SEALOS_DISABLE_HTTPS="true"
else
  SEALOS_DISABLE_HTTPS="false"
fi

TLS_REJECT_UNAUTHORIZED="$(read_cert_tls_reject_unauthorized)"
FRONTEND_HOST="${FRONTEND_HOST:-objectstorage.${CLOUD_DOMAIN}}"
FRONTEND_URL="$(global_http_external_url "${FRONTEND_HOST}")"
OBJECT_STORAGE_INTERNAL_ENDPOINT="${OBJECT_STORAGE_INTERNAL_ENDPOINT:-${OBJECT_STORAGE_SERVICE_NAME}.${OBJECT_STORAGE_NAMESPACE}.svc.cluster.local:${OBJECT_STORAGE_SERVICE_PORT}}"
OBJECT_STORAGE_EXTERNAL_HOST="${OBJECT_STORAGE_EXTERNAL_HOST:-objectstorageapi.${CLOUD_DOMAIN}}"
OBJECT_STORAGE_METRICS_INSTANCE="${OBJECT_STORAGE_METRICS_INSTANCE:-$OBJECT_STORAGE_INTERNAL_ENDPOINT}"

info "Preparing release=${RELEASE_NAME}, namespace=${RELEASE_NAMESPACE}, chart=${CHART_PATH}"
info "ObjectStorage frontend URL=${FRONTEND_URL}, disableHttps=${SEALOS_DISABLE_HTTPS}, tlsRejectUnauthorized=${TLS_REJECT_UNAUTHORIZED}"
info "Using base object storage namespace=${OBJECT_STORAGE_NAMESPACE}, endpoint=${OBJECT_STORAGE_INTERNAL_ENDPOINT}"

append_set_string_if_present "$CLOUD_DOMAIN" "objectstorageConfig.cloudDomain"
append_set_string_if_present "$CLOUD_DOMAIN" "cloudDomain"
append_set_string_if_present "$SEALOS_CLOUD_PORT" "objectstorageConfig.cloudPort"
append_set_string_if_present "$SEALOS_CLOUD_PORT" "cloudPort"
append_set_string_if_present "$SEALOS_HTTP_PORT" "objectstorageConfig.httpPort"
append_set_string_if_present "$SEALOS_HTTP_PORT" "httpPort"
append_set_string_if_present "$SEALOS_DISABLE_HTTPS" "objectstorageConfig.disableHttps"
append_set_string_if_present "$SEALOS_DISABLE_HTTPS" "disableHttps"
append_set_string_if_present "$SEALOS_CERT_SECRET_NAME" "objectstorageConfig.certSecretName"
append_set_string_if_present "$SEALOS_CERT_SECRET_NAME" "certSecretName"
append_set_string_if_present "$SEALOS_JWT_INTERNAL" "objectstorageConfig.appTokenJwtKey"
append_set_string_if_present "$PROMETHEUS_TOKEN" "objectstorageConfig.prometheusToken"
append_set_string_if_present "$OBJECT_STORAGE_NAMESPACE" "controller.osNamespace"
append_set_string_if_present "$OBJECT_STORAGE_NAMESPACE" "objectStorage.namespace"
append_set_string_if_present "$OBJECT_STORAGE_SERVICE_NAME" "objectStorage.serviceName"
append_set_string_if_present "$OBJECT_STORAGE_SERVICE_PORT" "objectStorage.servicePort"
append_set_string_if_present "$OBJECT_STORAGE_ADMIN_SECRET" "controller.osAdminSecret"
append_set_string_if_present "$OBJECT_STORAGE_ADMIN_SECRET" "objectStorage.adminSecret"
append_set_string_if_present "$OBJECT_STORAGE_INTERNAL_ENDPOINT" "controller.osInternalEndpoint"
append_set_string_if_present "$OBJECT_STORAGE_EXTERNAL_HOST" "controller.osExternalEndpoint"
append_set_string_if_present "$OBJECT_STORAGE_EXTERNAL_HOST" "objectStorage.externalHost"
append_set_string_if_present "$OBJECT_STORAGE_METRICS_INSTANCE" "controller.objectStorageService.metricsInstance"
append_set_string_if_present "$OBJECT_STORAGE_METRICS_INSTANCE" "objectStorage.metricsInstance"
append_set_string_if_present "${monitorUrl:-}" "objectstorageConfig.monitorUrl"
append_set_string_if_present "${billingUrl:-}" "objectstorageConfig.billingUrl"
append_set_string_if_present "${billingSecret:-}" "objectstorageConfig.billingSecret"
append_set_string_if_present "${appLaunchpadUrl:-}" "objectstorageConfig.appLaunchpadUrl"
append_set_string_if_present "${hostingPodCpuMilliCores:-}" "objectstorageConfig.hostingPodCpuMilliCores"
append_set_string_if_present "${hostingPodMemoryMiB:-}" "objectstorageConfig.hostingPodMemoryMiB"
append_set_string_if_present "${hostingAppNamePrefix:-}" "objectstorageConfig.hostingAppNamePrefix"
append_set_string_if_present "${hostingNetworkProtocol:-}" "objectstorageConfig.hostingNetworkProtocol"
append_set_string_if_present "${hostingNetworkPort:-}" "objectstorageConfig.hostingNetworkPort"
HELM_COMMON_ARGS+=(--set-string "platform.tlsRejectUnauthorized=${TLS_REJECT_UNAUTHORIZED}")

adopt_existing_objectstorage_resources

helm upgrade -i "${RELEASE_NAME}" "${CHART_PATH}" -n "${RELEASE_NAMESPACE}" --create-namespace \
  "${HELM_COMMON_ARGS[@]}" \
  ${HELM_OPTS}

wait_for_objectorstorage_rollout
cleanup_legacy_objectstorage_resources
