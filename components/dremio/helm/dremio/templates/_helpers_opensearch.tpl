{{/**
Copyright (C) 2017-2019 Dremio Corporation. This file is confidential and private property.
**/}}

{{/*
Opensearch - Storage Class
*/}}
{{- define "dremio.opensearch.storageClass" -}}
{{- $opensearchStorageClass := coalesce $.Values.opensearch.storageClass $.Values.storageClass -}}
{{- if $opensearchStorageClass -}}
storageClass: {{ $opensearchStorageClass }}
{{- end -}}
{{- end -}}

{{/*
Opensearch - PreInstall Job Pod Node Selectors
*/}}
{{- define "dremio.opensearch.preInstallJob.nodeSelector" -}}
{{- $opensearchNodeSelector := coalesce $.Values.opensearch.preInstallJob.nodeSelector $.Values.opensearch.nodeSelector $.Values.nodeSelector -}}
{{- if $opensearchNodeSelector -}}
nodeSelector:
  {{- toYaml $opensearchNodeSelector | nindent 2 }}
{{- end -}}
{{- end -}}

{{/*
Opensearch - PreInstall Job Pod PriorityClassName 
*/}}
{{- define "dremio.opensearch.preInstallJob.priorityClassName" -}}
{{- $priorityClassName := coalesce $.Values.opensearch.preInstallJob.priorityClassName $.Values.opensearch.priorityClassName -}}
{{- if $priorityClassName -}}
priorityClassName: {{ $priorityClassName }}
{{- end -}}
{{- end -}}

{{/*
Opensearch - PreInstall Job Pod Tolerations
*/}}
{{- define "dremio.opensearch.preInstallJob.tolerations" -}}
{{- $tolerations := coalesce $.Values.opensearch.preInstallJob.tolerations $.Values.opensearch.tolerations $.Values.tolerations -}}
{{- if $tolerations -}}
tolerations:
  {{- toYaml $tolerations | nindent 2 }}
{{- end -}}
{{- end -}}

{{/*
Opensearch -  OIDC Pod Node Selectors
*/}}
{{- define "dremio.opensearch.oidcProxy.nodeSelector" -}}
{{- $opensearchNodeSelector := coalesce $.Values.opensearch.oidcProxy.nodeSelector $.Values.opensearch.nodeSelector $.Values.nodeSelector -}}
{{- if $opensearchNodeSelector -}}
nodeSelector:
  {{- toYaml $opensearchNodeSelector | nindent 2 }}
{{- end -}}
{{- end -}}

{{/*
Opensearch - OIDC Pod PriorityClassName
*/}}
{{- define "dremio.opensearch.oidcProxy.priorityClassName" -}}
{{- $priorityClassName := coalesce $.Values.opensearch.oidcProxy.priorityClassName $.Values.opensearch.priorityClassName -}}
{{- if $priorityClassName -}}
priorityClassName: {{ $priorityClassName }}
{{- end -}}
{{- end -}}

{{/*
Opensearch - OIDC Pod Tolerations
*/}}
{{- define "dremio.opensearch.oidcProxy.tolerations" -}}
{{- $tolerations := coalesce $.Values.opensearch.oidcProxy.tolerations $.Values.opensearch.tolerations $.Values.tolerations -}}
{{- if $tolerations -}}
tolerations:
  {{- toYaml $tolerations | nindent 2 }}
{{- end -}}
{{- end -}}

{{/*
Opensearch - OIDC Pod Labels
*/}}
{{- define "dremio.opensearch.oidcProxy.podLabels" -}}
{{- $podLabels := coalesce $.Values.opensearch.oidcProxy.podLabels $.Values.podLabels -}}
{{- if $podLabels -}}
{{ toYaml $podLabels }}
{{- end -}}
{{- end -}}

{{/*
Opensearch - Tolerations
*/}}
{{- define "dremio.opensearch.tolerations" -}}
{{- $tolerations := coalesce $.Values.opensearch.tolerations $.Values.tolerations -}}
{{- if $tolerations -}}
tolerations:
  {{- toYaml $tolerations | nindent 2 }}
{{- end -}}
{{- end -}}

{{/*
Opensearch - PriorityClassName
*/}}
{{- define "dremio.opensearch.priorityClassName" -}}
{{- if $.Values.opensearch.priorityClassName -}}
priorityClassName: {{ $.Values.opensearch.priorityClassName }}
{{- end -}}
{{- end -}}

{{/*
Opensearch - Pod Node Selectors
*/}}
{{- define "dremio.opensearch.nodeSelector" -}}
{{- $opensearchNodeSelector := coalesce $.Values.opensearch.nodeSelector $.Values.nodeSelector -}}
{{- if $opensearchNodeSelector -}}
nodeSelector:
  {{- toYaml $opensearchNodeSelector | nindent 2 }}
{{- end -}}
{{- end -}}

{{/*
Opensearch - Labels
*/}}
{{- define "dremio.opensearch.podLabels" -}}
{{- $labels := coalesce $.Values.opensearch.podLabels $.Values.podLabels -}}
{{- if $labels -}}
labels:
  {{- toYaml $labels | nindent 2 }}
{{- end -}}
{{- end -}}


{{/*
Opensearch - SecurityContexts for OpenSearchCluster pods.
*/}}
{{- define "dremio.opensearchcluster.podSecurityContext" -}}
{{- $opensearchClusterPodSecurityContext := $.Values.opensearch.clusterPodSecurityContext -}}
{{- if $opensearchClusterPodSecurityContext -}}
podSecurityContext:
  {{- toYaml $opensearchClusterPodSecurityContext | nindent 2 }}
{{- end -}}
{{- end -}}

{{/*
Opensearch - SecurityContexts for OpenSearchCluster containers.
*/}}
{{- define "dremio.opensearchcluster.securityContext" -}}
{{- $opensearchClusterSecurityContext := $.Values.opensearch.containerSecurityContext -}}
{{- if $opensearchClusterSecurityContext -}}
securityContext:
  {{- toYaml $opensearchClusterSecurityContext | nindent 2 }}
{{- end -}}
{{- end -}}

{{/*
OpenSearch - Service Name
*/}}
{{- define "dremio.opensearch.serviceName" -}}
  {{- .Values.opensearch.serviceName | default "opensearch-cluster" -}}
{{- end -}}

{{/*
OpenSearch - Service Port
*/}}
{{- define "dremio.opensearch.servicePort" -}}
  {{- .Values.opensearch.servicePort | default 9200 -}}
{{- end -}}

{{/*
Opensearch - Bootstrap Pod Node Selectors
*/}}
{{- define "dremio.opensearch.bootstrap.nodeSelector" -}}
{{- $bootstrapNodeSelector := coalesce $.Values.opensearch.bootstrap.nodeSelector $.Values.opensearch.nodeSelector $.Values.nodeSelector -}}
{{- if $bootstrapNodeSelector -}}
nodeSelector:
  {{- toYaml $bootstrapNodeSelector | nindent 2 }}
{{- end -}}
{{- end -}}

{{/*
Opensearch - Bootstrap Pod PriorityClassName 
NOTE NOT USED or SUPPORTED by the OpenSearch Operator as of 2025-08-05 so we are not implementing it.
*/}}

{{/*
Opensearch - Bootstrap Pod Tolerations
*/}}
{{- define "dremio.opensearch.bootstrap.tolerations" -}}
{{- $bootstrapTolerations := coalesce $.Values.opensearch.bootstrap.tolerations $.Values.opensearch.tolerations $.Values.tolerations -}}
{{- if $bootstrapTolerations -}}
tolerations:
  {{- toYaml $bootstrapTolerations | nindent 2 }}
{{- end -}}
{{- end -}}
