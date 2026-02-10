{{/**
Copyright (C) 2017-2019 Dremio Corporation. This file is confidential and private property.
**/}}

{{/*
Shared - Image Pull Secrets
*/}}
{{- define "dremio.imagePullSecrets" -}}
{{- $trialImagePullCredentials := $.Values.dremio.trialImagePullCredentials | default "" }}
{{- $imagePullSecrets := (($.Values.imagePullSecrets)) | default (list) }}
{{- $hasImagePullSecrets := gt (len $imagePullSecrets) 0 }}
{{- if or (not (empty $trialImagePullCredentials)) $hasImagePullSecrets }}
imagePullSecrets:
{{- range $imagePullSecrets }}
- name: {{ . }}
{{- end }}
{{- if $trialImagePullCredentials }}
- name: dremio-trial-image-pull-credentials
{{- end }}
{{- end }}
{{- end -}}

{{/*
Shared - Pod Security Context
*/}}
{{- define "dremio.podSecurityContext" -}}
{{- if $.Values.podSecurityContext }}
securityContext:
  {{- toYaml $.Values.podSecurityContext | nindent 2 }}
{{- else }}
securityContext:
  fsGroup: 999
  fsGroupChangePolicy: OnRootMismatch
{{- end }}
{{- end -}}

{{/*
Shared - Container Security Context
*/}}
{{- define "dremio.containerSecurityContext" -}}
{{- if $.Values.containerSecurityContext }}
securityContext:
  {{- toYaml $.Values.containerSecurityContext | nindent 2 }}
{{- else }}
securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
  privileged: false
  readOnlyRootFilesystem: false
  runAsGroup: 999
  runAsNonRoot: true
  runAsUser: 999
  seccompProfile:
    type: RuntimeDefault
{{- end -}}
{{- end -}}

{{/*
Service - Annotations
*/}}
{{- define "dremio.service.annotations" -}}
{{- $serviceAnnotations := coalesce $.Values.service.annotations $.Values.annotations -}}
{{- if $.Values.service.internalLoadBalancer }}
annotations:
  service.beta.kubernetes.io/azure-load-balancer-internal: "true"
  networking.gke.io/load-balancer-type: "Internal"
  service.beta.kubernetes.io/aws-load-balancer-internal: "true"
  {{- if $serviceAnnotations -}}
  {{- toYaml $serviceAnnotations | nindent 2 -}}
  {{- end -}}
{{- else -}}
{{ if $serviceAnnotations }}
annotations:
  {{- toYaml $serviceAnnotations | nindent 4 -}}
{{- end -}}
{{- end }}
{{- end -}}

{{/*
Service - Labels
*/}}
{{- define "dremio.service.labels" -}}
{{- $serviceLabels := coalesce $.Values.service.labels $.Values.labels -}}
{{- if $serviceLabels -}}
{{- toYaml $serviceLabels }}
{{- end -}}
{{- end -}}

{{/*
Admin - Pod Annotations
*/}}
{{- define "dremio.admin.podAnnotations" -}}
{{- $adminPodAnnotations := coalesce $.Values.coordinator.podAnnotations $.Values.podAnnotations -}}
{{- if $adminPodAnnotations -}}
annotations:
  {{- toYaml $adminPodAnnotations | nindent 2 }}
{{- end -}}
{{- end -}}

{{/*
Admin - Pod Labels
*/}}
{{- define "dremio.admin.podLabels" -}}
{{- $adminPodLabels := coalesce $.Values.coordinator.podLabels $.Values.podLabels -}}
{{- if $adminPodLabels -}}
labels:
  {{- toYaml $adminPodLabels | nindent 2 }}
{{- end -}}
{{- end -}}

{{/*
Admin - Pod Node Selectors
*/}}
{{- define "dremio.admin.nodeSelector" -}}
{{- $adminNodeSelector := coalesce $.Values.coordinator.nodeSelector $.Values.nodeSelector -}}
{{- if $adminNodeSelector -}}
nodeSelector:
  {{- toYaml $adminNodeSelector | nindent 2 }}
{{- end -}}
{{- end -}}

{{/*
Admin - PriorityClassName
*/}}
{{- define "dremio.admin.priorityClassName" -}}
{{- if $.Values.coordinator.priorityClassName -}}
priorityClassName: {{ $.Values.coordinator.priorityClassName }}
{{- end -}}
{{- end -}}

{{/*
Admin - Pod Tolerations
*/}}
{{- define "dremio.admin.tolerations" -}}
{{- $adminPodTolerations := coalesce $.Values.coordinator.tolerations $.Values.tolerations -}}
{{- if $adminPodTolerations -}}
tolerations:
  {{- toYaml $adminPodTolerations | nindent 2 }}
{{- end -}}
{{- end -}}

{{/*
Admin - Service Account
*/}}
{{- define "dremio.admin.serviceAccount" -}}
{{- $adminServiceAccount := $.Values.coordinator.serviceAccount -}}
{{- if $adminServiceAccount -}}
serviceAccount: {{ $adminServiceAccount }}
{{- end -}}
{{- end -}}

{{/*
Admin - Pod Extra Init Containers
*/}}
{{- define "dremio.admin.extraInitContainers" -}}
{{- $adminExtraInitContainers := coalesce $.Values.coordinator.extraInitContainers $.Values.extraInitContainers -}}
{{- if $adminExtraInitContainers -}}
initContainers:
{{ tpl $adminExtraInitContainers $ | nindent 2 }}
{{- end -}}
{{- end -}}

{{/*
Shared - Converts a Kubernetes quantity to a number (int64 or float64).
It handles raw numbers as well as quantities with suffixes
like m, k, M, G, T, P, E, ki, Mi, Gi, Ti, Pi, Ei.
It also handles scientific notation.
https://kubernetes.io/docs/reference/kubernetes-api/common-definitions/quantity/
*/}}
{{- define "dremio.quantity" -}}
{{- $quantity := . -}}
{{- $n := $quantity | float64 -}}
{{- if kindIs "string" $quantity -}}
{{- if hasSuffix "m" $quantity -}}
{{- $n = divf (trimSuffix "m" $quantity | float64) 1000.0 -}}
{{- else if hasSuffix "k" $quantity -}}
{{- $n = trimSuffix "k" $quantity | int64 | mul 1000 -}}
{{- else if hasSuffix "M" $quantity -}}
{{- $n = trimSuffix "M" $quantity | int64 | mul 1000000 -}}
{{- else if hasSuffix "G" $quantity -}}
{{- $n = trimSuffix "G" $quantity | int64 | mul 1000000000 -}}
{{- else if hasSuffix "T" $quantity -}}
{{- $n = trimSuffix "T" $quantity | int64 | mul 1000000000000 -}}
{{- else if hasSuffix "P" $quantity -}}
{{- $n = trimSuffix "P" $quantity | int64 | mul 1000000000000000 -}}
{{- else if hasSuffix "E" $quantity -}}
{{- $n = trimSuffix "E" $quantity | int64 | mul 1000000000000000000 -}}
{{- else if hasSuffix "ki" $quantity -}}
{{- $n = trimSuffix "ki" $quantity | int64 | mul 1024 -}}
{{- else if hasSuffix "Mi" $quantity -}}
{{- $n = trimSuffix "Mi" $quantity | int64 | mul 1048576 -}}
{{- else if hasSuffix "Gi" $quantity -}}
{{- $n = trimSuffix "Gi" $quantity | int64 | mul 1073741824 -}}
{{- else if hasSuffix "Ti" $quantity -}}
{{- $n = trimSuffix "Ti" $quantity | int64 | mul 1099511627776 -}}
{{- else if hasSuffix "Pi" $quantity -}}
{{- $n = trimSuffix "Pi" $quantity | int64 | mul 1125899906842624 -}}
{{- else if hasSuffix "Ei" $quantity -}}
{{- $n = trimSuffix "Ei" $quantity | int64 | mul 1152921504606846976 -}}
{{- end -}}
{{- end -}}
{{- if le ($n | float64) 0.0 -}}
{{- fail (print "invalid quantity: " $quantity) -}}
{{- end -}}
{{- $n -}}
{{- end -}}


{{/*
This helper function is used to convert the given Kubernetes quantity to an integer in Mi
(mibibytes).
*/}}
{{- define "dremio.quantityMi" -}}
{{- $n := div (include "dremio.quantity" . ) 1048576 -}}
{{- if le $n 0 -}}
{{- fail (print "invalid quantity: must be >= 1Mi: " .) -}}
{{- end -}}
{{- $n -}}
{{- end -}}

{{/*
This helper function is used to extract the memory request from the given resources object,
and convert it to Mi. This is used to fill in the environment variable DREMIO_MAX_MEMORY_SIZE_MB
for Dremio pods.
*/}}
{{- define "dremio.memoryMi" -}}
{{- dig "requests" "memory" "" . | required (print "invalid resources: missing memory request: " (toJson .)) | include "dremio.quantityMi" -}}
{{- end -}}

{{/*
This helper function is used to coalesce a list of boolean values using "trilean" logic,
i.e., returning the first non-nil value found, even if it is false.
If a non-nil value is found and it is true, the function returns "1"; otherwise the function returns an empty string.
This function is suitable for use in lieu of the coalesce function, which has surprising effects
when used with boolean values. This function should not be used with non-boolean values.
*/}}
{{- define "dremio.booleanCoalesce" -}}
{{- $found := false -}}
{{- range $value := . -}}
{{- if and (not $found) (ne $value nil) -}}
{{- $found = true -}}
{{- if $value -}}1{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
