{{/**
Copyright (C) 2017-2019 Dremio Corporation. This file is confidential and private property.
**/}}

{{/*
Telemetry - Pod Annotations
*/}}
{{- define "dremio.telemetry.podAnnotations" -}}
{{- $podAnnotations := coalesce $.Values.telemetry.podAnnotations $.Values.podAnnotations -}}
{{- if $podAnnotations -}}
{{ toYaml $podAnnotations }}
{{- end -}}
{{- end -}}

{{/*
Telemetry - Pod Node Selectors
*/}}
{{- define "dremio.telemetry.nodeSelector" -}}
{{- $telemetryNodeSelector := coalesce $.Values.telemetry.nodeSelector $.Values.nodeSelector -}}
{{- if $telemetryNodeSelector -}}
nodeSelector:
  {{- toYaml $telemetryNodeSelector | nindent 2 }}
{{- end -}}
{{- end -}}

{{/*
Telemetry - PriorityClassName
*/}}
{{- define "dremio.telemetry.priorityClassName" -}}
{{- if $.Values.telemetry.priorityClassName -}}
priorityClassName: {{ $.Values.telemetry.priorityClassName }}
{{- end -}}
{{- end -}}

{{/*
Telemetry - Tolerations
*/}}
{{- define "dremio.telemetry.tolerations" -}}
{{- $tolerations := coalesce $.Values.telemetry.tolerations $.Values.tolerations -}}
{{- if $tolerations -}}
tolerations:
  {{- toYaml $tolerations | nindent 2 }}
{{- end -}}
{{- end -}}

{{/*
Telemetry - Annotations
*/}}
{{- define "dremio.telemetry.annotations" -}}
{{- $annotations := coalesce $.Values.telemetry.annotations $.Values.annotations -}}
{{- if $annotations -}}
annotations:
  {{- toYaml $annotations | nindent 2 }}
{{- end -}}
{{- end -}}

{{/*
Telemetry - Pod Labels
*/}}
{{- define "dremio.telemetry.podLabels" -}}
{{- $podLabels := coalesce $.Values.telemetry.podLabels $.Values.podLabels -}}
{{- if $podLabels -}}
{{ toYaml $podLabels }}
{{- end -}}
{{- end -}}

{{/*
Telemetry Cluster ID - PriorityClassName
*/}}
{{- define "dremio.telemetry.clusterId.priorityClassName" -}}
{{- $priority := coalesce $.Values.telemetry.clusterId.priorityClassName $.Values.telemetry.priorityClassName -}}
{{- if $priority -}}
priorityClassName: {{ $priority }}
{{- end -}}
{{- end -}}

{{/*
Telemetry - Pod Security Context
*/}}
{{- define "dremio.telemetry.podSecurityContext" -}}
{{- $context := coalesce .Values.telemetry.podSecurityContext (include "dremio.podSecurityContext" . | fromYaml).securityContext -}}
{{- if $context }}
securityContext:
  {{- toYaml $context | nindent 2 }}
{{- end }}
{{- end -}}

{{/*
Telemetry - Container Security Context
*/}}
{{- define "dremio.telemetry.containerSecurityContext" -}}
{{- $context := coalesce .Values.telemetry.containerSecurityContext (include "dremio.containerSecurityContext" . | fromYaml).securityContext -}}
{{- if $context }}
securityContext:
  {{- toYaml $context | nindent 2 }}
{{- end }}
{{- end -}}

{{/*
Cluster Type
*/}}
{{- define "dremio.cluster.type" -}}
{{- $allowedTypes := list "prod" "non-prod" -}}
{{- $clusterType := coalesce $.Values.cluster.type "prod" -}}
{{- if has $clusterType $allowedTypes -}}
{{ $clusterType }}
{{- else -}}
{{- fail "cluster.type must be 'prod' or 'non-prod'" -}}
{{- end -}}
{{- end -}}
