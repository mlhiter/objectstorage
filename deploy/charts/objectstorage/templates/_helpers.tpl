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
{{- $disableHttps := default .Values.objectstorageConfig.disableHttps .Values.disableHttps -}}
{{- if eq (toString $disableHttps) "true" -}}http{{- else -}}https{{- end -}}
{{- end }}

{{- define "objectstorage.port" -}}
{{- $scheme := include "objectstorage.scheme" . -}}
{{- $port := toString (default .Values.objectstorageConfig.cloudPort .Values.cloudPort) -}}
{{- if eq $scheme "http" -}}
{{- $port = toString (default .Values.objectstorageConfig.httpPort .Values.httpPort) -}}
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
{{- include "objectstorage.scheme" . -}}://{{ default .Values.objectstorageConfig.cloudDomain .Values.cloudDomain }}{{ include "objectstorage.portSuffix" . }}
{{- end }}

{{- define "objectstorage.wildcardCloudOrigin" -}}
{{- include "objectstorage.scheme" . -}}://*.{{ default .Values.objectstorageConfig.cloudDomain .Values.cloudDomain }}{{ include "objectstorage.portSuffix" . }}
{{- end }}

{{- define "objectstorage.host" -}}
{{- $cloudDomain := default .Values.objectstorageConfig.cloudDomain .Values.cloudDomain -}}
{{- default (printf "objectstorage.%s" $cloudDomain) .Values.frontend.ingress.host -}}
{{- end }}

{{- define "objectstorage.appUrl" -}}
{{- include "objectstorage.scheme" . -}}://{{ include "objectstorage.host" . }}{{ include "objectstorage.portSuffix" . }}
{{- end }}

{{- define "objectstorage.apiHost" -}}
{{- $cloudDomain := default .Values.objectstorageConfig.cloudDomain .Values.cloudDomain -}}
{{- $externalHost := default .Values.objectStorage.externalHost .Values.controller.osExternalEndpoint -}}
{{- default (printf "objectstorageapi.%s" $cloudDomain) $externalHost -}}
{{- end }}

{{- define "objectstorage.apiOrigin" -}}
{{- include "objectstorage.scheme" . -}}://{{ include "objectstorage.apiHost" . }}{{ include "objectstorage.portSuffix" . }}
{{- end }}

{{- define "objectstorage.objectStorageNamespace" -}}
{{- default "objectstorage-system" (default .Values.objectStorage.namespace .Values.controller.osNamespace) -}}
{{- end }}

{{- define "objectstorage.objectStorageAdminSecret" -}}
{{- default "object-storage-user-0" (default .Values.objectStorage.adminSecret .Values.controller.osAdminSecret) -}}
{{- end }}

{{- define "objectstorage.objectStorageEndpoint" -}}
{{- if .Values.controller.osInternalEndpoint -}}
{{- .Values.controller.osInternalEndpoint -}}
{{- else -}}
{{- $serviceName := default "object-storage" .Values.objectStorage.serviceName -}}
{{- $servicePort := default 80 .Values.objectStorage.servicePort -}}
{{- printf "%s.%s.svc.cluster.local:%v" $serviceName (include "objectstorage.objectStorageNamespace" .) $servicePort -}}
{{- end -}}
{{- end }}

{{- define "objectstorage.objectStorageMetricsInstance" -}}
{{- $metricsInstance := default .Values.objectStorage.metricsInstance .Values.controller.objectStorageService.metricsInstance -}}
{{- default (include "objectstorage.objectStorageEndpoint" .) $metricsInstance -}}
{{- end }}

{{- define "objectstorage.monitorServiceName" -}}
{{- default "object-storage-monitor" .Values.controller.monitor.serviceName -}}
{{- end }}

{{- define "objectstorage.monitorHost" -}}
{{- $cloudDomain := default .Values.objectstorageConfig.cloudDomain .Values.cloudDomain -}}
{{- default (printf "object-storage-monitor.%s" $cloudDomain) .Values.controller.monitor.ingress.host -}}
{{- end }}

{{- define "objectstorage.monitorUrl" -}}
{{- if .Values.objectstorageConfig.monitorUrl -}}
{{- .Values.objectstorageConfig.monitorUrl -}}
{{- else -}}
{{- printf "http://%s.%s.svc.cluster.local:%v/q" (include "objectstorage.monitorServiceName" .) .Release.Namespace .Values.controller.monitor.service.port -}}
{{- end -}}
{{- end }}
