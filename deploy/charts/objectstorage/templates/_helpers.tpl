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
{{- if eq (toString .Values.objectstorageConfig.disableHttps) "true" -}}http{{- else -}}https{{- end -}}
{{- end }}

{{- define "objectstorage.port" -}}
{{- $scheme := include "objectstorage.scheme" . -}}
{{- $port := toString .Values.objectstorageConfig.cloudPort -}}
{{- if eq $scheme "http" -}}
{{- $port = toString .Values.objectstorageConfig.httpPort -}}
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
{{- include "objectstorage.scheme" . -}}://{{ .Values.objectstorageConfig.cloudDomain }}{{ include "objectstorage.portSuffix" . }}
{{- end }}

{{- define "objectstorage.wildcardCloudOrigin" -}}
{{- include "objectstorage.scheme" . -}}://*.{{ .Values.objectstorageConfig.cloudDomain }}{{ include "objectstorage.portSuffix" . }}
{{- end }}

{{- define "objectstorage.host" -}}
{{- default (printf "objectstorage.%s" .Values.objectstorageConfig.cloudDomain) .Values.frontend.ingress.host -}}
{{- end }}

{{- define "objectstorage.appUrl" -}}
{{- include "objectstorage.scheme" . -}}://{{ include "objectstorage.host" . }}{{ include "objectstorage.portSuffix" . }}
{{- end }}
