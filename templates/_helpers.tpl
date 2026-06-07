{{/*
Expand the chart name.
*/}}
{{- define "application-chart.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a fully qualified app name.
*/}}
{{- define "application-chart.fullname" -}}
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
{{- define "application-chart.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels.
*/}}
{{- define "application-chart.labels" -}}
helm.sh/chart: {{ include "application-chart.chart" . }}
{{ include "application-chart.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/component: {{ default "application" .Values.component | quote }}
app.kubernetes.io/part-of: {{ default (include "application-chart.name" .) .Values.partOf | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.labels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/*
Selector labels must remain stable across upgrades.
*/}}
{{- define "application-chart.selectorLabels" -}}
app.kubernetes.io/name: {{ include "application-chart.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
ServiceAccount name.
*/}}
{{- define "application-chart.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "application-chart.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "application-chart.configMapName" -}}
{{- default (printf "%s-config" (include "application-chart.fullname" .)) .Values.configMap.name -}}
{{- end -}}

{{- define "application-chart.secretName" -}}
{{- default (printf "%s-secret" (include "application-chart.fullname" .)) .Values.secret.name -}}
{{- end -}}

{{- define "application-chart.externalSecretTargetName" -}}
{{- default (include "application-chart.secretName" .) .Values.externalSecret.target.name -}}
{{- end -}}

{{- define "application-chart.image" -}}
{{- $image := .image -}}
{{- printf "%s:%s" $image.repository $image.tag | quote -}}
{{- end -}}

{{- define "application-chart.probe" -}}
{{- $probe := . -}}
{{- if $probe.enabled }}
{{- omit $probe "enabled" | toYaml -}}
{{- end -}}
{{- end -}}

{{- define "application-chart.container" -}}
{{- $root := .root -}}
{{- $container := .container | default dict -}}
{{- $image := default $root.Values.image $container.image -}}
{{- $ports := $root.Values.containerPorts -}}
{{- if hasKey $container "ports" -}}
{{- $ports = $container.ports -}}
{{- end -}}
{{- $env := concat ($root.Values.env | default list) ($container.env | default list) -}}
{{- $envFrom := concat ($root.Values.envFrom | default list) ($container.envFrom | default list) -}}
{{- $resources := default $root.Values.resources $container.resources -}}
{{- $volumeMounts := concat ($root.Values.volumeMounts | default list) ($container.volumeMounts | default list) -}}
{{- $command := default $root.Values.command $container.command -}}
{{- $args := default $root.Values.args $container.args -}}
{{- $livenessProbe := default $root.Values.livenessProbe $container.livenessProbe -}}
{{- $readinessProbe := default $root.Values.readinessProbe $container.readinessProbe -}}
{{- $startupProbe := default $root.Values.startupProbe $container.startupProbe -}}
{{- $securityContext := default $root.Values.securityContext $container.securityContext -}}
{{- $lifecycle := default $root.Values.lifecycle $container.lifecycle -}}
- name: {{ default (include "application-chart.name" $root) $container.name }}
  image: {{ include "application-chart.image" (dict "image" $image) }}
  imagePullPolicy: {{ default "IfNotPresent" $image.pullPolicy }}
{{- with $command }}
  command:
{{ toYaml . | nindent 4 }}
{{- end }}
{{- with $args }}
  args:
{{ toYaml . | nindent 4 }}
{{- end }}
{{- with $ports }}
  ports:
{{ toYaml . | nindent 4 }}
{{- end }}
{{- with $env }}
  env:
{{ toYaml . | nindent 4 }}
{{- end }}
{{- with $envFrom }}
  envFrom:
{{ toYaml . | nindent 4 }}
{{- end }}
{{- if and $livenessProbe $livenessProbe.enabled }}
  livenessProbe:
{{ include "application-chart.probe" $livenessProbe | nindent 4 }}
{{- end }}
{{- if and $readinessProbe $readinessProbe.enabled }}
  readinessProbe:
{{ include "application-chart.probe" $readinessProbe | nindent 4 }}
{{- end }}
{{- if and $startupProbe $startupProbe.enabled }}
  startupProbe:
{{ include "application-chart.probe" $startupProbe | nindent 4 }}
{{- end }}
{{- with $resources }}
  resources:
{{ toYaml . | nindent 4 }}
{{- end }}
{{- with $securityContext }}
  securityContext:
{{ toYaml . | nindent 4 }}
{{- end }}
{{- with $lifecycle }}
  lifecycle:
{{ toYaml . | nindent 4 }}
{{- end }}
{{- with $volumeMounts }}
  volumeMounts:
{{ toYaml . | nindent 4 }}
{{- end }}
{{- end -}}

{{- define "application-chart.podSpec" -}}
{{- $root := .root -}}
{{- $container := .container | default dict -}}
{{- $restartPolicy := .restartPolicy | default "Always" -}}
{{- with $root.Values.imagePullSecrets }}
imagePullSecrets:
{{ toYaml . | nindent 2 }}
{{- end }}
serviceAccountName: {{ include "application-chart.serviceAccountName" $root }}
{{- with $root.Values.podSecurityContext }}
securityContext:
{{ toYaml . | nindent 2 }}
{{- end }}
{{- with $root.Values.priorityClassName }}
priorityClassName: {{ . }}
{{- end }}
{{- with $root.Values.runtimeClassName }}
runtimeClassName: {{ . }}
{{- end }}
restartPolicy: {{ $restartPolicy }}
{{- with $root.Values.initContainers }}
initContainers:
{{ toYaml . | nindent 2 }}
{{- end }}
containers:
{{ include "application-chart.container" (dict "root" $root "container" $container) | nindent 2 }}
{{- with $root.Values.extraContainers }}
{{ toYaml . | nindent 2 }}
{{- end }}
{{- with $root.Values.volumes }}
volumes:
{{ toYaml . | nindent 2 }}
{{- end }}
{{- with $root.Values.nodeSelector }}
nodeSelector:
{{ toYaml . | nindent 2 }}
{{- end }}
{{- with $root.Values.affinity }}
affinity:
{{ toYaml . | nindent 2 }}
{{- end }}
{{- with $root.Values.tolerations }}
tolerations:
{{ toYaml . | nindent 2 }}
{{- end }}
{{- with $root.Values.topologySpreadConstraints }}
topologySpreadConstraints:
{{ toYaml . | nindent 2 }}
{{- end }}
{{- with $root.Values.terminationGracePeriodSeconds }}
terminationGracePeriodSeconds: {{ . }}
{{- end }}
{{- end -}}
