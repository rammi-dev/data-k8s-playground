{{/**
Copyright (C) 2017-2019 Dremio Corporation. This file is confidential and private property.
**/}}

{{/*
Zookeeper - Storage Class
*/}}
{{- define "dremio.zookeeper.storageClass" -}}
{{- $zookeeperStorageClass := coalesce $.Values.zookeeper.storageClass $.Values.storageClass -}}
{{- if $zookeeperStorageClass -}}
storageClassName: {{ $zookeeperStorageClass }}
{{- end -}}
{{- end -}}

{{/*
Zookeeper - StatefulSet Annotations
*/}}
{{- define "dremio.zookeeper.annotations" -}}
{{- $zookeeperAnnotations := coalesce $.Values.zookeeper.annotations $.Values.annotations -}}
{{- if $zookeeperAnnotations -}}
annotations:
  {{- toYaml $zookeeperAnnotations | nindent 2 }}
{{- end -}}
{{- end -}}

{{/*
Zookeeper - StatefulSet Labels
*/}}
{{- define "dremio.zookeeper.labels" -}}
{{- $zookeeperLabels := coalesce $.Values.zookeeper.labels $.Values.labels -}}
{{- if $zookeeperLabels -}}
labels:
  {{- toYaml $zookeeperLabels | nindent 2 }}
{{- end -}}
{{- end -}}

{{/*
Zookeeper - Pod Annotations
*/}}
{{- define "dremio.zookeeper.podAnnotations" -}}
{{- $coordinatorAnnotations := coalesce $.Values.zookeeper.podAnnotations $.Values.podAnnotations -}}
{{- if $coordinatorAnnotations -}}
{{- toYaml $coordinatorAnnotations }}
{{- end -}}
{{- end -}}

{{/*
Zookeeper - Pod Labels
*/}}
{{- define "dremio.zookeeper.podLabels" -}}
{{- $zookeeperLabels := coalesce $.Values.zookeeper.podLabels $.Values.podLabels -}}
{{- if $zookeeperLabels -}}
{{ toYaml $zookeeperLabels }}
{{- end -}}
{{- end -}}

{{/*
Zookeeper - Pod Node Selectors
*/}}
{{- define "dremio.zookeeper.nodeSelector" -}}
{{- $zookeeperNodeSelector := coalesce $.Values.zookeeper.nodeSelector $.Values.nodeSelector -}}
{{- if $zookeeperNodeSelector -}}
nodeSelector:
  {{- toYaml $zookeeperNodeSelector | nindent 2 }}
{{- end -}}
{{- end -}}

{{/*
Zookeeper - PriorityClassName
*/}}
{{- define "dremio.zookeeper.priorityClassName" -}}
{{- if $.Values.zookeeper.priorityClassName -}}
priorityClassName: {{ $.Values.zookeeper.priorityClassName }}
{{- end -}}
{{- end -}}

{{/*
Zookeeper - Pod Tolerations
*/}}
{{- define "dremio.zookeeper.tolerations" -}}
{{- $zookeeperTolerations := coalesce $.Values.zookeeper.tolerations $.Values.tolerations -}}
{{- if $zookeeperTolerations -}}
tolerations:
  {{- toYaml $zookeeperTolerations | nindent 2 }}
{{- end -}}
{{- end -}}

{{/*
Zookeeper - Service Account
*/}}
{{- define "dremio.zookeeper.serviceAccount" -}}
{{- $zookeeperServiceAccount := $.Values.zookeeper.serviceAccount -}}
{{- if $zookeeperServiceAccount -}}
serviceAccountName: {{ $zookeeperServiceAccount }}
{{- end -}}
{{- end -}}
