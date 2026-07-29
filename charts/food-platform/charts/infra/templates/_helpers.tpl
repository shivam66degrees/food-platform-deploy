{{- define "infra.postgresName" -}}
{{- printf "%s-postgres" .name }}
{{- end }}

{{- define "infra.labels" -}}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
helm.sh/chart: infra-{{ .Chart.Version }}
{{- end }}
