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
