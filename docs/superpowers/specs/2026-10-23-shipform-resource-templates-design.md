# Design: shipform resource templates and hardening

Status: Draft · Author: af/faridlamaul · Date: 2026-10-23 · Scope: shipform chart 0.4.0

## Goal

shipform 0.4.0 adds Gateway API routes, companion Jobs and CronJobs, a standalone PVC, KEDA, VPA, PrometheusRule, PodMonitor, and `extraObjects`. Its pod defaults pass Pod Security Standard `restricted` with a read-only root filesystem. The release ships together with the rename to `shipform` (PR #3), so consumers absorb one breaking upgrade instead of two.

## Scope

- In: the blocks in [Values interface](#values-interface), helper split, cross-field validation, schema, unit tests, examples, CI, CHANGELOG, README rewrite.
- Out: a library chart, KEDA `ScaledJob`, cert-manager `Certificate`, Istio or Argo Rollouts resources, `ClusterRole`, more than one chart-managed ConfigMap or Secret, NetworkPolicies for companion pods.

## Constraints

- Every new block defaults to `enabled: false` or an empty map, so the default render changes only through the hardening defaults.
- The schema keeps `additionalProperties: false` at every level it has today, and every new block gets the same.
- Main workload selector labels (`app.kubernetes.io/name`, `app.kubernetes.io/instance`) stay unchanged.
- Minimum Kubernetes stays `>=1.25.0-0`.
- CRD-backed templates render only when enabled; the chart does not install CRDs.

## Structure

`templates/_helpers.tpl` (240 lines) is split by responsibility. The `define` names stay the same, so templates do not change for the split itself.

| File | Contents |
| --- | --- |
| `_names.tpl` | `shipform.name`, `shipform.fullname`, `shipform.chart`, `shipform.serviceAccountName`, `shipform.statefulSetServiceName`, ConfigMap, Secret, and ExternalSecret names, `shipform.companionName` |
| `_labels.tpl` | `shipform.labels`, `shipform.labelsWith`, `shipform.selectorLabels`, `shipform.companionSelectorLabels` |
| `_pod.tpl` | `shipform.image`, `shipform.probe`, `shipform.container`, `shipform.podSpec`, `shipform.servicePortNumber` |
| `_validate.tpl` | `shipform.validate`: every cross-field rule added by this design |

`templates/validate.yaml` includes `shipform.validate` and renders nothing, so the rules run on every render. Existing rules in `hpa.yaml` and `secret.yaml` stay where they are.

## Values interface

### Gateway API routes

`templates/httproute.yaml` and `templates/grpcroute.yaml`, API `gateway.networking.k8s.io/v1`.

```yaml
httpRoute:
  enabled: false
  annotations: {}
  labels: {}
  parentRefs: []        # required, minItems 1 when enabled
  hostnames: []
  rules:
    - matches:
        - path: { type: PathPrefix, value: / }
      filters: []
      timeouts: {}
      servicePort: http  # name or number from service.ports

grpcRoute:
  enabled: false
  annotations: {}
  labels: {}
  parentRefs: []
  hostnames: []
  rules:
    - matches: []        # empty matches every method
      filters: []
      servicePort: grpc
```

- Each rule renders `backendRefs: [{ name: <fullname>, port: <number> }]`. `shipform.servicePortNumber` resolves a name through `service.ports[].name`; a number passes through.
- Render fails when a route is enabled and `service.enabled` is false, or when `servicePort` matches no entry in `service.ports`.
- `matches`, `filters`, and `timeouts` are passed through as given; the schema checks their type only.

### Companion jobs and cron jobs

`templates/companion-jobs.yaml` and `templates/companion-cronjobs.yaml`. Map keys must match `^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`.

```yaml
jobs: {}
#  migrate:
#    enabled: true
#    hook: pre-install,pre-upgrade   # empty: post-install,post-upgrade
#    hookWeight: "0"
#    hookDeletePolicy: before-hook-creation,hook-succeeded
#    serviceAccountName: ""          # see rules below
#    image: {}                       # defaults to .Values.image
#    command: []
#    args: []
#    env: []
#    envFrom: []
#    resources: {}
#    securityContext: {}             # defaults to .Values.securityContext
#    backoffLimit: 3
#    activeDeadlineSeconds: null
#    ttlSecondsAfterFinished: 300
#    restartPolicy: Never
#    annotations: {}
#    labels: {}
#    podAnnotations: {}

cronJobs: {}
#  cleanup:
#    enabled: true
#    schedule: "0 3 * * *"
#    timeZone: ""
#    concurrencyPolicy: Forbid
#    suspend: false
#    successfulJobsHistoryLimit: 3
#    failedJobsHistoryLimit: 1
#    startingDeadlineSeconds: null
#    (plus every Job field above except hook*)
```

- Name: `<fullname>-<key>`. Render fails when the name exceeds 63 characters for a Job or 52 for a CronJob, instead of truncating and risking a collision.
- Pod labels: `app.kubernetes.io/name: <name>-<key>`, `app.kubernetes.io/instance: <release>`, `app.kubernetes.io/component: <key>`. The main Service, PodDisruptionBudget, and NetworkPolicy do not select companion pods.
- Inherited from the root values: image, `imagePullSecrets`, `env`, `envFrom`, `volumes`, `volumeMounts`, `podSecurityContext`, `securityContext`, `nodeSelector`, `tolerations`, `affinity`, `tmpDir`. Not inherited: `command`, `args`, `resources` (each comes only from the entry), probes, `initContainers`, `extraContainers` (a sidecar would keep the Job from completing), `persistence`, `priorityClassName`, `runtimeClassName`, `topologySpreadConstraints`, `terminationGracePeriodSeconds`.
- ServiceAccount: an explicit `serviceAccountName` wins. A hook that includes `pre-install` defaults to `default` when `serviceAccount.create` is true, because the chart's ServiceAccount does not exist yet. Every other companion uses `shipform.serviceAccountName`. `automountServiceAccountToken` follows `serviceAccount.automount`.
- Every companion Job is a Helm hook, because a Job's pod template is immutable. An empty `hook` means `post-install,post-upgrade`.
- Pre-install hooks run before chart-created ConfigMaps, Secrets, and ExternalSecrets exist on first install. The README says so and points to existing Secrets.

### Persistence

`templates/pvc.yaml`.

```yaml
persistence:
  enabled: false
  existingClaim: ""
  storageClassName: null   # null: cluster default; "": no class
  accessModes: [ReadWriteOnce]
  size: 1Gi
  mountPath: /data
  subPath: ""
  annotations: {}
  keep: true               # adds helm.sh/resource-policy: keep
```

- The chart creates `<fullname>-data` unless `existingClaim` is set. The volume `persistence` is added to the pod and mounted in the main container only.
- Render fails for `workload.type: StatefulSet`, which uses `statefulSet.volumeClaimTemplates`.
- README notes that `ReadWriteOnce` with more than one replica, or with `RollingUpdate`, can leave new pods pending.

### KEDA

`templates/scaledobject.yaml`, API `keda.sh/v1alpha1`.

```yaml
keda:
  enabled: false
  annotations: {}
  minReplicaCount: 1
  maxReplicaCount: 10
  idleReplicaCount: null
  pollingInterval: 30
  cooldownPeriod: 300
  fallback: {}
  advanced: {}
  triggers: []             # required, minItems 1 when enabled
```

- Workload types: Deployment and StatefulSet. Both templates omit `replicas` when `keda.enabled`.
- Render fails when `keda.enabled` and `autoscaling.enabled` are both true.

### Vertical pod autoscaler

`templates/vpa.yaml`, API `autoscaling.k8s.io/v1`.

```yaml
verticalPodAutoscaler:
  enabled: false
  updateMode: "Off"        # Off, Initial, Recreate, InPlaceOrRecreate, Auto
  minReplicas: null
  controlledResources: [cpu, memory]
  controlledValues: RequestsAndLimits
  minAllowed: {}
  maxAllowed: {}
```

- Workload types: Deployment and StatefulSet; render fails for the others.
- Render fails when `updateMode` is not `Off` and `autoscaling.enabled` or `keda.enabled` is true.

### Prometheus rules and pod monitors

`templates/prometheusrule.yaml` and `templates/podmonitor.yaml`, API `monitoring.coreos.com/v1`.

```yaml
prometheusRule:
  enabled: false
  namespace: ""
  labels: {}
  annotations: {}
  groups: []               # required, minItems 1 when enabled

podMonitor:
  enabled: false
  namespace: ""
  labels: {}
  annotations: {}
  interval: 30s
  scrapeTimeout: 10s
  path: /metrics
  port: http               # container port name
  scheme: http
  relabelings: []
  metricRelabelings: []
```

- Render fails when `podMonitor.enabled` and `serviceMonitor.enabled` are both true, to avoid scraping each pod twice.

### Extra objects

`templates/extra-objects.yaml`.

```yaml
extraObjects: []
```

- Each item is a map or a string. Maps render through `tpl (toYaml .) $`; strings through `tpl . $`. Items are separated by `---`. The chart adds no labels.

## Security hardening

| Change | Default | Breaking |
| --- | --- | --- |
| `securityContext.readOnlyRootFilesystem` | `true` (was `false`) | Yes |
| `tmpDir` | `{ enabled: true, sizeLimit: 64Mi, medium: "" }`: `emptyDir` at `/tmp` | No |
| `enableServiceLinks` | `false` (Kubernetes default `true`) | Yes |
| `networkPolicy.allowDNS` | `{ enabled: true, to: [kube-system pods with k8s-app: kube-dns] }`, ports 53 UDP and TCP | No; renders only when `policyTypes` has `Egress` |
| Schema guards | Reject `privileged: true`, `hostPath` volumes, and `capabilities.add` other than `NET_BIND_SERVICE` | Yes |

- `tmpDir` is added to the main and companion containers, and skipped when `volumeMounts` already mounts `/tmp`.
- Schema guards apply to `securityContext`, `jobs.*.securityContext`, `cronJobs.*.securityContext`, `initContainers[].securityContext`, `extraContainers[].securityContext`, and `volumes[]`.

## Validation rules

All in `shipform.validate`, each with a message that names the values to change.

| Rule | Message starts with |
| --- | --- |
| Route enabled without Service | `httpRoute.enabled requires service.enabled` (same for `grpcRoute`) |
| Route `servicePort` not in `service.ports` | `httpRoute.rules[N].servicePort "<x>" matches no service.ports entry` |
| Companion name too long | `jobs.<key>: name <name> exceeds 63 characters` |
| Persistence on StatefulSet | `persistence is not supported for workload.type StatefulSet` |
| KEDA with HPA | `keda.enabled and autoscaling.enabled cannot both be true` |
| KEDA on Job or CronJob | `keda.enabled is supported only for Deployment and StatefulSet` |
| VPA on Job or CronJob | `verticalPodAutoscaler.enabled is supported only for Deployment and StatefulSet` |
| VPA active with HPA or KEDA | `verticalPodAutoscaler.updateMode must be Off when autoscaling or keda is enabled` |
| PodMonitor with ServiceMonitor | `podMonitor.enabled and serviceMonitor.enabled cannot both be true` |

## Testing

- helm-unittest: one suite per new template, one test per validation rule, and tests for `tmpDir` skipping, companion labels, hook ServiceAccount defaulting, and `servicePort` resolution.
- Examples: `values-gateway.yaml`, `values-worker-keda.yaml`, `values-migration-job.yaml`, `values-persistence.yaml`. CI lints, renders, and validates them with kubeconform against Kubernetes 1.25.0 and 1.33.0, using the CRDs-catalog schemas already configured.
- kind: a namespace labeled `pod-security.kubernetes.io/enforce=restricted` installs the default values, `values-migration-job.yaml` (hook Job completes), and `values-persistence.yaml` (a file written to `/data` survives a pod restart). The default install passes `helm test` with a read-only root filesystem.
- Render diff: the existing 7 examples and the default values, rendered before and after, differ only by the hardening defaults and `helm.sh/chart`.

## Risks

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Apps that write outside `/tmp` crash with a read-only root | Medium | High | CHANGELOG upgrade note; `securityContext.readOnlyRootFilesystem: false` restores the old behavior |
| Apps that read `<SVC>_SERVICE_HOST` env vars break | Low | Medium | CHANGELOG note; `enableServiceLinks: true` restores it |
| `allowDNS` selector does not match a cluster's DNS pods | Medium | Medium | `networkPolicy.allowDNS.to` is configurable; README names the default selector |
| Schema guards block a legitimate privileged sidecar | Low | Medium | Documented as intentional; such workloads need a different chart |

## Open questions

- None.
