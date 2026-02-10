{{/**
Copyright (C) 2017-2019 Dremio Corporation. This file is confidential and private property.
**/}}

{{/*
MongoDB - Cluster Name
*/}}
{{- define "dremio.mongodb.cluster" -}}
{{ .Release.Name }}-mongodb
{{- end -}}

{{/*
MongoDB - Database Name
*/}}
{{- define "dremio.mongodb.db" -}}
dremio
{{- end -}}

{{/*
MongoDB - User Name
*/}}
{{- define "dremio.mongodb.user" -}}
dremio
{{- end -}}

{{/*
MongoDB - User Secret Name
*/}}
{{- define "dremio.mongodb.userSecret" -}}
{{ include "dremio.mongodb.cluster" . }}-app-users
{{- end -}}

{{/*
MongoDB - Monitor User key in the Secret
*/}}
{{- define "dremio.mongodb.monitorUserKey" -}}
MONGODB_CLUSTER_MONITOR_USER
{{- end -}}

{{/*
MongoDB - Monitor User password key in the Secret
*/}}
{{- define "dremio.mongodb.monitorPasswordKey" -}}
MONGODB_CLUSTER_MONITOR_PASSWORD
{{- end -}}

{{/*
MongoDB - Monitor User secret
*/}}
{{- define "dremio.mongodb.monitorUserSecret" -}}
{{ include "dremio.mongodb.cluster" . }}-system-users
{{- end -}}

{{/*
MongoDB - Host FQDN
*/}}
{{- define "dremio.mongodb.host" -}}
{{ printf "%s-rs0.%s.svc.%s" (include "dremio.mongodb.cluster" .) .Release.Namespace .Values.cluster.domain }}
{{- end -}}

{{/*
MongoDB - Connection String
*/}}
{{- define "dremio.mongodb.connectionString" -}}
mongodb://{{ include "dremio.mongodb.host" . }}:27017/{{ include "dremio.mongodb.db" . }}?ssl=false&replicaSet=rs0
{{- end -}}

{{/*
MongoDB - Connection String for Coordinators
*/}}
{{- define "dremio.mongodb.coordinator.connectionString" -}}
mongodb://{{ include "dremio.mongodb.host" . }}:27017/?ssl=false&replicaSet=rs0
{{- end -}}

{{/*
MongoDB - Wait for MongoDB Init Container
Note: a Volume named "temp-dir" must be declared in the parent Pod template.
*/}}
{{- define "dremio.mongodb.waitForMongoInitContainer" -}}
- name: wait-for-mongo
  image: {{ $.Values.mongodb.image.repository }}:{{ $.Values.mongodb.image.tag }}
  imagePullPolicy: {{ $.Values.mongodb.image.pullPolicy }}
  env:
    - name: MONGODB_USERNAME
      value: "{{ include "dremio.mongodb.user" $ }}"
    - name: MONGODB_PASSWORD
      valueFrom:
        secretKeyRef:
          name: "{{ include "dremio.mongodb.userSecret" $ }}"
          key: "{{ include "dremio.mongodb.user" $ }}"
    - name: MONGODB_CONNECTION_STRING
      value: "{{ include "dremio.mongodb.connectionString" $ }}"
  command:
    - "sh"
    - "-c"
    - |
      while : ; do
        echo "Waiting for MongoDB connectivity..."
        if mongosh --quiet "$(MONGODB_CONNECTION_STRING)" --username "$(MONGODB_USERNAME)" --password "$(MONGODB_PASSWORD)" \
         --eval '
          disableTelemetry()
          let hello = db.hello()
          if ((hello.isWritablePrimary || hello.secondary) && hello.hosts.length > {{ if .Values.devMode -}}0{{- else -}}2{{- end }}) {
            print("MongoDB service looks ready")
          } else {
            throw new Error("MongoDB service not ready, retrying in 5 seconds...")
          }'; then
          break
        fi
        sleep 5
      done
  {{- include "dremio.mongodb.waitContainerSecurityContext" $ | nindent 2 }}
  resources:
    limits:
      cpu: 100m
      memory: 200Mi
    requests:
      cpu: 100m
      memory: 200Mi
  volumeMounts:
    - name: temp-dir
      mountPath: /.mongodb
{{- end -}}

{{/*
MongoDB - Metrics Port - Internal
*/}}
{{- define "dremio.mongodb.ports.metrics.internal" -}}
9216
{{- end -}}

{{/*
MongoDB - PriorityClassName
*/}}
{{- define "dremio.mongodb.priorityClassName" -}}
{{- if $.Values.mongodb.priorityClassName -}}
priorityClassName: {{ $.Values.mongodb.priorityClassName }}
{{- end -}}
{{- end -}}

{{/*
MongoDB - Tolerations
*/}}
{{- define "dremio.mongodb.tolerations" -}}
{{- $tolerations := coalesce $.Values.mongodb.tolerations $.Values.tolerations -}}
{{- if $tolerations -}}
tolerations:
  {{- toYaml $tolerations | nindent 2 }}
{{- end -}}
{{- end -}}

{{/*
MongoDB - Pod Annotations
*/}}
{{- define "dremio.mongodb.podAnnotations" -}}
{{- $podAnnotations := coalesce $.Values.mongodb.annotations $.Values.podAnnotations -}}
{{- if $podAnnotations -}}
{{ toYaml $podAnnotations }}
{{- end -}}
{{- end -}}

{{/*
MongoDB - Pod Node Selectors
*/}}
{{- define "dremio.mongodb.nodeSelector" -}}
{{- $mongoNodeSelector := coalesce $.Values.mongodb.nodeSelector $.Values.nodeSelector -}}
{{- if $mongoNodeSelector -}}
nodeSelector:
  {{- toYaml $mongoNodeSelector | nindent 2 }}
{{- end -}}
{{- end -}}

{{/*
MongoDB - Annotations
*/}}
{{- define "dremio.mongodb.annotations" -}}
{{- $annotations := coalesce $.Values.mongodb.annotations $.Values.annotations -}}
{{- if $annotations -}}
annotations:
  {{- toYaml $annotations | nindent 2 }}
{{- end -}}
{{- end -}}


{{/*
MongoDB - Pod Labels
*/}}
{{- define "dremio.mongodb.podLabels" -}}
{{- $podLabels := coalesce $.Values.mongodb.labels $.Values.podLabels -}}
{{- if $podLabels -}}
labels:
  {{- toYaml $podLabels | nindent 2 }}
{{- end -}}
{{- end -}}

{{/*
MongoDB - Storage Class
*/}}
{{- define "dremio.mongodb.storageClass" -}}
{{- $mongodbStorageClass := coalesce $.Values.mongodb.storageClass $.Values.storageClass -}}
{{- if $mongodbStorageClass -}}
storageClassName: {{ $mongodbStorageClass }}
{{- end -}}
{{- end -}}

{{/*
MongoDB Hooks - Pod Node Selectors
*/}}
{{- define "dremio.mongodbHooks.nodeSelector" -}}
{{- $mongodbHooksNodeSelector := coalesce $.Values.mongodbHooks.nodeSelector $.Values.nodeSelector -}}
{{- if $mongodbHooksNodeSelector -}}
nodeSelector:
  {{- toYaml $mongodbHooksNodeSelector | nindent 2 }}
{{- end -}}
{{- end -}}

{{/*
MongoDB Hooks - PriorityClassName
*/}}
{{- define "dremio.mongodbHooks.priorityClassName" -}}
{{- if $.Values.mongodbHooks.priorityClassName -}}
priorityClassName: {{ $.Values.mongodbHooks.priorityClassName }}
{{- end -}}
{{- end -}}

{{/*
MongoDB Hooks - Tolerations
*/}}
{{- define "dremio.mongodbHooks.tolerations" -}}
{{- $tolerations := coalesce $.Values.mongodbHooks.tolerations $.Values.tolerations -}}
{{- if $tolerations -}}
tolerations:
  {{- toYaml $tolerations | nindent 2 }}
{{- end -}}
{{- end -}}

{{/*
MongoDB - Wait Container Security Context
*/}}
{{- define "dremio.mongodb.waitContainerSecurityContext" -}}
securityContext:
  {{- if hasKey $.Values.mongodb "waitContainer" }}
    {{- if $.Values.mongodb.waitContainer.securityContext }}
  {{- toYaml $.Values.mongodb.waitContainer.securityContext | nindent 2 }}
    {{- else }}
  allowPrivilegeEscalation: false
  capabilities:
    drop:
    - ALL
  privileged: false
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  runAsGroup: 65534
  runAsUser: 65534
    {{- end }}
  {{- else }}
  allowPrivilegeEscalation: false
  capabilities:
    drop:
    - ALL
  privileged: false
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  runAsGroup: 65534
  runAsUser: 65534
  {{- end }}
{{- end -}}

{{/*
MongoDB - Backup - Container Security Context
  Falls back to global containerSecurityContext.
Note: backups are done by a sidecar container running PBM.
They do not use CronJobs anymore, so we don't need to define podSecurityContext for backups.
*/}}
{{- define "dremio.mongodb.backup.containerSecurityContext" -}}
containerSecurityContext:
{{- if $.Values.mongodb.backup.containerSecurityContext }}
  {{- toYaml $.Values.mongodb.backup.containerSecurityContext | nindent 2 }}
{{- else if $.Values.mongodb.containerSecurityContext }}
  {{- toYaml $.Values.mongodb.containerSecurityContext | nindent 2 }}
{{- else }}
  {{- toYaml $.Values.containerSecurityContext | nindent 2 }}
{{- end }}
{{- end -}}

{{/*
MongoDB - Backup - Storage Logical Name
*/}}
{{- define "dremio.mongodb.backup.storage.name" -}}
{{ .Release.Name }}-catalog-backups
{{- end }}

{{/*
MongoDB - Backup - Storage Prefix (path within bucket)
*/}}
{{- define "dremio.mongodb.backup.storage.prefix" -}}
{{- $path := trimSuffix "/" . }}
{{- $path = printf "%s/catalog-backups" $path }}
{{- $path = trimPrefix "/" $path }}
{{- $path }}
{{- end }}

{{/*
MongoDB - Backup - Storage Secret Name
*/}}
{{- define "dremio.mongodb.backup.storage.secretName" -}}
{{ .Release.Name }}-mongodb-backup
{{- end }}

{{/*
MongoDB - Backup - Storage Secret Availability
*/}}
{{- define "dremio.mongodb.backup.storage.secretAvailable" }}
{{- if or
  (and (eq .Values.distStorage.type "aws") .Values.distStorage.aws.credentials.accessKey .Values.distStorage.aws.credentials.secret)
  (and (eq .Values.distStorage.type "gcp") .Values.distStorage.gcp.credentials.clientEmail .Values.distStorage.gcp.credentials.privateKey)
  (and (eq .Values.distStorage.type "azureStorage") .Values.distStorage.azureStorage.credentials.accessKey)
}}1{{ end -}}
{{- end }}

{{/*
MongoDB - Backup - MonrogDB CRD Storage Configuration
*/}}
{{- define "dremio.mongodb.backup.storage" }}
{{- $distStorageType := $.Values.distStorage.type | default false }}
{{- $mongoStorageType := "s3" }}
{{- if eq $.Values.distStorage.type "gcp" }}
{{- $mongoStorageType = "gcs" }}
{{- else if eq $.Values.distStorage.type "azureStorage" }}
{{- $mongoStorageType = "azure" }}
{{- end }}
{{- include "dremio.mongodb.backup.storage.name" $ }}:
  type: {{ $mongoStorageType }}
  main: true
  {{- if eq $mongoStorageType "s3" }}
  s3:
    bucket: {{ $.Values.distStorage.aws.bucketName | quote }}
    region: {{ $.Values.distStorage.aws.region | quote }}
    {{- if $.Values.distStorage.aws.endpoint }}
    endpointUrl: {{ $.Values.distStorage.aws.endpoint | quote }}
    {{- end }}
    {{- if not $.Values.distStorage.aws.tls }}
    insecureSkipTLSVerify: true
    {{- end }}
    prefix: {{ include "dremio.mongodb.backup.storage.prefix" $.Values.distStorage.aws.path | quote }}
  {{- else if eq $mongoStorageType "gcs" }}
  gcs:
    bucket: {{ $.Values.distStorage.gcp.bucketName | quote }}
    prefix: {{ include "dremio.mongodb.backup.storage.prefix" $.Values.distStorage.gcp.path | quote }}
  {{- else if eq $mongoStorageType "azure" }}
  azure:
    container: {{ $.Values.distStorage.azureStorage.filesystem | quote }}
    prefix: {{ include "dremio.mongodb.backup.storage.prefix" $.Values.distStorage.azureStorage.path | quote }}
  {{- end }}
  {{- $secretAvailable := include "dremio.mongodb.backup.storage.secretAvailable" . }}
  {{- if $secretAvailable }}
    credentialsSecret: {{ include "dremio.mongodb.backup.storage.secretName" $ }}
  {{- end }}
{{- end -}}

{{/*
MongoDB - unsafe flags
*/}}
{{- define "dremio.mongodb.unsafeFlags" -}}
{{- $isDevMode := $.Values.devMode | default false -}}
{{- $disableTls := $.Values.mongodb.disableTls | default false -}}
{{- if or $isDevMode $disableTls }}
unsafeFlags:
  {{- if $isDevMode }}
  replsetSize: true
  {{- end }}
  {{- if $disableTls }}
  tls: true
  {{- end }}
{{- end }}
{{- end -}}

{{/*
MongoDB - TLS Mode
*/}}
{{- define "dremio.mongodb.tlsMode" -}}
{{- $disableTls := $.Values.mongodb.disableTls | default false -}}
{{- if $disableTls -}}
disabled
{{- else -}}
preferTLS
{{- end -}}
{{- end -}}

{{/*
MongoDB - Pod Security Context
  Falls back to global podSecurityContext.
*/}}
{{- define "dremio.mongodb.podSecurityContext" -}}
podSecurityContext:
{{- if $.Values.mongodb.podSecurityContext }}
  {{- toYaml $.Values.mongodb.podSecurityContext | nindent 2 }}
{{- else }}
  {{- toYaml $.Values.podSecurityContext | nindent 2 }}
{{- end }}
{{- end -}}

{{/*
MongoDB - Container Security Context
  Falls back to global containerSecurityContext.
*/}}
{{- define "dremio.mongodb.containerSecurityContext" -}}
containerSecurityContext:
{{- if $.Values.mongodb.containerSecurityContext }}
  {{- toYaml $.Values.mongodb.containerSecurityContext | nindent 2 }}
{{- else }}
  {{- toYaml $.Values.containerSecurityContext | nindent 2 }}
{{- end }}
{{- end -}}

{{/*
MongoDB - Init Container Security Context
  Falls back to global containerSecurityContext.
*/}}
{{- define "dremio.mongodb.initContainerSecurityContext" -}}
initContainerSecurityContext:
{{- if $.Values.mongodb.initContainerSecurityContext }}
  {{- toYaml $.Values.mongodb.initContainerSecurityContext | nindent 2 }}
{{- else if $.Values.mongodb.containerSecurityContext }}
  {{- toYaml $.Values.mongodb.containerSecurityContext | nindent 2 }}
{{- else }}
  {{- toYaml $.Values.containerSecurityContext | nindent 2 }}
{{- end }}
{{- end -}}

{{/*
MongoDB - Sidecar Container Security Context
  Falls back to global containerSecurityContext.
*/}}
{{- define "dremio.mongodb.sidecarContainerSecurityContext" -}}
securityContext:
{{- if $.Values.mongodb.sidecarContainerSecurityContext }}
  {{- toYaml $.Values.mongodb.sidecarContainerSecurityContext | nindent 2 }}
{{- else if $.Values.mongodb.containerSecurityContext }}
  {{- toYaml $.Values.mongodb.containerSecurityContext | nindent 2 }}
{{- else }}
  {{- toYaml $.Values.containerSecurityContext | nindent 2 }}
{{- end }}
{{- end -}}