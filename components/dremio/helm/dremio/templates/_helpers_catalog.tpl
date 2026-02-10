
{{/**
Copyright (C) 2017-2019 Dremio Corporation. This file is confidential and private property.
**/}}

{{/*
Catalog Server - Dremio Catalog - App Name
*/}}
{{- define "dremio.catalog.app.name" -}}
dremio-catalog-server
{{- end -}}

{{/*
Catalog Server - Dremio Catalog- HTTP Port - Internal
*/}}
{{- define "dremio.catalog.ports.http.internal" -}}
9181
{{- end -}}

{{/*
Catalog - Dremio Catalog - HTTP Port - External
*/}}
{{- define "dremio.catalog.ports.http.external" -}}
{{- if $.Values.catalog.externalAccess.tls.enabled -}}
8183
{{- else -}}
8181
{{- end -}}
{{- end -}}

{{/*
Catalog Server - Dremio Catalog - Management Port - Internal
*/}}
{{- define "dremio.catalog.ports.mgmt.internal" -}}
9182
{{- end -}}

{{/*
Catalog Server - Dremio Catalog - Management Port - External
*/}}
{{- define "dremio.catalog.ports.mgmt.external" -}}
8182
{{- end -}}

{{/*
Catalog Server - Dremio Catalog - GRPC Port
*/}}
{{- define "dremio.catalog.ports.grpc" -}}
9000
{{- end -}}

{{/*
Catalog Server - Dremio Catalog - Server JVM Options
*/}}
{{- define "dremio.catalog.java.options" -}}
-Ddremio.debug.sysopt.dremio.catalog.enabled=true
-Dservices.dremio.catalog.uri={{ include "dremio.catalog.app.name" $ }}
-Dservices.dremio.catalog.port={{ include "dremio.catalog.ports.http.internal" $ }}
-Dservices.dremio.catalog.grpc.uri={{ include "dremio.catalog.app.name" $ }}-grpc
-Dservices.dremio.catalog.grpc.port={{ include "dremio.catalog.ports.grpc" $ }}
{{- end -}}

{{/*
Catalog Server - Dremio Catalog - Storage - Locations list
*/}}
{{- define "dremio.catalog.storage.locations" -}}
{{- if (kindIs "string" .Values.catalog.storage.location) }}
{{- if and .Values.catalog.storage.location  (hasSuffix "/" .Values.catalog.storage.location) }}
{{- fail "Invalid value for catalog.storage.location: must not end with a slash (/)" -}}
{{- end }}
{{- .Values.catalog.storage.location }}
{{- else if (kindIs "slice" .Values.catalog.storage.location) }}
{{- range .Values.catalog.storage.location }}
{{- if (hasSuffix "/" .) }}
{{- fail "Invalid value for catalog.storage.location: must not end with a slash (/)" -}}
{{- end }}
{{- end }}
{{- join "," .Values.catalog.storage.location }}
{{- end }}
{{- end -}}

{{/*
Catalog Server - Dremio Catalog - Storage - Base Location
*/}}
{{- define "dremio.catalog.storage.base-location" -}}
{{- if (kindIs "string" .Values.catalog.storage.location) }}
{{- .Values.catalog.storage.location }}
{{- else if (kindIs "slice" .Values.catalog.storage.location) }}
{{- first .Values.catalog.storage.location }}
{{- end }}
{{- end -}}

{{/*
Catalog Server - Dremio Catalog - Storage - Secrets - S3 - Secret Name
*/}}
{{- define "dremio.catalog.storage.s3.secretName" -}}
{{- if $.Values.catalog.storage.s3.secretName -}}
{{ $.Values.catalog.storage.s3.secretName }}
{{- else -}}
catalog-server-s3-storage-creds
{{- end -}}
{{- end -}}

{{/*
Catalog Server - Dremio Catalog - Storage - Secrets - Azure - Secret Name
*/}}
{{- define "dremio.catalog.storage.azure.secretName" -}}
{{- if $.Values.catalog.storage.azure.secretName -}}
{{ $.Values.catalog.storage.azure.secretName }}
{{- else -}}
catalog-server-azure-storage-creds
{{- end -}}
{{- end -}}

{{/*
Catalog Server - Dremio Catalog - Storage - Secrets - GCP - Secret Name
*/}}
{{- define "dremio.catalog.storage.gcs.secretName" -}}
{{- if $.Values.catalog.storage.gcs.secretName -}}
{{ $.Values.catalog.storage.gcs.secretName }}
{{- else -}}
catalog-server-gcs-storage-creds
{{- end -}}
{{- end -}}

{{/*
Catalog Server - Dremio Catalog - Storage - Environment variables
*/}}
{{- define "dremio.catalog.storage.env" -}}
- name: dremio.catalog.storage.base-location
  value: "{{- include "dremio.catalog.storage.base-location" $ }}"
- name: dremio.catalog.storage.locations
  value: "{{- include "dremio.catalog.storage.locations" $ }}"
{{- if eq (upper (.Values.catalog.storage.type | default "" )) "S3" }}
- name: dremio.catalog.storage.type
  value: "S3"
- name: dremio.catalog.storage.s3-role-arn
  value: "{{ .Values.catalog.storage.s3.roleArn }}"
{{- if .Values.catalog.storage.s3.userArn }}
- name: dremio.catalog.storage.s3-user-arn
  value: "{{ .Values.catalog.storage.s3.userArn }}"
{{- end }}
{{- if .Values.catalog.storage.s3.externalId }}
- name: dremio.catalog.storage.s3-external-id
  value: "{{ .Values.catalog.storage.s3.externalId }}"
{{- end }}
{{- if .Values.catalog.storage.s3.endpoint }}
- name: polaris.storage.aws.s3-endpoint
  value: "{{ .Values.catalog.storage.s3.endpoint }}"
{{- end }}
{{- if .Values.catalog.storage.s3.stsEndpoint }}
- name: polaris.storage.aws.sts-endpoint
  value: "{{ .Values.catalog.storage.s3.stsEndpoint }}"
{{- end }}
{{- if .Values.catalog.storage.s3.pathStyleAccess }}
- name: polaris.storage.aws.path-style-access-enabled
  value: "true"
{{- end }}
{{- if .Values.catalog.storage.s3.skipSts }}
- name: polaris.storage.aws.skip-sts
  value: "true"
{{- end }}
{{- if .Values.catalog.storage.s3.region }}
- name: dremio.catalog.storage.s3-region
  value: "{{ .Values.catalog.storage.s3.region }}"
{{- end }}
- name: AWS_REGION
  value: "{{ .Values.catalog.storage.s3.region }}"
{{- if .Values.catalog.storage.s3.useAccessKeys }}
- name: AWS_ACCESS_KEY_ID
  valueFrom:
    secretKeyRef:
      name: {{ include "dremio.catalog.storage.s3.secretName" $ }}
      key: awsAccessKeyId
- name: AWS_SECRET_ACCESS_KEY
  valueFrom:
    secretKeyRef:
      name: {{ include "dremio.catalog.storage.s3.secretName" $ }}
      key: awsSecretAccessKey
{{- end }}
{{- else if eq (upper (.Values.catalog.storage.type | default "" )) "AZURE" }}
- name: dremio.catalog.storage.type
  value: "AZURE"
- name: dremio.catalog.storage.azure-tenant-id
  value: "{{ .Values.catalog.storage.azure.tenantId }}"
{{- if .Values.catalog.storage.azure.multiTenantAppName }}
- name: dremio.catalog.storage.azure-multi-tenant-app-name
  value: "{{ .Values.catalog.storage.azure.multiTenantAppName }}"
{{- end }}
{{- if .Values.catalog.storage.azure.useClientSecrets }}
- name: AZURE_CLIENT_ID
  valueFrom:
    secretKeyRef:
      name: {{ include "dremio.catalog.storage.azure.secretName" $ }}
      key: azureClientId
- name: AZURE_CLIENT_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ include "dremio.catalog.storage.azure.secretName" $ }}
      key: azureClientSecret
- name: AZURE_TENANT_ID
  value: "{{ .Values.catalog.storage.azure.tenantId }}"
{{- end }}
{{- else if eq (upper (.Values.catalog.storage.type | default "" )) "GCS" }}
- name: dremio.catalog.storage.type
  value: "GCS"
{{- if .Values.catalog.storage.gcs.useCredentialsFile }}
- name: GOOGLE_APPLICATION_CREDENTIALS
  value: "/opt/dremio/gcs/credentials.json"
{{- else }}
- name: dremio.catalog.storage.gcs-service-account
  value: "{{ .Values.catalog.storage.gcs.serviceAccount }}"
{{- end }}
{{- end }}
{{- end -}}

{{/*
Catalog Server - Dremio Catalog - Pod Annotations
*/}}
{{- define "dremio.catalog.podAnnotations" -}}
{{- $podAnnotations := coalesce $.Values.catalog.podAnnotations $.Values.podAnnotations -}}
{{- if $podAnnotations -}}
{{ toYaml $podAnnotations }}
{{- end -}}
{{- end -}}

{{/*
Catalog Server - Dremio Catalog - PriorityClassName
*/}}
{{- define "dremio.catalog.priorityClassName" -}}
{{- if $.Values.catalog.priorityClassName -}}
priorityClassName: {{ $.Values.catalog.priorityClassName }}
{{- end -}}
{{- end -}}

{{/*
Catalog Server - Dremio Catalog - Pod Node Selectors
*/}}
{{- define "dremio.catalog.nodeSelector" -}}
{{- $catalogNodeSelector := coalesce $.Values.catalog.nodeSelector $.Values.nodeSelector -}}
{{- if $catalogNodeSelector -}}
nodeSelector:
  {{- toYaml $catalogNodeSelector | nindent 2 }}
{{- end -}}
{{- end -}}

{{/*
Catalog Server - Dremio Catalog - External Access Pod Node Selectors
*/}}
{{- define "dremio.catalog.externalAccess.nodeSelector" -}}
{{- $catalogExternalAccessNodeSelector := coalesce $.Values.catalog.externalAccess.nodeSelector $.Values.catalog.nodeSelector $.Values.nodeSelector -}}
{{- if $catalogExternalAccessNodeSelector -}}
nodeSelector:
  {{- toYaml $catalogExternalAccessNodeSelector | nindent 2 }}
{{- end -}}
{{- end -}}

{{/*
Catalog Server - Dremio Catalog - External Access Tolerations
*/}}
{{- define "dremio.catalog.externalAccess.tolerations" -}}
{{- $tolerations := coalesce $.Values.catalog.externalAccess.tolerations $.Values.catalog.tolerations $.Values.tolerations -}}
{{- if $tolerations -}}
tolerations:
  {{- toYaml $tolerations | nindent 2 }}
{{- end -}}
{{- end -}}

{{/*
Catalog Server - Dremio Catalog - Tolerations
*/}}
{{- define "dremio.catalog.tolerations" -}}
{{- $tolerations := coalesce $.Values.catalog.tolerations $.Values.tolerations -}}
{{- if $tolerations -}}
tolerations:
  {{- toYaml $tolerations | nindent 2 }}
{{- end -}}
{{- end -}}

{{/*
Catalog Server - Dremio Catalog - Annotations
*/}}
{{- define "dremio.catalog.annotations" -}}
{{- $annotations := coalesce $.Values.catalog.annotations $.Values.annotations -}}
{{- if $annotations -}}
annotations:
  {{- toYaml $annotations | nindent 2 }}
{{- end -}}
{{- end -}}

{{/*
Catalog - Pod Labels
*/}}
{{- define "dremio.catalog.podLabels" -}}
{{- $podLabels := coalesce $.Values.catalog.podLabels $.Values.podLabels -}}
{{- if $podLabels -}}
{{ toYaml $podLabels }}
{{- end -}}
{{- end -}}

{{/*
Catalog - Pod Security Context
*/}}
{{- define "dremio.catalog.podSecurityContext" -}}
{{- if $.Values.catalog.podSecurityContext }}
securityContext:
  {{- toYaml $.Values.catalog.podSecurityContext | nindent 2 }}
{{- else }}
securityContext:
  fsGroup: 10001
  seccompProfile:
    type: RuntimeDefault
{{- end -}}
{{- end -}}

{{/*
Catalog - Container Security Context
*/}}
{{- define "dremio.catalog.containerSecurityContext" -}}
{{- if $.Values.catalog.containerSecurityContext }}
securityContext:
  {{- toYaml $.Values.catalog.containerSecurityContext | nindent 2 }}
{{- else }}
securityContext:
  runAsUser: 10000
  runAsGroup: 10001
  runAsNonRoot: true
  privileged: false
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop:
      - ALL
{{- end -}}
{{- end -}}

{{/*
Catalog - Copy Run Scripts Init Container
*/}}
{{- define "dremio.catalog.copyRunScriptsInitContainer" -}}
- name: copy-run-scripts
  {{- include "dremio.catalog.containerSecurityContext" $ | nindent 2 }}
  image: {{ $.Values.catalog.image.repository }}:{{ $.Values.catalog.image.tag }}
  imagePullPolicy: {{ $.Values.catalog.image.pullPolicy }}
  command: [ "sh", "-c", "cp /opt/jboss/container/java/run/* /mnt/rundir" ]
  resources:
    limits:
      cpu: 100m
      memory: 200Mi
    requests:
      cpu: 100m
      memory: 200Mi
  volumeMounts:
    - name: run-scripts
      mountPath: /mnt/rundir
{{- end -}}

{{/*
Catalog - Start Parameters
*/}}
{{- define "dremio.catalog.extraStartParams" -}}
{{- $catalogExtraStartParams := coalesce $.Values.catalog.extraStartParams $.Values.extraStartParams -}}
{{- if $catalogExtraStartParams}}
- name: JAVA_OPTS_APPEND
  value: >-
    {{ tpl $catalogExtraStartParams $ }}
{{- end -}}
{{- end -}}

{{/*
Catalog - Pod Extra Init Containers
*/}}
{{- define "dremio.catalog.extraInitContainers" -}}
{{- $catalogExtraInitContainers := coalesce $.Values.catalog.extraInitContainers $.Values.extraInitContainers -}}
{{- if $catalogExtraInitContainers -}}
{{- if kindIs "string" $catalogExtraInitContainers }}
{{ tpl $catalogExtraInitContainers $ }}
{{- else -}}
{{ tpl (toYaml $catalogExtraInitContainers) $ }}
{{- end -}}
{{- end -}}
{{- end -}}
