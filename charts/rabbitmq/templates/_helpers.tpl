{{- define "rabbitmq.fullname" -}}
{{- printf "%s-rabbitmq" .Release.Name }}
{{- end }}
