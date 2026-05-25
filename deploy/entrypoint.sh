#!/usr/bin/env bash
set -euo pipefail

RELEASE_NAME=${RELEASE_NAME:-"objectstorage"}
RELEASE_NAMESPACE=${RELEASE_NAMESPACE:-"objectstorage-frontend"}
CHART_PATH=${CHART_PATH:-"./charts/objectstorage"}
HELM_OPTS=${HELM_OPTS:-""}

get_cm_value() {
  local namespace="$1"
  local name="$2"
  local key="$3"
  kubectl get configmap "${name}" -n "${namespace}" -o "jsonpath={.data.${key}}" 2>/dev/null || true
}

helm_args=()
add_set_string() {
  local key="$1"
  local value="$2"
  if [ -n "${value}" ]; then
    helm_args+=(--set-string "${key}=${value}")
  fi
}

SEALOS_CLOUD_DOMAIN=${SEALOS_CLOUD_DOMAIN:-"${cloudDomain:-$(get_cm_value sealos-system sealos-config cloudDomain)}"}
SEALOS_CLOUD_PORT=${SEALOS_CLOUD_PORT:-"${cloudPort:-$(get_cm_value sealos-system sealos-config cloudPort)}"}
SEALOS_HTTP_PORT=${SEALOS_HTTP_PORT:-"${httpPort:-$(get_cm_value sealos-system sealos-config httpPort)}"}
SEALOS_DISABLE_HTTPS=${SEALOS_DISABLE_HTTPS:-"${disableHttps:-$(get_cm_value sealos-system sealos-config disableHttps)}"}
SEALOS_CERT_SECRET_NAME=${SEALOS_CERT_SECRET_NAME:-"${certSecretName:-$(get_cm_value sealos-system sealos-config certSecretName)}"}
SEALOS_JWT_INTERNAL=${SEALOS_JWT_INTERNAL:-"${jwtInternal:-$(get_cm_value sealos-system sealos-config jwtInternal)}"}

add_set_string objectstorageConfig.cloudDomain "${SEALOS_CLOUD_DOMAIN}"
add_set_string objectstorageConfig.cloudPort "${SEALOS_CLOUD_PORT}"
add_set_string objectstorageConfig.httpPort "${SEALOS_HTTP_PORT}"
add_set_string objectstorageConfig.disableHttps "${SEALOS_DISABLE_HTTPS}"
add_set_string objectstorageConfig.certSecretName "${SEALOS_CERT_SECRET_NAME}"
add_set_string objectstorageConfig.appTokenJwtKey "${SEALOS_JWT_INTERNAL}"
add_set_string objectstorageConfig.monitorUrl "${monitorUrl:-}"
add_set_string objectstorageConfig.billingUrl "${billingUrl:-}"
add_set_string objectstorageConfig.billingSecret "${billingSecret:-}"
add_set_string objectstorageConfig.appLaunchpadUrl "${appLaunchpadUrl:-}"
add_set_string objectstorageConfig.hostingPodCpuMilliCores "${hostingPodCpuMilliCores:-}"
add_set_string objectstorageConfig.hostingPodMemoryMiB "${hostingPodMemoryMiB:-}"
add_set_string objectstorageConfig.hostingAppNamePrefix "${hostingAppNamePrefix:-}"
add_set_string objectstorageConfig.hostingNetworkProtocol "${hostingNetworkProtocol:-}"
add_set_string objectstorageConfig.hostingNetworkPort "${hostingNetworkPort:-}"

MINIO_CONFIG_ENV=$(kubectl -n objectstorage-system get secret object-storage-env-configuration -o jsonpath="{.data.config\.env}" | base64 --decode)
MINIO_ROOT_USER=$(echo "${MINIO_CONFIG_ENV}" | tr ' ' '\n' | grep '^MINIO_ROOT_USER=' | cut -d '=' -f 2)
MINIO_ROOT_USER=${MINIO_ROOT_USER//\"}
MINIO_ROOT_PASSWORD=$(echo "${MINIO_CONFIG_ENV}" | tr ' ' '\n' | grep '^MINIO_ROOT_PASSWORD=' | cut -d '=' -f 2)
MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD//\"}

SYMMETRIC_KEY=${MINIO_ROOT_PASSWORD}
HEADER='{"alg":"HS256","typ":"JWT"}'
PAYLOAD='{"exp":4833872336,"iss":"prometheus","sub":"'"${MINIO_ROOT_USER}"'"}'

BASE64_HEADER=$(echo -n "${HEADER}" | base64 | tr -d '\n=' | tr '/+' '_-')
BASE64_PAYLOAD=$(echo -n "${PAYLOAD}" | base64 | tr -d '\n=' | tr '/+' '_-')
BASE64_SIGNATURE=$(echo -n "${BASE64_HEADER}.${BASE64_PAYLOAD}" | openssl dgst -binary -sha256 -hmac "${SYMMETRIC_KEY}" | base64 | tr -d '\n=' | tr '/+' '_-')
TOKEN="${BASE64_HEADER}.${BASE64_PAYLOAD}.${BASE64_SIGNATURE}"
BASE64_TOKEN=$(echo -n "${TOKEN}" | base64 -w 0)
add_set_string objectstorageConfig.prometheusToken "${BASE64_TOKEN}"

helm_opts_arr=()
if [ -n "${HELM_OPTS}" ]; then
  # shellcheck disable=SC2206
  helm_opts_arr=(${HELM_OPTS})
fi

helm upgrade -i "${RELEASE_NAME}" -n "${RELEASE_NAMESPACE}" --create-namespace "${CHART_PATH}" \
  "${helm_args[@]}" \
  "${helm_opts_arr[@]}"
