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
- `values.schema.json` validation for high-risk values
- Example values files for common production patterns

## Chart Structure

```text
application-chart/
  Chart.yaml
  values.yaml
  values.schema.json
  README.md
  examples/
  templates/
    _helpers.tpl
    deployment.yaml
    service.yaml
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
      test-connection.yaml
```

## Installation

```bash
helm upgrade --install user-api ./helm-chart/application-chart \
  --namespace applications \
  --create-namespace \
  -f ./helm-chart/application-chart/examples/values-api.yaml
```

## Upgrade

```bash
helm diff upgrade user-api ./helm-chart/application-chart \
  --namespace applications \
  -f values-user-api.yaml

helm upgrade --install user-api ./helm-chart/application-chart \
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

## StatefulSet Example

Use `StatefulSet` for workloads that need stable pod identity or stable per-pod storage. This chart can run simple stateful workloads, but production databases should normally use a managed database service or a database-specific operator.

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

When HPA is enabled, the Deployment does not render `spec.replicas`. The HPA controls replica count.

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
- Keep `serviceAccount.automount: false` unless the pod must call the Kubernetes API
- Enable RBAC only with least-privilege `Role` rules
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
helm lint helm-chart/application-chart
helm template test helm-chart/application-chart
helm template api helm-chart/application-chart -f helm-chart/application-chart/examples/values-api.yaml
helm template worker helm-chart/application-chart -f helm-chart/application-chart/examples/values-worker.yaml
helm template cronjob helm-chart/application-chart -f helm-chart/application-chart/examples/values-cronjob.yaml
helm template statefulset helm-chart/application-chart -f helm-chart/application-chart/examples/values-statefulset.yaml
helm template public helm-chart/application-chart -f helm-chart/application-chart/examples/values-public-ingress.yaml
helm template secure helm-chart/application-chart -f helm-chart/application-chart/examples/values-secure-production.yaml
```

## CI Usage

This chart repository consumes reusable GitHub Actions workflows from `faridlamaul/ci-template` instead of duplicating pipeline logic per repository.

Lint workflow:

```yaml
name: Helm Lint

jobs:
  helm-lint:
    uses: faridlamaul/ci-template/.github/workflows/helm-lint.yaml@main
    with:
      chart_dir: "."
      release_name: "application-chart"
      render_value_files: "examples/values-api.yaml examples/values-worker.yaml examples/values-cronjob.yaml examples/values-statefulset.yaml examples/values-internal-service.yaml examples/values-public-ingress.yaml examples/values-secure-production.yaml"
```

GitHub Pages publishing workflow:


```yaml
name: Publish Helm Chart

jobs:
  publish:
    uses: faridlamaul/ci-template/.github/workflows/publish-gh-pages.yaml@main
    with:
      chart_dir: "."
      helm_repo_url: "https://faridlamaul.github.io/application-chart"
      publish_branch: "gh-pages"
```

The local workflow files live under `.github/workflows/` and call the shared reusable workflows from `faridlamaul/ci-template`.

## Common Troubleshooting

| Symptom | Likely Cause | Action |
| --- | --- | --- |
| `values don't meet the specifications` | Invalid value rejected by `values.schema.json` | Fix the value shape before rendering |
| Ingress is not rendered | `ingress.enabled`, `service.enabled`, or `workload.type` is not compatible | Use `workload.type: Deployment` or `StatefulSet` and enable Service |
| HPA rendered but pods do not scale | Metrics Server or Prometheus adapter is missing | Check HPA events with `kubectl describe hpa` |
| PDB render fails | Both `minAvailable` and `maxUnavailable` are set | Set only one field |
| Pod cannot start as non-root | Image requires root user | Fix the image or override security context explicitly |
| ServiceMonitor is ignored | Prometheus Operator selectors do not match labels | Add the required release/team labels under `serviceMonitor.labels` |

## Design Decisions

- One release manages one main workload type. This avoids making Deployment, StatefulSet, Job, and CronJob logic compete in the same release.
- Templates use Kubernetes-native value shapes where possible, for example `env`, `envFrom`, probes, volumes, and security contexts.
- Service, Ingress, PDB, ServiceMonitor, and tests support Deployment and StatefulSet workloads. HPA remains Deployment-only.
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
