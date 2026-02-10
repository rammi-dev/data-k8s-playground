{{/*
# Copyright (C) 2017-2019 Dremio Corporation. This file is confidential and private property.
*/}}

{{/*
Engines - Coordinator Container Extra Environment Variables
*/}}
{{- define "dremio.coordinator.engine.envs" -}}
- name: "KUBERNETES_NAMESPACE"
  value: {{ .Release.Namespace }}
{{- end -}}

{{/*
Engines - Coordinator Extra Volumes
*/}}
{{- define "dremio.coordinator.engine.volumes" -}}
- name: dremio-engine-config
  configMap:
    name: engine-options
{{- end -}}

{{/*
Engines - Coordinator Container Extra Volume Mounts
*/}}
{{- define "dremio.coordinator.engine.volume.mounts" -}}
- name: dremio-engine-config
  mountPath: /opt/dremio/conf/engine
{{- end -}}

{{/*
Engine Operator - Service Account
*/}}
{{- define "dremio.engine.operator.serviceAccount" -}}
{{- $operatorServiceAccount := coalesce (($.Values.engine).operator).serviceAccount "engine-operator" -}}
{{- if $operatorServiceAccount -}}
serviceAccountName: {{ $operatorServiceAccount }}
{{- end -}}
{{- end -}}

{{/*
Engine Operator - Pod Extra Init Containers
*/}}
{{- define "dremio.engine.operator.extraInitContainers" -}}
{{- $operatorExtraInitContainers := coalesce (($.Values.engine).operator).extraInitContainers $.Values.extraInitContainers -}}
{{- if $operatorExtraInitContainers -}}
{{ tpl $operatorExtraInitContainers $ }}
{{- end -}}
{{- end -}}

{{/*
Engine Executor - Pod Extra Init Containers
*/}}
{{- define "dremio.engine.executor.extraInitContainers" -}}
{{- $executorExtraInitContainers := coalesce (($.Values.engine).executor).extraInitContainers $.Values.extraInitContainers -}}
{{- if $executorExtraInitContainers -}}
{{- if kindIs "string" $executorExtraInitContainers }}
{{ tpl $executorExtraInitContainers $ }}
{{- else -}}
{{ tpl (toYaml $executorExtraInitContainers) $ }}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Engine Operator - Container Extra Environment Variables
*/}}
{{- define "dremio.engine.operator.extraEnvs" -}}
{{- $operatorEnvironmentVariables := default (default (dict) $.Values.extraEnvs) (($.Values.engine).operator).extraEnvs -}}
{{- range $index, $environmentVariable:= $operatorEnvironmentVariables -}}
{{- if hasPrefix "DREMIO" $environmentVariable.name -}}
{{ fail "Environment variables cannot begin with DREMIO"}}
{{- end -}}
{{- end -}}
{{- if $operatorEnvironmentVariables -}}
{{ toYaml $operatorEnvironmentVariables }}
{{- end -}}
{{- end -}}

{{/*
Engine Operator - Deployment Annotations
*/}}
{{- define "dremio.engine.operator.annotations" -}}
{{- $operatorAnnotations := coalesce (($.Values.engine).operator).annotations $.Values.annotations -}}
{{- if $operatorAnnotations -}}
annotations:
  {{- toYaml $operatorAnnotations | nindent 2 }}
{{- end -}}
{{- end -}}

{{/*
Engine Operator - Deployment Labels
*/}}
{{- define "dremio.engine.operator.labels" -}}
{{- $operatorLabels := coalesce (($.Values.engine).operator).labels $.Values.labels -}}
{{- if $operatorLabels -}}
labels:
  {{- toYaml $operatorLabels | nindent 2 }}
{{- end -}}
{{- end -}}

{{/*
Engine Operator - Pod Annotations
*/}}
{{- define "dremio.engine.operator.podAnnotations" -}}
{{- $coordinatorPodAnnotations := coalesce (($.Values.engine).operator).podAnnotations $.Values.podAnnotations -}}
{{- if $coordinatorPodAnnotations -}}
{{ toYaml $coordinatorPodAnnotations }}
{{- end -}}
{{- end -}}

{{/*
Engine Operator - Pod Labels
*/}}
{{- define "dremio.engine.operator.podLabels" -}}
{{- $operatorPodLabels := coalesce (($.Values.engine).operator).podLabels $.Values.podLabels -}}
{{- if $operatorPodLabels -}}
{{ toYaml $operatorPodLabels }}
{{- end -}}
{{- end -}}

{{/*
Engine Operator - Pod Node Selectors
*/}}
{{- define "dremio.engine.operator.nodeSelector" -}}
{{- $operatorNodeSelector := coalesce (($.Values.engine).operator).nodeSelector $.Values.nodeSelector -}}
{{- if $operatorNodeSelector -}}
nodeSelector:
  {{- toYaml $operatorNodeSelector | nindent 2 }}
{{- end -}}
{{- end -}}

{{/*
Engine Operator - PriorityClassName
*/}}
{{- define "dremio.engine.operator.priorityClassName" -}}
{{- if (($.Values.engine).operator).priorityClassName -}}
priorityClassName: {{ (($.Values.engine).operator).priorityClassName }}
{{- end -}}
{{- end -}}

{{/*
Engine Operator - Pod Tolerations
*/}}
{{- define "dremio.engine.operator.tolerations" -}}
{{- $operatorTolerations := coalesce (($.Values.engine).operator).tolerations $.Values.tolerations -}}
{{- if $operatorTolerations -}}
tolerations:
  {{- toYaml $operatorTolerations | nindent 2 }}
{{- end -}}
{{- end -}}

{{/*
Engine Operator - Pod Security Context
*/}}
{{- define "dremio.engine.operator.podSecurityContext" -}}
{{- $context := coalesce .Values.engine.operator.podSecurityContext (include "dremio.podSecurityContext" . | fromYaml).securityContext -}}
{{- if $context }}
securityContext:
  {{- toYaml $context | nindent 2 }}
{{- end }}
{{- end -}}

{{/*
Engine Operator - Container Security Context
*/}}
{{- define "dremio.engine.operator.containerSecurityContext" -}}
{{- $context := coalesce .Values.engine.operator.containerSecurityContext (include "dremio.containerSecurityContext" . | fromYaml).securityContext -}}
{{- if $context }}
securityContext:
  {{- toYaml $context | nindent 2 }}
{{- end }}
{{- end -}}

{{/*
Generate a volume definition for the default executor volume (hostPath or emptyDir only)
Usage:
  {{- include "dremio.defaultVolume" . | nindent 8 }}
*/}}
{{- define "dremio.defaultVolume" -}}
{{- if eq ((.Values.engine.executor.volumes).default).type "hostPath" }}
- name: dremio-default-executor-volume
  hostPath:
    path: {{ .Values.engine.executor.volumes.default.hostPath.path }}
    {{- if .Values.engine.executor.volumes.default.hostPath.type }}
    type: {{ .Values.engine.executor.volumes.default.hostPath.type }}
    {{- end }}
{{- else if eq ((.Values.engine.executor.volumes).default).type "emptyDir" }}
- name: dremio-default-executor-volume
  emptyDir:
    {{- if .Values.engine.executor.volumes.default.emptyDir.sizeLimit }}
    sizeLimit: {{ .Values.engine.executor.volumes.default.emptyDir.sizeLimit }}
    {{- end }}
    {{- if .Values.engine.executor.volumes.default.emptyDir.medium }}
    medium: {{ .Values.engine.executor.volumes.default.emptyDir.medium }}
    {{- end }}
{{- end }}
{{- end }}

{{/*
Generate a volume definition for the C3 cache volume (hostPath or emptyDir only)
Usage:
  {{- include "dremio.c3Volume" . | nindent 8 }}
*/}}
{{- define "dremio.c3Volume" -}}
{{- if eq ((.Values.engine.executor.volumes).c3).type "hostPath" }}
- name: dremio-default-executor-c3-0
  hostPath:
    path: {{ .Values.engine.executor.volumes.c3.hostPath.path }}
    {{- if .Values.engine.executor.volumes.c3.hostPath.type }}
    type: {{ .Values.engine.executor.volumes.c3.hostPath.type }}
    {{- end }}
{{- else if eq ((.Values.engine.executor.volumes).c3).type "emptyDir" }}
- name: dremio-default-executor-c3-0
  emptyDir:
    {{- if .Values.engine.executor.volumes.c3.emptyDir.sizeLimit }}
    sizeLimit: {{ .Values.engine.executor.volumes.c3.emptyDir.sizeLimit }}
    {{- end }}
    {{- if .Values.engine.executor.volumes.c3.emptyDir.medium }}
    medium: {{ .Values.engine.executor.volumes.c3.emptyDir.medium }}
    {{- end }}
{{- end }}
{{- end }}

{{/*
Generate a volumeClaimTemplate for the default executor volume (PVC only)
Usage:
  {{- include "dremio.defaultVolumeClaimTemplate" . | nindent 4 }}
*/}}
{{- define "dremio.defaultVolumeClaimTemplate" -}}
{{- if eq (((.Values.engine.executor.volumes).default).type | default "pvc") "pvc" }}
- metadata:
    name: dremio-default-executor-volume
  spec:
    accessModes: [ "ReadWriteOnce" ]
    {{- if (((.Values.engine.executor.volumes).default).pvc).storageClass }}
    storageClassName: {{ .Values.engine.executor.volumes.default.pvc.storageClass }}
    {{- end }}
    resources:
      requests:
        storage: 0Gi
{{- end }}
{{- end }}

{{/*
Generate a volumeClaimTemplate for the C3 cache volume (PVC only)
Usage:
  {{- include "dremio.c3VolumeClaimTemplate" . | nindent 4 }}
*/}}
{{- define "dremio.c3VolumeClaimTemplate" -}}
{{- if eq (((.Values.engine.executor.volumes).c3).type | default "pvc") "pvc" }}
- metadata:
    name: dremio-default-executor-c3-0
  spec:
    accessModes: [ "ReadWriteOnce" ]
    {{- if (((.Values.engine.executor.volumes).c3).pvc).storageClass }}
    storageClassName: {{ .Values.engine.executor.volumes.c3.pvc.storageClass }}
    {{- end }}
    resources:
      requests:
        storage: 0Gi
{{- end }}
{{- end }}

{{/*
Engine Operator - Logs Storage Class
*/}}
{{- define "dremio.engine.operator.log.storageClass" -}}
{{- if (((.Values.engine.executor.volumes).log).pvc).storageClass }}
storageClassName: {{ .Values.engine.executor.volumes.log.pvc.storageClass }}
{{- end -}}
{{- end -}}
