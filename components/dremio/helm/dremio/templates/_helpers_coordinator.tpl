{{/**
Copyright (C) 2017-2019 Dremio Corporation. This file is confidential and private property.
**/}}

{{/*
Coordinator - Dremio Heap Memory allocation
*/}}
{{- define "dremio.coordinator.heapMemory" -}}
{{- $coordinatorMemory := include "dremio.memoryMi" $.Values.coordinator.resources | int -}}
{{- $reserveMemory := 0 -}}
{{- if gt 4096 $coordinatorMemory -}}
{{ fail "Dremio's minimum memory requirement is 4 GB." }}
{{- end -}}
{{- if le 64000 $coordinatorMemory -}}
{{- $reserveMemory = 6000 -}}
{{- else -}}
{{- $reserveMemory = mulf $coordinatorMemory .05 | int -}}
{{- end -}}
{{- $coordinatorMemory = sub $coordinatorMemory $reserveMemory}}
{{- if le 18432 $coordinatorMemory -}}
16384
{{- else -}}
{{- sub $coordinatorMemory 2048}}
{{- end -}}
{{- end -}}

{{/*
Coordiantor - Dremio Direct Memory Allocation
*/}}
{{- define "dremio.coordinator.directMemory" -}}
{{- $coordinatorMemory := include "dremio.memoryMi" $.Values.coordinator.resources | int -}}
{{- $reserveMemory := 0 -}}
{{- if gt 4096 $coordinatorMemory -}}
{{ fail "Dremio's minimum memory requirement is 4 GB." }}
{{- end -}}
{{- if le 64000 $coordinatorMemory -}}
{{- $reserveMemory = 6000 -}}
{{- else -}}
{{- $reserveMemory = mulf $coordinatorMemory .05 | int -}}
{{- end -}}
{{- $coordinatorMemory = sub $coordinatorMemory $reserveMemory}}
{{- if le 18432 $coordinatorMemory -}}
{{- sub $coordinatorMemory 16384 -}}
{{- else -}}
2048
{{- end -}}
{{- end -}}

{{/*
Coordinator - Dremio Start Parameters
*/}}
{{- define "dremio.coordinator.extraStartParams" -}}
{{- $coordinatorExtraStartParams := coalesce $.Values.coordinator.extraStartParams $.Values.extraStartParams -}}
{{- if $coordinatorExtraStartParams}}
{{- printf "%v " $coordinatorExtraStartParams -}}
{{- end -}}
{{- end -}}

{{/*
Coordinator - Search Enabled
*/}}
{{- define "dremio.coordinator.search.enabled" -}}
{{- if $.Values.opensearch.enabled }}
{{ printf "\n-Ddremio.debug.sysopt.search.v2.enabled=true" }}
-Ddremio.debug.sysopt.nextgen_search.ui.enable=true
-Ddremio.debug.sysopt.search.logging.enabled=true
-Ddremio.debug.sysopt.search.versioned_entity_ingest.enabled=true
-Ddremio.debug.sysopt.search.scheduled_reconciliation.enabled=true
{{ printf "-Ddremio.debug.sysopt.search.job_ingest.enabled=true\n" }}
{{- end -}}
{{- end -}}

{{/*
Coordinator - Pod Extra Init Containers
*/}}
{{- define "dremio.coordinator.extraInitContainers" -}}
{{- $coordinatorExtraInitContainers := coalesce $.Values.coordinator.extraInitContainers $.Values.extraInitContainers -}}
{{- if $coordinatorExtraInitContainers -}}
{{ tpl $coordinatorExtraInitContainers $ }}
{{- end -}}
{{- end -}}

{{/*
Coordinator - Log Path
*/}}
{{- define "dremio.coordinator.log.path" -}}
{{- $logEnabled := include "dremio.booleanCoalesce" (list $.Values.coordinator.writeLogsToFile (($.Values.coordinator).log).enabled  $.Values.writeLogsToFile (($.Values.dremio).log).enabled 1) -}}
{{- if $logEnabled -}}
- name: DREMIO_LOG_TO_CONSOLE
  value: "0"
- name: DREMIO_LOG_DIR
  value: /opt/dremio/log
{{- else -}}
- name: DREMIO_LOG_TO_CONSOLE
  value: "1"
{{- end -}}
{{- end -}}

{{/*
Coordinator - Log Volume Mount
*/}}
{{- define "dremio.coordinator.log.volumeMount" -}}
{{- $logEnabled := include "dremio.booleanCoalesce" (list $.Values.coordinator.writeLogsToFile (($.Values.coordinator).log).enabled  $.Values.writeLogsToFile (($.Values.dremio).log).enabled 1) -}}
{{- if $logEnabled -}}
- name: dremio-log-volume
  mountPath: /opt/dremio/log
{{- end -}}
{{- end -}}

{{/*
Coordinator - Logs Volume Claim Template
*/}}
{{- define "dremio.coordinator.log.volumeClaimTemplate" -}}
{{- $logEnabled := include "dremio.booleanCoalesce" (list $.Values.coordinator.writeLogsToFile (($.Values.coordinator).log).enabled  $.Values.writeLogsToFile (($.Values.dremio).log).enabled 1) -}}
{{- $logVolumeSize := coalesce ((($.Values.coordinator).log).volume).size $.Values.dremio.log.volume.size -}}
{{- if $logEnabled -}}
- metadata:
    name: dremio-log-volume
  spec:
    accessModes: ["ReadWriteOnce"]
    {{ include "dremio.coordinator.log.storageClass" $ }}
    resources:
      requests:
        storage: {{ $logVolumeSize }}
{{- end -}}
{{- end -}}

{{/*
Coordinator - Pod Extra Volume Mounts
*/}}
{{- define "dremio.coordinator.extraVolumeMounts" -}}
{{- $coordinatorExtraVolumeMounts := default (default (dict) $.Values.extraVolumeMounts) $.Values.coordinator.extraVolumeMounts -}}
{{- if $coordinatorExtraVolumeMounts -}}
{{ toYaml $coordinatorExtraVolumeMounts }}
{{- end -}}
{{- end -}}

{{/*
Coordinator - Pod Extra Volumes
*/}}
{{- define "dremio.coordinator.extraVolumes" -}}
{{- $coordinatorExtraVolumes := coalesce $.Values.coordinator.extraVolumes $.Values.extraVolumes -}}
{{- if $coordinatorExtraVolumes -}}
{{ toYaml $coordinatorExtraVolumes }}
{{- end -}}
{{- end -}}

{{/*
Coordinator - Pod Extra Envs
*/}}
{{- define "dremio.coordinator.extraEnvs" -}}
{{- $coordinatorExtraEnvs := coalesce $.Values.coordinator.extraEnvs $.Values.extraEnvs -}}
{{- range $index, $environmentVariable:= $coordinatorExtraEnvs -}}
{{- if hasPrefix "DREMIO" $environmentVariable.name -}}
{{ fail "Environment variables cannot begin with DREMIO"}}
{{- end -}}
{{- end -}}
{{- if $coordinatorExtraEnvs -}}
{{ toYaml $coordinatorExtraEnvs }}
{{- end -}}
{{- end -}}

{{/*
Coordinator - Storage Class
*/}}
{{- define "dremio.coordinator.storageClass" -}}
{{- $coordinatorStorageClass := coalesce $.Values.coordinator.storageClass $.Values.storageClass -}}
{{- if $coordinatorStorageClass -}}
storageClassName: {{ $coordinatorStorageClass }}
{{- end -}}
{{- end -}}

{{/*
Coordinator - Logs Storage Class
*/}}
{{- define "dremio.coordinator.log.storageClass" -}}
{{- $coordinatorLogStorageClass := coalesce $.Values.coordinator.logStorageClass ((($.Values.coordinator).log).volume).storageClass $.Values.logStorageClass ((($.Values.dremio).log).volume).storageClass $.Values.storageClass -}}
{{- if $coordinatorLogStorageClass -}}
storageClassName: {{ $coordinatorLogStorageClass }}
{{- end -}}
{{- end -}}

{{/*
Coordinator - StatefulSet Annotations
*/}}
{{- define "dremio.coordinator.annotations" -}}
{{- $coordinatorAnnotations := coalesce $.Values.coordinator.annotations $.Values.annotations -}}
{{- if $coordinatorAnnotations -}}
annotations:
  {{- toYaml $coordinatorAnnotations | nindent 2 }}
{{- end -}}
{{- end -}}

{{/*
Coordinator - StatefulSet Labels
*/}}
{{- define "dremio.coordinator.labels" -}}
{{- $coordinatorLabels := coalesce $.Values.coordinator.labels $.Values.labels -}}
{{- if $coordinatorLabels -}}
labels:
  {{- toYaml $coordinatorLabels | nindent 2 }}
{{- end -}}
{{- end -}}

{{/*
Coordinator - Pod Annotations
*/}}
{{- define "dremio.coordinator.podAnnotations" -}}
{{- $coordiantorPodAnnotations := coalesce $.Values.coordinator.podAnnotations $.Values.podAnnotations -}}
{{- if $coordiantorPodAnnotations -}}
{{ toYaml $coordiantorPodAnnotations }}
{{- end -}}
{{- end -}}

{{/*
Coordinator - Pod Labels
*/}}
{{- define "dremio.coordinator.podLabels" -}}
{{- $coordinatorPodLabels := coalesce $.Values.coordinator.podLabels $.Values.podLabels -}}
{{- if $coordinatorPodLabels -}}
{{ toYaml $coordinatorPodLabels }}
{{- end -}}
{{- end -}}

{{/*
Coordinator - Pod Node Selectors
*/}}
{{- define "dremio.coordinator.nodeSelector" -}}
{{- $coordinatorNodeSelector := coalesce $.Values.coordinator.nodeSelector $.Values.nodeSelector -}}
{{- if $coordinatorNodeSelector -}}
nodeSelector:
  {{- toYaml $coordinatorNodeSelector | nindent 2 }}
{{- end -}}
{{- end -}}

{{/*
Coordinator - PriorityClassName
*/}}
{{- define "dremio.coordinator.priorityClassName" -}}
{{- if $.Values.coordinator.priorityClassName -}}
priorityClassName: {{ $.Values.coordinator.priorityClassName }}
{{- end -}}
{{- end -}}

{{/*
Coordinator - Pod Tolerations
*/}}
{{- define "dremio.coordinator.tolerations" -}}
{{- $coordinatorTolerations := coalesce $.Values.coordinator.tolerations $.Values.tolerations -}}
{{- if $coordinatorTolerations -}}
tolerations:
  {{- toYaml $coordinatorTolerations | nindent 2 }}
{{- end -}}
{{- end -}}

{{/*
Coordinator - Active Processor Count
*/}}
{{- define "dremio.coordinator.activeProcessorCount" -}}
{{- $coordinatorCpu := floor $.Values.coordinator.resources.requests.cpu | int -}}
{{- if gt 1 $coordinatorCpu -}}
1
{{- else -}}
{{- $coordinatorCpu -}}
{{- end -}}
{{- end -}}

{{/*
Coordinator - Pod Security Context
*/}}
{{- define "dremio.coordinator.podSecurityContext" -}}
{{- if $.Values.coordinator.podSecurityContext }}
securityContext:
  {{- toYaml $.Values.coordinator.podSecurityContext | nindent 2 }}
{{- else }}
{{- include "dremio.podSecurityContext" $ }}
{{- end }}
{{- end -}}

{{/*
Coordinator - Container Security Context
*/}}
{{- define "dremio.coordinator.containerSecurityContext" -}}
{{- if $.Values.coordinator.containerSecurityContext }}
securityContext:
  {{- toYaml $.Values.coordinator.containerSecurityContext | nindent 2 }}
{{- else }}
{{- include "dremio.containerSecurityContext" $ }}
{{- end -}}
{{- end -}}
