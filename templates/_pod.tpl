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

{{- /*
Returns "true" when the chart should add its /tmp emptyDir: tmpDir is enabled
and no root volumeMounts entry already mounts /tmp. Takes the root context.
*/ -}}
{{- define "shipform.needsTmpDir" -}}
{{- $root := . -}}
{{- $mounted := false -}}
{{- range ($root.Values.volumeMounts | default list) -}}
{{- if eq (toString .mountPath) "/tmp" -}}
{{- $mounted = true -}}
{{- end -}}
{{- end -}}
{{- if and $root.Values.tmpDir.enabled (not $mounted) -}}
true
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
{{- if include "shipform.needsTmpDir" $root -}}
{{- $volumeMounts = append $volumeMounts (dict "name" "tmp" "mountPath" "/tmp") -}}
{{- end -}}
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
enableServiceLinks: {{ $root.Values.enableServiceLinks }}
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
{{- $volumes := $root.Values.volumes | default list -}}
{{- if include "shipform.needsTmpDir" $root -}}
{{- $emptyDir := dict "sizeLimit" $root.Values.tmpDir.sizeLimit -}}
{{- with $root.Values.tmpDir.medium -}}
{{- $_ := set $emptyDir "medium" . -}}
{{- end -}}
{{- $volumes = append $volumes (dict "name" "tmp" "emptyDir" $emptyDir) -}}
{{- end -}}
{{- with $volumes }}
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

{{/*
Resolve a service port reference to its number. Takes (dict "root" $ "port" <string|int>).
A name matches service.ports[].name; a number matches service.ports[].port.
Compares with toString so int, int64 and float64 (from --set) all work.
Returns the number as an integer string, or "" when no entry matches.
*/ -}}
{{- define "shipform.servicePortNumber" -}}
{{- $want := toString .port -}}
{{- $found := "" -}}
{{- range (.root.Values.service.ports | default list) -}}
{{- if and (eq $found "") (or (eq (toString .name) $want) (eq (toString .port) $want)) -}}
{{- $found = printf "%d" (int64 .port) -}}
{{- end -}}
{{- end -}}
{{- $found -}}
{{- end -}}

{{/*
Render the rules of a Gateway API route. Takes (dict "root" $ "rules" <list> "default" <port>).
*/ -}}
{{- define "shipform.routeRules" -}}
{{- $root := .root -}}
{{- range .rules }}
- {{- with .matches }}
  matches:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .filters }}
  filters:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .timeouts }}
  timeouts:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  backendRefs:
    - name: {{ include "shipform.fullname" $root }}
      port: {{ include "shipform.servicePortNumber" (dict "root" $root "port" (default $.default .servicePort)) }}
{{- end }}
{{- end -}}
