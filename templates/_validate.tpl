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
{{- end -}}
