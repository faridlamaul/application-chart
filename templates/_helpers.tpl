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
Common labels.
*/}}
{{- define "shipform.labels" -}}
{{- include "shipform.labelsWith" (dict "root" . "extra" dict) -}}
{{- end -}}

{{/*
Common labels plus a resource's own labels. Precedence: selector labels (never
replaced), then the resource's labels, then .Values.labels, then the standard
labels, so overrides replace keys instead of duplicating them.
*/}}
{{- define "shipform.labelsWith" -}}
{{- $root := .root -}}
{{- $standard := dict
  "helm.sh/chart" (include "shipform.chart" $root)
  "app.kubernetes.io/component" (default "application" $root.Values.component)
  "app.kubernetes.io/part-of" (default (include "shipform.name" $root) $root.Values.partOf)
  "app.kubernetes.io/managed-by" $root.Release.Service -}}
{{- with $root.Chart.AppVersion }}
{{- $_ := set $standard "app.kubernetes.io/version" . }}
{{- end }}
{{- $selector := include "shipform.selectorLabels" $root | fromYaml -}}
{{- $labels := merge $selector (deepCopy (.extra | default dict)) (deepCopy ($root.Values.labels | default dict)) $standard -}}
{{- toYaml $labels -}}
{{- end -}}

{{/*
Selector labels must remain stable across upgrades.
*/}}
{{- define "shipform.selectorLabels" -}}
app.kubernetes.io/name: {{ include "shipform.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
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

{{- define "shipform.image" -}}
{{- $image := .image -}}
{{- printf "%s:%s" $image.repository $image.tag | quote -}}
{{- end -}}

{{- define "shipform.probe" -}}
{{- $probe := . -}}
{{- if $probe.enabled }}
{{- omit $probe "enabled" | toYaml -}}
{{- end -}}
{{- end -}}

{{- define "shipform.container" -}}
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
{{- /* A key present in the container overrides the root value, even when empty. */ -}}
{{- $livenessProbe := ternary $container.livenessProbe $root.Values.livenessProbe (hasKey $container "livenessProbe") -}}
{{- $readinessProbe := ternary $container.readinessProbe $root.Values.readinessProbe (hasKey $container "readinessProbe") -}}
{{- $startupProbe := ternary $container.startupProbe $root.Values.startupProbe (hasKey $container "startupProbe") -}}
{{- $securityContext := default $root.Values.securityContext $container.securityContext -}}
{{- $lifecycle := default $root.Values.lifecycle $container.lifecycle -}}
- name: {{ default (include "shipform.name" $root) $container.name }}
  image: {{ include "shipform.image" (dict "image" $image) }}
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
{{ include "shipform.probe" $livenessProbe | nindent 4 }}
{{- end }}
{{- if and $readinessProbe $readinessProbe.enabled }}
  readinessProbe:
{{ include "shipform.probe" $readinessProbe | nindent 4 }}
{{- end }}
{{- if and $startupProbe $startupProbe.enabled }}
  startupProbe:
{{ include "shipform.probe" $startupProbe | nindent 4 }}
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

{{- define "shipform.podSpec" -}}
{{- $root := .root -}}
{{- $container := .container | default dict -}}
{{- $restartPolicy := .restartPolicy | default "Always" -}}
{{- with $root.Values.imagePullSecrets }}
imagePullSecrets:
{{ toYaml . | nindent 2 }}
{{- end }}
serviceAccountName: {{ include "shipform.serviceAccountName" $root }}
automountServiceAccountToken: {{ $root.Values.serviceAccount.automount }}
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
{{ include "shipform.container" (dict "root" $root "container" $container) | nindent 2 }}
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
{{- if not (kindIs "invalid" $root.Values.terminationGracePeriodSeconds) }}
terminationGracePeriodSeconds: {{ $root.Values.terminationGracePeriodSeconds }}
{{- end }}
{{- end -}}
