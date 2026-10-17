# application-chart

`application-chart` is a generic Helm chart for Kubernetes application workloads. It is designed as a reusable base chart for APIs, backend services, workers, internal services, StatefulSets, Jobs, and CronJobs.

The design principle is:

> Flexible by values, simple by templates.

## Features

- Generic naming with `nameOverride` and `fullnameOverride`
- Standard Kubernetes labels
- Deployment, StatefulSet, Job, and CronJob workload modes
- Service, Ingress, HPA, PDB, NetworkPolicy, ServiceMonitor, ConfigMap, Secret, ExternalSecret, ServiceAccount, and RBAC
- Secure-by-default pod and container security context
- GitOps-friendly deterministic manifests
- `values.schema.json` validation: unknown keys and wrong value shapes fail at render time
- Example values files for common production patterns

## Chart Structure

```text
application-chart/
  Chart.yaml
  values.yaml
  values.schema.json
  README.md
  CHANGELOG.md
  examples/
  templates/
    _helpers.tpl
    deployment.yaml
    service.yaml
    service-headless.yaml   # StatefulSet governing Service
    ingress.yaml
    serviceaccount.yaml
    rbac.yaml
    configmap.yaml
    secret.yaml
    externalsecret.yaml
    hpa.yaml
    statefulset.yaml
    pdb.yaml
    networkpolicy.yaml
    servicemonitor.yaml
    job.yaml
    cronjob.yaml
    tests/
      test-connection.yaml  # `helm test` hook
  tests/                    # helm-unittest suites (not packaged)
```

## Installation

From GHCR (OCI):

```bash
helm upgrade --install user-api oci://ghcr.io/faridlamaul/charts/application-chart \
  --version 0.3.0 \
  --namespace applications \
  --create-namespace \
  -f values-user-api.yaml
```

From the Helm repository:

```bash
helm repo add application-chart https://faridlamaul.github.io/application-chart
helm upgrade --install user-api application-chart/application-chart \
  --version 0.3.0 --namespace applications --create-namespace -f values-user-api.yaml
```

With no values file, the chart deploys `nginxinc/nginx-unprivileged` on port 8080 as a non-root user, which is useful to check a cluster before deploying a real image.

## Upgrade

Read [CHANGELOG.md](CHANGELOG.md) before upgrading across minor versions; 0.3.0 has upgrade steps.

```bash
helm diff upgrade user-api oci://ghcr.io/faridlamaul/charts/application-chart --version 0.3.0 \
  --namespace applications \
  -f values-user-api.yaml

helm upgrade --install user-api oci://ghcr.io/faridlamaul/charts/application-chart --version 0.3.0 \
  --namespace applications \
  -f values-user-api.yaml
```

## Uninstall

```bash
helm uninstall user-api --namespace applications
```

## Basic API Deployment

```yaml
nameOverride: user-api
replicaCount: 3

image:
  repository: ghcr.io/example/user-api
  tag: "1.4.2"

readinessProbe:
  enabled: true
  httpGet:
    path: /readyz
    port: http

livenessProbe:
  enabled: true
  httpGet:
    path: /healthz
    port: http

service:
  enabled: true
  ports:
    - name: http
      port: 80
      targetPort: http
```

## Worker Deployment

Workers usually do not need Services or Ingress.

```yaml
nameOverride: notification-worker

service:
  enabled: false

containerPorts: []

command:
  - /app/worker
args:
  - --queue
  - notifications
```

## CronJob Example

```yaml
workload:
  type: CronJob

service:
  enabled: false

cronjob:
  schedule: "15 * * * *"
  concurrencyPolicy: Forbid
  command:
    - /app/export-reports
```

CronJob and Job containers do not get `livenessProbe`, `readinessProbe`, or `startupProbe`, and expose no ports.

## Job Example

A Job's pod template is immutable, so `workload.type: Job` renders the Job as a Helm `post-install,post-upgrade` hook. Every install and upgrade replaces the previous Job and runs it again, and `helm install`/`upgrade` waits for it to finish: raise `--timeout` for long jobs. Because it is a hook, `helm uninstall` does not delete it; `job.ttlSecondsAfterFinished` (default 300) cleans it up.

```yaml
workload:
  type: Job

service:
  enabled: false

job:
  command:
    - /app/migrate
  backoffLimit: 2
```

## StatefulSet Example

Use `StatefulSet` for workloads that need stable pod identity or stable per-pod storage. This chart can run simple stateful workloads, but production databases should normally use a managed database service or a database-specific operator.

A StatefulSet needs a headless governing Service for stable per-pod DNS (`<pod>.<service>`). When the main Service is not headless, the chart renders `<fullname>-headless` (`clusterIP: None`, `publishNotReadyAddresses: true`) and uses it as `spec.serviceName`. Set `service.headless: true` to make the main Service the governing one, as below, or `statefulSet.serviceName` to use a Service managed elsewhere.

```yaml
workload:
  type: StatefulSet

replicaCount: 3

service:
  enabled: true
  headless: true
  ports:
    - name: redis
      port: 6379
      targetPort: redis

statefulSet:
  podManagementPolicy: OrderedReady
  persistentVolumeClaimRetentionPolicy:
    whenDeleted: Retain
    whenScaled: Retain
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 10Gi

volumeMounts:
  - name: data
    mountPath: /data
```

## Ingress Example

```yaml
ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  hosts:
    - host: api.example.com
      paths:
        - path: /
          pathType: Prefix
          servicePort: http
  tls:
    - secretName: api-example-com-tls
      hosts:
        - api.example.com
```

## HPA Example

When HPA is enabled, the Deployment does not render `spec.replicas`. The HPA controls replica count. HPA is supported for `workload.type: Deployment` only; enabling it for another workload type fails the render.

```yaml
autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80
```

## ExternalSecret Example

Prefer External Secrets Operator, Sealed Secrets, or another secret manager integration for production secrets. Do not commit real secrets to `values.yaml`.

The default `externalSecret.apiVersion` is `external-secrets.io/v1`; ESO stopped serving `v1beta1` in v0.17.0. The target Secret defaults to the same name as `secret.name`, so enabling `secret` and `externalSecret` together fails unless their names differ.

```yaml
externalSecret:
  enabled: true
  refreshInterval: 30m
  secretStoreRef:
    name: production-secrets
    kind: ClusterSecretStore
  target:
    name: payment-api-secret
    creationPolicy: Owner
  data:
    - secretKey: DATABASE_URL
      remoteRef:
        key: payment-api/database-url
```

## Security Recommendations

- Pin image tags and avoid `latest`
- Use private registry pull secrets where needed
- Keep `serviceAccount.automount: false` unless the pod must call the Kubernetes API; the value applies to the ServiceAccount and to the pod
- Enable RBAC only with least-privilege `Role` rules, and set `serviceAccount.automount: true` so the pod gets a token to use them
- Prefer ExternalSecret over chart-rendered Secret objects
- Review `readOnlyRootFilesystem` per application because some runtimes need writable temp directories
- Use NetworkPolicy in clusters with a policy-enforcing CNI
- Run containers as non-root where the image supports it

## Production Readiness Checklist

- [ ] Image tag is pinned and not `latest`
- [ ] Resource requests and limits are configured
- [ ] Readiness probe is enabled
- [ ] Liveness probe is enabled where appropriate
- [ ] Startup probe is configured for slow-starting apps
- [ ] HPA is enabled for stateless services
- [ ] PDB is enabled for HA workloads
- [ ] Multiple replicas are configured
- [ ] Pod anti-affinity or topology spread constraints are configured
- [ ] Secrets are managed using External Secrets or sealed secrets
- [ ] ServiceAccount has least privilege
- [ ] NetworkPolicy is configured where supported
- [ ] SecurityContext is reviewed
- [ ] Metrics scraping is configured
- [ ] Logs are emitted to stdout/stderr
- [ ] Ingress TLS is enabled for public endpoints

## GitOps Usage

Argo CD example:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: user-api
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/example/platform-charts.git
    targetRevision: main
    path: helm-chart/application-chart
    helm:
      valueFiles:
        - examples/values-api.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: applications
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

Argo CD maps Helm hooks to its own: a `workload.type: Job` release runs as a PostSync hook on every sync.

Flux example:

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: user-api
  namespace: applications
spec:
  interval: 5m
  chart:
    spec:
      chart: ./helm-chart/application-chart
      sourceRef:
        kind: GitRepository
        name: platform-charts
        namespace: flux-system
  valuesFrom:
    - kind: ConfigMap
      name: user-api-values
```

## Validation Commands

```bash
helm lint . --strict
for f in examples/*.yaml; do helm lint . --strict -f "$f"; done
helm template app . -f examples/values-api.yaml
docker run --rm -v "$PWD:/apps" helmunittest/helm-unittest:4.3.0-1.2.1 .   # unit tests in tests/
```

## CI and Publishing

- **`ci.yaml`** (pull requests, and before every publish): `helm lint --strict` and rendering of the defaults and every example with Helm 3 and Helm 4; kubeconform against Kubernetes 1.25 and 1.33 (including the ExternalSecret and ServiceMonitor CRDs); the helm-unittest suites; and a kind cluster that installs the defaults (plus `helm test`), a StatefulSet (per-pod DNS), the Redis example, and a Job that is upgraded with a changed pod template.
- **`publish.yaml`** (every push to `main`): runs CI, then publishes only when the `version` in `Chart.yaml` has no `application-chart-<version>` tag yet. It pushes the chart to `oci://ghcr.io/faridlamaul/charts`, adds it to the GitHub Pages repository, and creates the tag with a GitHub Release. Bump `version` in `Chart.yaml` and add a CHANGELOG entry to release.

## Common Troubleshooting

| Symptom | Likely Cause | Action |
| --- | --- | --- |
| `values don't meet the specifications` | Invalid value rejected by `values.schema.json` | Fix the value shape before rendering |
| Ingress is not rendered | `ingress.enabled`, `service.enabled`, or `workload.type` is not compatible | Use `workload.type: Deployment` or `StatefulSet` and enable Service |
| HPA rendered but pods do not scale | Metrics Server or Prometheus adapter is missing | Check HPA events with `kubectl describe hpa` |
| PDB render fails | Both `minAvailable` and `maxUnavailable` are set | Set only one field; with neither, `minAvailable: 1` is used |
| `additional properties '…' not allowed` | Unknown or misspelled key in values | Fix the key; the schema rejects keys the chart does not read |
| `autoscaling.enabled is supported only for workload.type Deployment` | HPA enabled for a StatefulSet, Job, or CronJob | Disable autoscaling or switch to a Deployment |
| Pod cannot start as non-root | Image requires root user | Use a non-root image, or set `podSecurityContext.runAsUser` to the image's unprivileged user |
| `helm test` times out | A NetworkPolicy blocks the test pod | Set `tests.enabled: false` or allow ingress from pods labeled `app.kubernetes.io/component: test` |
| ServiceMonitor is ignored | Prometheus Operator selectors do not match labels | Add the required release/team labels under `serviceMonitor.labels` |

## Design Decisions

- One release manages one main workload type. This avoids making Deployment, StatefulSet, Job, and CronJob logic compete in the same release.
- Templates use Kubernetes-native value shapes where possible, for example `env`, `envFrom`, probes, volumes, and security contexts.
- Service, Ingress, PDB, ServiceMonitor, and tests support Deployment and StatefulSet workloads. HPA is Deployment-only and fails the render for other workload types.
- Secrets are supported for development and simple internal use, but ExternalSecret is the recommended production path.
- Kong, Istio, VPA, and cloud-provider-specific resources are intentionally excluded from the base chart. Add them as overlays or separate platform charts.

## Limitations

- This chart does not install CRDs for External Secrets Operator or Prometheus Operator.
- It does not create ClusterRoles by design. Use a separate platform chart for cluster-scoped access.
- It does not support multiple Deployments in one release. Prefer one Helm release per microservice component.
- It does not package environment-specific domains or company-specific annotations.
- It is not a production database operator. Use database-specific charts/operators for PostgreSQL, MySQL, Redis, MongoDB, or similar systems when you need replication, backups, restore, failover, and major-version upgrade workflows.

## Migration Guide From a Legacy Multi-Deployment Chart

1. Create one values file per workload component instead of using `deployments: []`.
2. Map `deployments[].replicasCount` to `replicaCount`.
3. Map global `image.repository` and `image.tag` to the new `image` block.
4. Convert map-style `env` into Kubernetes EnvVar list syntax.
5. Move service settings from `deployments[].service` to the top-level `service` block.
6. Move ingress rules to `ingress.hosts[].paths[]`; remove hardcoded service names.
7. Replace chart-rendered secret values with ExternalSecret where possible.
8. Replace Kong-specific plugin templates with ingress-controller-specific overlays.
9. Use `workload.type: StatefulSet` for stable identity or persistent per-pod storage.
10. Use `workload.type: Job` or `workload.type: CronJob` for batch workloads.
11. Run `helm template` and compare the generated Service selectors, container ports, probes, and environment variables before rollout.

## Minimum Kubernetes Version

The chart targets Kubernetes `>=1.25` and uses modern APIs:

- `apps/v1` Deployment
- `apps/v1` StatefulSet
- `batch/v1` Job and CronJob
- `autoscaling/v2` HPA
- `policy/v1` PDB
- `networking.k8s.io/v1` Ingress and NetworkPolicy
