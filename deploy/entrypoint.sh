#!/usr/bin/env bash
set -e

load_cloud_tools_or_exit() {
  local tools_file="/root/.sealos/cloud/scripts/tools.sh"
  local required_functions=(
    ensure_global_values_ready_for_component
    read_yaml_file_path
    global_http_disable_https
    global_http_external_url
    get_cm_value
    read_cert_tls_reject_unauthorized
    read_jwt_internal
    read_prometheus_url
    read_account_service_name
    info
    warn
    error
  )
  local missing_functions=()
  local function_name

  if [ ! -f "$tools_file" ]; then
    cat >&2 <<'EOF'
错误：未找到 /root/.sealos/cloud/scripts/tools.sh，当前组件镜像无法继续执行。

请先回到当前安装包目录，执行对应命令同步 values + tools：
  Pro 安装包：./sealos-pro.sh sync-config
  OSS 安装包：./sealos-oss.sh sync-config
EOF
    exit 1
  fi

  # shellcheck source=/dev/null
  source "$tools_file"

  for function_name in "${required_functions[@]}"; do
    if ! declare -f "$function_name" >/dev/null 2>&1; then
      missing_functions+=("$function_name")
    fi
  done

  if [ "${#missing_functions[@]}" -gt 0 ]; then
    cat >&2 <<EOF
错误：/root/.sealos/cloud/scripts/tools.sh 版本过旧，缺少配置检测函数，当前组件镜像无法继续执行。

缺少函数：${missing_functions[*]}

请先回到当前安装包目录，执行对应命令同步 values + tools：
  Pro 安装包：./sealos-pro.sh sync-config
  OSS 安装包：./sealos-oss.sh sync-config
EOF
    exit 1
  fi

  ensure_global_values_ready_for_component
}

read_billing_config() {
  local account_namespace="account-system"
  local account_configmap="account-manager-env"
  local account_svc_port=""

  BILLING_SECRET="${BILLING_SECRET:-${billingSecret:-}}"
  if [ -z "$BILLING_SECRET" ]; then
    BILLING_SECRET="$(get_cm_value "$account_namespace" "$account_configmap" ACCOUNT_API_JWT_SECRET 1 0)"
  fi

  BILLING_URL="${BILLING_URL:-${billingUrl:-}}"
  if [ -z "$BILLING_URL" ]; then
    ACCOUNT_SVC_NAME="${ACCOUNT_SVC_NAME:-$(read_account_service_name)}"
    if [ -n "$ACCOUNT_SVC_NAME" ] && kubectl get svc "$ACCOUNT_SVC_NAME" -n "$account_namespace" >/dev/null 2>&1; then
      account_svc_port="$(kubectl get svc "$ACCOUNT_SVC_NAME" -n "$account_namespace" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || true)"
      account_svc_port="${account_svc_port:-2333}"
      BILLING_URL="http://${ACCOUNT_SVC_NAME}.${account_namespace}.svc:${account_svc_port}"
    fi
  fi

  if [ -z "$BILLING_SECRET" ]; then
    warn "Billing secret not found from ${account_namespace}/${account_configmap}.ACCOUNT_API_JWT_SECRET"
  fi
  if [ -z "$BILLING_URL" ]; then
    warn "Billing service not found by selector app.kubernetes.io/instance=account-controller in namespace ${account_namespace}"
  fi
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

  error "failed to discover base object storage namespace; expected service ${OBJECT_STORAGE_SERVICE_NAME} and secret ${OBJECT_STORAGE_ADMIN_SECRET}"
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

  minio_config_env="$(kubectl get secret object-storage-env-configuration -n "$config_namespace" -o jsonpath='{.data.config\.env}' 2>/dev/null || true)"
  [ -n "$minio_config_env" ] || error "missing required field: secret ${config_namespace}/object-storage-env-configuration data.config.env"
  minio_config_env="$(printf '%s' "$minio_config_env" | base64 --decode)"
  minio_root_user="$(echo "${minio_config_env}" | tr ' ' '\n' | grep '^MINIO_ROOT_USER=' | cut -d '=' -f 2)"
  minio_root_user=${minio_root_user//\"}
  minio_root_password="$(echo "${minio_config_env}" | tr ' ' '\n' | grep '^MINIO_ROOT_PASSWORD=' | cut -d '=' -f 2)"
  minio_root_password=${minio_root_password//\"}

  [ -n "$minio_root_user" ] || error "MINIO_ROOT_USER not found in ${config_namespace}/object-storage-env-configuration"
  [ -n "$minio_root_password" ] || error "MINIO_ROOT_PASSWORD not found in ${config_namespace}/object-storage-env-configuration"

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
OBJECT_STORAGE_ADMIN_SECRET=${OBJECT_STORAGE_ADMIN_SECRET:-"object-storage-user-0"}
CHART_PATH=${CHART_PATH:-"${SCRIPT_DIR}/charts/objectstorage"}
HELM_OPTS=${HELM_OPTS:-""}
SEALOS_SYSTEM_NS=${SEALOS_SYSTEM_NS:-"sealos-system"}
SEALOS_CONFIG_CM=${SEALOS_CONFIG_CM:-"sealos-config"}
SEALOS_GLOBAL_VALUES_FILE=${SEALOS_GLOBAL_VALUES_FILE:-"/root/.sealos/cloud/values/global.yaml"}
PACKAGED_APP_VALUES_FILE=${PACKAGED_APP_VALUES_FILE:-${CHART_APP_VALUES_FILE:-"${CHART_PATH}/objectstorage-values.yaml"}}
APP_VALUES_DIR=${APP_VALUES_DIR:-"/root/.sealos/cloud/values/apps/objectstorage"}

[ -d "$CHART_PATH" ] || {
  echo "chart directory not found: ${CHART_PATH}" >&2
  exit 1
}

HELM_COMMON_ARGS=()

load_cloud_tools_or_exit

for cmd in helm kubectl base64 openssl; do
  command -v "$cmd" >/dev/null 2>&1 || error "missing required command: ${cmd}"
done

if [ -f "$PACKAGED_APP_VALUES_FILE" ]; then
  info "Using apps/objectstorage default Helm values from ${PACKAGED_APP_VALUES_FILE}"
  HELM_COMMON_ARGS+=("-f" "$PACKAGED_APP_VALUES_FILE")
else
  warn "apps/objectstorage default values file ${PACKAGED_APP_VALUES_FILE} not found, proceeding without it"
fi

if [ -d "$APP_VALUES_DIR" ]; then
  while IFS= read -r values_file; do
    info "Using apps/objectstorage Helm values from ${values_file}"
    HELM_COMMON_ARGS+=("-f" "$values_file")
  done < <(find "$APP_VALUES_DIR" -maxdepth 1 -type f \( -name '*-values.yaml' -o -name '*-values.yml' \) | sort)
else
  warn "apps/objectstorage values directory ${APP_VALUES_DIR} not found, proceeding without it"
fi
OBJECT_STORAGE_NAMESPACE="$(detect_object_storage_namespace)"

CLOUD_DOMAIN="${SEALOS_CLOUD_DOMAIN:-${cloudDomain:-$(get_cm_value "$SEALOS_SYSTEM_NS" "$SEALOS_CONFIG_CM" cloudDomain 1 0)}}"
[ -n "$CLOUD_DOMAIN" ] || error "missing required field: configmap ${SEALOS_SYSTEM_NS}/${SEALOS_CONFIG_CM} data.cloudDomain"
SEALOS_JWT_INTERNAL="${SEALOS_JWT_INTERNAL:-${jwtInternal:-$(read_jwt_internal)}}"
read_billing_config
PROMETHEUS_URL="${PROMETHEUS_URL:-$(read_prometheus_url)}"
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

# read_cert_tls_reject_unauthorized reads sealos-system/cert-config CERT_MODE:
# https|acme|acmedns -> printf '0', other modes -> printf '1'.
TLS_REJECT_UNAUTHORIZED="$(read_cert_tls_reject_unauthorized)"
FRONTEND_HOST="${FRONTEND_HOST:-objectstorage.${CLOUD_DOMAIN}}"
FRONTEND_URL="$(global_http_external_url "${FRONTEND_HOST}")"
OBJECT_STORAGE_INTERNAL_ENDPOINT="${OBJECT_STORAGE_INTERNAL_ENDPOINT:-object-storage.${OBJECT_STORAGE_NAMESPACE}.svc.cluster.local:80}"
OBJECT_STORAGE_EXTERNAL_HOST="${OBJECT_STORAGE_EXTERNAL_HOST:-objectstorageapi.${CLOUD_DOMAIN}}"

info "Preparing release=${RELEASE_NAME}, namespace=${RELEASE_NAMESPACE}, chart=${CHART_PATH}"
info "ObjectStorage frontend URL=${FRONTEND_URL}, disableHttps=${SEALOS_DISABLE_HTTPS}, tlsRejectUnauthorized=${TLS_REJECT_UNAUTHORIZED}"
info "Using base object storage namespace=${OBJECT_STORAGE_NAMESPACE}, endpoint=${OBJECT_STORAGE_INTERNAL_ENDPOINT}"

[ -n "$CLOUD_DOMAIN" ] && HELM_COMMON_ARGS+=("--set-string" "cloudDomain=${CLOUD_DOMAIN}")
[ -n "$SEALOS_CLOUD_PORT" ] && HELM_COMMON_ARGS+=("--set-string" "cloudPort=${SEALOS_CLOUD_PORT}")
[ -n "$SEALOS_HTTP_PORT" ] && HELM_COMMON_ARGS+=("--set-string" "httpPort=${SEALOS_HTTP_PORT}")
[ -n "$SEALOS_DISABLE_HTTPS" ] && HELM_COMMON_ARGS+=("--set-string" "disableHttps=${SEALOS_DISABLE_HTTPS}")
[ -n "$SEALOS_CERT_SECRET_NAME" ] && HELM_COMMON_ARGS+=("--set-string" "certSecretName=${SEALOS_CERT_SECRET_NAME}")
[ -n "$SEALOS_JWT_INTERNAL" ] && HELM_COMMON_ARGS+=("--set-string" "objectstorageConfig.appTokenJwtKey=${SEALOS_JWT_INTERNAL}")
[ -n "$PROMETHEUS_URL" ] && HELM_COMMON_ARGS+=("--set-string" "objectstorageConfig.monitor.prometheusUrl=${PROMETHEUS_URL}")
[ -n "$PROMETHEUS_TOKEN" ] && HELM_COMMON_ARGS+=("--set-string" "objectstorageConfig.monitor.prometheusToken=${PROMETHEUS_TOKEN}")
[ -n "$BILLING_URL" ] && HELM_COMMON_ARGS+=("--set-string" "objectstorageConfig.billingUrl=${BILLING_URL}")
[ -n "$BILLING_SECRET" ] && HELM_COMMON_ARGS+=("--set-string" "objectstorageConfig.billingSecret=${BILLING_SECRET}")
[ -n "$OBJECT_STORAGE_NAMESPACE" ] && HELM_COMMON_ARGS+=("--set-string" "objectstorageConfig.minio.namespace=${OBJECT_STORAGE_NAMESPACE}")
[ -n "$OBJECT_STORAGE_EXTERNAL_HOST" ] && HELM_COMMON_ARGS+=("--set-string" "objectstorageConfig.minio.externalHost=${OBJECT_STORAGE_EXTERNAL_HOST}")
HELM_COMMON_ARGS+=(--set-string "platform.tlsRejectUnauthorized=${TLS_REJECT_UNAUTHORIZED}")

adopt_existing_objectstorage_resources

helm upgrade -i "${RELEASE_NAME}" "${CHART_PATH}" -n "${RELEASE_NAMESPACE}" --create-namespace \
  "${HELM_COMMON_ARGS[@]}" \
  ${HELM_OPTS}

wait_for_objectorstorage_rollout
cleanup_legacy_objectstorage_resources
