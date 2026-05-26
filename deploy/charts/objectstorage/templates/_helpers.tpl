{{/* Expand the name of the chart. */}}
{{- define "objectstorage.name" -}}
{{- default .Chart.Name .Values.frontend.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Create a default fully qualified app name. */}}
{{- define "objectstorage.fullname" -}}
{{- if .Values.frontend.fullnameOverride }}
{{- .Values.frontend.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.frontend.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "objectstorage.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "objectstorage.labels" -}}
helm.sh/chart: {{ include "objectstorage.chart" . }}
{{ include "objectstorage.selectorLabels" . }}
{{ include "objectstorage.recommendedLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "objectstorage.selectorLabels" -}}
app: {{ include "objectstorage.fullname" . }}
{{- end }}

{{- define "objectstorage.recommendedLabels" -}}
app.kubernetes.io/name: {{ include "objectstorage.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "objectstorage.scheme" -}}
{{- $disableHttps := .Values.disableHttps -}}
{{- if eq (toString $disableHttps) "true" -}}http{{- else -}}https{{- end -}}
{{- end }}

{{- define "objectstorage.port" -}}
{{- $scheme := include "objectstorage.scheme" . -}}
{{- $port := toString .Values.cloudPort -}}
{{- if eq $scheme "http" -}}
{{- $port = toString .Values.httpPort -}}
{{- end -}}
{{- if or (and (eq $scheme "https") (or (eq $port "") (eq $port "443"))) (and (eq $scheme "http") (or (eq $port "") (eq $port "80"))) -}}
{{- "" -}}
{{- else -}}
{{- $port -}}
{{- end }}
{{- end }}

{{- define "objectstorage.portSuffix" -}}
{{- $port := include "objectstorage.port" . -}}
{{- if $port -}}:{{ $port }}{{- end -}}
{{- end }}

{{- define "objectstorage.portEnv" -}}
{{- $port := include "objectstorage.port" . -}}
{{- if $port -}}:{{ $port }}{{- end -}}
{{- end }}

{{- define "objectstorage.cloudOrigin" -}}
{{- include "objectstorage.scheme" . -}}://{{ .Values.cloudDomain }}{{ include "objectstorage.portSuffix" . }}
{{- end }}

{{- define "objectstorage.wildcardCloudOrigin" -}}
{{- include "objectstorage.scheme" . -}}://*.{{ .Values.cloudDomain }}{{ include "objectstorage.portSuffix" . }}
{{- end }}

{{- define "objectstorage.host" -}}
{{- $cloudDomain := .Values.cloudDomain -}}
{{- default (printf "objectstorage.%s" $cloudDomain) .Values.frontend.ingress.host -}}
{{- end }}

{{- define "objectstorage.appUrl" -}}
{{- include "objectstorage.scheme" . -}}://{{ include "objectstorage.host" . }}{{ include "objectstorage.portSuffix" . }}
{{- end }}

{{- define "objectstorage.apiHost" -}}
{{- default (printf "objectstorageapi.%s" .Values.cloudDomain) .Values.objectstorageConfig.minio.externalHost -}}
{{- end }}

{{- define "objectstorage.apiOrigin" -}}
{{- include "objectstorage.scheme" . -}}://{{ include "objectstorage.apiHost" . }}{{ include "objectstorage.portSuffix" . }}
{{- end }}

{{- define "objectstorage.objectStorageNamespace" -}}
{{- default "objectstorage-system" .Values.objectstorageConfig.minio.namespace -}}
{{- end }}

{{- define "objectstorage.objectStorageAdminSecret" -}}
object-storage-user-0
{{- end }}

{{- define "objectstorage.objectStorageEndpoint" -}}
{{- printf "object-storage.%s.svc.cluster.local:80" (include "objectstorage.objectStorageNamespace" .) -}}
{{- end }}

{{- define "objectstorage.monitorServiceName" -}}
{{- default "object-storage-monitor" .Values.controller.monitor.serviceName -}}
{{- end }}

{{- define "objectstorage.monitorHost" -}}
{{- $cloudDomain := .Values.cloudDomain -}}
{{- default (printf "object-storage-monitor.%s" $cloudDomain) .Values.objectstorageConfig.monitor.externalHost -}}
{{- end }}

{{- define "objectstorage.monitorUrl" -}}
{{- printf "http://%s.%s.svc.cluster.local:%v/q" (include "objectstorage.monitorServiceName" .) .Release.Namespace .Values.controller.monitor.service.port -}}
{{- end }}
