{{/*
Expand the chart name.
*/}}
{{- define "shipform.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a fully qualified app name.
*/}}
{{- define "shipform.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version label value.
*/}}
{{- define "shipform.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
ServiceAccount name.
*/}}
{{- define "shipform.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "shipform.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Governing Service of a StatefulSet. It must be headless for stable per-pod DNS:
the main Service when it is headless, otherwise the chart's -headless Service.
*/}}
{{- define "shipform.statefulSetServiceName" -}}
{{- if .Values.statefulSet.serviceName -}}
{{- .Values.statefulSet.serviceName -}}
{{- else if and .Values.service.enabled .Values.service.headless -}}
{{- include "shipform.fullname" . -}}
{{- else -}}
{{- printf "%s-headless" (include "shipform.fullname" . | trunc 54 | trimSuffix "-") -}}
{{- end -}}
{{- end -}}

{{- define "shipform.configMapName" -}}
{{- default (printf "%s-config" (include "shipform.fullname" .)) .Values.configMap.name -}}
{{- end -}}

{{- define "shipform.secretName" -}}
{{- default (printf "%s-secret" (include "shipform.fullname" .)) .Values.secret.name -}}
{{- end -}}

{{- define "shipform.externalSecretTargetName" -}}
{{- default (include "shipform.secretName" .) .Values.externalSecret.target.name -}}
{{- end -}}

{{- define "shipform.persistenceClaimName" -}}
{{- default (printf "%s-data" (include "shipform.fullname" . | trunc 58 | trimSuffix "-")) .Values.persistence.existingClaim -}}
{{- end -}}

{{/*
Companion Job or CronJob name: <fullname>-<key>. Not truncated; shipform.validate
fails instead, so two keys can never collide. Takes (dict "root" $ "key" <key>).
*/}}
{{- define "shipform.companionName" -}}
{{- printf "%s-%s" (include "shipform.fullname" .root) .key -}}
{{- end -}}

{{/*
ServiceAccount of a companion. Takes (dict "root" $ "job" <entry>). An explicit
serviceAccountName wins. A hook that includes pre-install runs before the
chart's ServiceAccount exists, so it uses "default" when serviceAccount.create
is true. Every other companion uses shipform.serviceAccountName.
*/}}
{{- define "shipform.companionServiceAccountName" -}}
{{- $root := .root -}}
{{- $job := .job -}}
{{- $preInstall := false -}}
{{- range (splitList "," (toString (default "" $job.hook))) -}}
{{- if eq (trim .) "pre-install" -}}
{{- $preInstall = true -}}
{{- end -}}
{{- end -}}
{{- if $job.serviceAccountName -}}
{{- $job.serviceAccountName -}}
{{- else if and $preInstall $root.Values.serviceAccount.create -}}
default
{{- else -}}
{{- include "shipform.serviceAccountName" $root -}}
{{- end -}}
{{- end -}}
