{{/*
Cross-field validation. Included by templates/validate.yaml so every rule runs
on each render. Renders nothing; calls `fail` on invalid combinations.
*/}}
{{- define "shipform.validate" -}}
{{- if include "shipform.needsTmpDir" . -}}
{{- range (.Values.volumes | default list) -}}
{{- if eq (toString .name) "tmp" -}}
{{- fail "volumes: the name \"tmp\" is reserved while tmpDir.enabled is true; rename the volume or set tmpDir.enabled=false" -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- if and .Values.persistence.enabled (eq .Values.workload.type "StatefulSet") -}}
{{- fail "persistence is not supported for workload.type StatefulSet; use statefulSet.volumeClaimTemplates" -}}
{{- end -}}
{{- range $kind := list "httpRoute" "grpcRoute" -}}
{{- $route := index $.Values $kind -}}
{{- if $route.enabled -}}
{{- if not $.Values.service.enabled -}}
{{- fail (printf "%s.enabled requires service.enabled=true; the route backend is the chart Service" $kind) -}}
{{- end -}}
{{- $default := ternary "http" "grpc" (eq $kind "httpRoute") -}}
{{- range $i, $rule := $route.rules -}}
{{- $port := default $default $rule.servicePort -}}
{{- if eq (include "shipform.servicePortNumber" (dict "root" $ "port" $port)) "" -}}
{{- fail (printf "%s.rules[%d].servicePort %q matches no service.ports entry" $kind $i (toString $port)) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- range $kind, $max := dict "jobs" 63 "cronJobs" 52 -}}
{{- range $key, $entry := (index $.Values $kind | default dict) -}}
{{- if $entry.enabled -}}
{{- $name := include "shipform.companionName" (dict "root" $ "key" $key) -}}
{{- if gt (len $name) $max -}}
{{- fail (printf "%s.%s: name %s exceeds %d characters; shorten the key or set fullnameOverride" $kind $key $name $max) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
