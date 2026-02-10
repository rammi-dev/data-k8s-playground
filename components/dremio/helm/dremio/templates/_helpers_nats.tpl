{{/**
Copyright (C) 2017-2019 Dremio Corporation. This file is confidential and private property.
**/}}

{{/* Nats Service Name */}}
{{- define "dremio.nats.serviceName" -}}
  {{- $defaultName := printf "%s-nats" .Release.Name -}}
  {{- .Values.nats.serviceName | default $defaultName -}}
{{- end -}}

{{/* Nats Service Port */}}
{{- define "dremio.nats.servicePort" -}}
  {{- $defaultPort := 4222 -}}
  {{- ((((.Values.nats).config).nats).port) | default $defaultPort -}}
{{- end -}}
