{{- define "service.name" -}}
{{- .Values.nameOverride | default .Chart.Name }}
{{- end }}

{{- define "service.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "service.name" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "service.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | trunc 63 }}
app.kubernetes.io/name: {{ include "service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
