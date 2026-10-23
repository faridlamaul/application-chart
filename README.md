<p align="center">
  <strong>shipform: one Helm chart for APIs, workers, StatefulSets, Jobs and CronJobs, secure by default.</strong><br>
  Configure everything through values; the schema rejects unknown keys and unsafe settings.
</p>

<p align="center">
  <a href="https://github.com/faridlamaul/shipform/actions/workflows/ci.yaml"><img alt="CI" src="https://github.com/faridlamaul/shipform/actions/workflows/ci.yaml/badge.svg"></a>
  <a href="https://github.com/faridlamaul/shipform/actions/workflows/publish.yaml"><img alt="Publish" src="https://github.com/faridlamaul/shipform/actions/workflows/publish.yaml/badge.svg"></a>
  <a href="https://github.com/faridlamaul/shipform/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/faridlamaul/shipform?sort=semver"></a>
  <a href="https://kubernetes.io"><img alt="Kubernetes 1.25+" src="https://img.shields.io/badge/Kubernetes-1.25+-326CE5?style=flat&logo=kubernetes"></a>
  <a href="https://helm.sh"><img alt="Helm 3 and 4" src="https://img.shields.io/badge/Helm-3%20%7C%204-0F1689?style=flat&logo=helm"></a>
</p>

shipform deploys one application workload per Helm release: a Deployment, StatefulSet, Job or CronJob, plus the Service, routing, scaling, secrets and monitoring resources it needs.

- **Secure defaults:** non-root, read-only root filesystem, no added capabilities, no Service links, no ServiceAccount token. The default install passes the restricted Pod Security Standard.
- **Schema-checked values:** `values.schema.json` rejects unknown keys, wrong shapes, privileged containers and `hostPath` volumes at render time.
- **One chart for every component:** API, worker, internal service, StatefulSet, batch Job, CronJob, plus companion migration Jobs and cleanup CronJobs.
- **GitOps-friendly:** deterministic manifests, no random names, works with Argo CD and Flux.

<details>
<summary><strong>Contents</strong></summary>

- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Features](#features)
- [Security defaults](#security-defaults)
- [Workloads and hooks](#workloads-and-hooks)
- [Persistence](#persistence)
- [Routing](#routing)
- [Upgrading](#upgrading)
- [Troubleshooting](#troubleshooting)
- [Scope](#scope)
- [Development](#development)
- [Ownership](#ownership)

</details>

## Requirements

- Kubernetes 1.25 or later (`kubeVersion: ">=1.25.0-0"` in `Chart.yaml`).
- Helm 3 or Helm 4. CI tests Helm v3.22.1 and v4.3.1.
- Optional operators, only for the blocks that use them: Gateway API CRDs (`httpRoute`, `grpcRoute`), External Secrets Operator (`externalSecret`), Prometheus Operator (`serviceMonitor`, `podMonitor`, `prometheusRule`), KEDA (`keda`) and the VPA CRDs (`verticalPodAutoscaler`). The chart installs no CRDs.

## Installation

From GHCR (OCI):

```bash
helm upgrade --install user-api oci://ghcr.io/faridlamaul/charts/shipform \
  --version 0.4.0 \
  --namespace applications --create-namespace \
  -f values-user-api.yaml
```

From the Helm repository:

```bash
helm repo add shipform https://faridlamaul.github.io/shipform
helm repo update shipform
helm upgrade --install user-api shipform/shipform \
  --version 0.4.0 \
  --namespace applications --create-namespace \
  -f values-user-api.yaml
```

With no values file, the chart deploys `nginxinc/nginx-unprivileged:1.27` on port 8080 as uid 101. Use it to check a cluster before you deploy a real image.

To remove a release:

```bash
helm uninstall user-api --namespace applications
```

`helm uninstall` keeps the `persistence` claim while `persistence.keep` is `true`. The main Job hook stays after uninstall until `ttlSecondsAfterFinished` (default 300) removes it. The default `hookDeletePolicy` deletes companion Jobs when they succeed.

## Quick start

Save this as `values-user-api.yaml`. It runs three replicas of an HTTP API on container port 8080 behind a ClusterIP Service on port 80.

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
```

Render it before you install, so the schema checks run locally:

```bash
helm template user-api oci://ghcr.io/faridlamaul/charts/shipform --version 0.4.0 -f values-user-api.yaml
```

The default `containerPorts` (`http`, 8080) and `service.ports` (`http`, 80 to `http`) already match this API. For more complete setups, start from a file in [`examples/`](examples/).

## Features

Each row is a top-level block in [`values.yaml`](values.yaml). The example column links to a working values file; `—` means there is no example, so the link goes to `values.yaml` and names the key.

| Block | What it renders | Example |
|---|---|---|
| `workload.type: Deployment` | Deployment for an HTTP API | [values-api.yaml](examples/values-api.yaml) |
| `workload.type: Deployment`, no Service | Queue worker | [values-worker.yaml](examples/values-worker.yaml) |
| `workload.type: StatefulSet`, `statefulSet` | StatefulSet with a headless governing Service and volume claim templates | [values-statefulset.yaml](examples/values-statefulset.yaml) |
| `workload.type: Job`, `job` | Job run as a `post-install,post-upgrade` hook | — ([`job`](values.yaml)) |
| `workload.type: CronJob`, `cronjob` | CronJob | [values-cronjob.yaml](examples/values-cronjob.yaml) |
| `jobs` | Companion Jobs, always Helm hooks, for example a migration | [values-migration-job.yaml](examples/values-migration-job.yaml) |
| `cronJobs` | Companion CronJobs next to the main workload | — ([`cronJobs`](values.yaml)) |
| `service` | ClusterIP, NodePort, LoadBalancer or headless Service | [values-internal-service.yaml](examples/values-internal-service.yaml) |
| `ingress` | Ingress with TLS | [values-public-ingress.yaml](examples/values-public-ingress.yaml) |
| `httpRoute` | Gateway API HTTPRoute | [values-gateway.yaml](examples/values-gateway.yaml) |
| `grpcRoute` | Gateway API GRPCRoute | — ([`grpcRoute`](values.yaml)) |
| `autoscaling` | HorizontalPodAutoscaler (Deployment only) | [values-api.yaml](examples/values-api.yaml) |
| `keda` | KEDA ScaledObject, including scale to zero | [values-worker-keda.yaml](examples/values-worker-keda.yaml) |
| `verticalPodAutoscaler` | VerticalPodAutoscaler | — ([`verticalPodAutoscaler`](values.yaml)) |
| `podDisruptionBudget` | PodDisruptionBudget | [values-api.yaml](examples/values-api.yaml) |
| `persistence` | PersistentVolumeClaim `<fullname>-data` mounted in the main container | [values-persistence.yaml](examples/values-persistence.yaml) |
| `tmpDir` | `emptyDir` mounted at `/tmp` | — ([`tmpDir`](values.yaml)) |
| `externalSecret` | ExternalSecret (`external-secrets.io/v1`) | [values-secure-production.yaml](examples/values-secure-production.yaml) |
| `configMap` | ConfigMap `<fullname>-config` | — ([`configMap`](values.yaml)) |
| `secret` | Secret `<fullname>-secret`, for development use | — ([`secret`](values.yaml)) |
| `serviceAccount`, `rbac` | ServiceAccount, namespaced Role and RoleBinding | — ([`serviceAccount`](values.yaml)) |
| `networkPolicy` | NetworkPolicy with an optional DNS egress rule | [values-internal-service.yaml](examples/values-internal-service.yaml), [values-secure-production.yaml](examples/values-secure-production.yaml) |
| `serviceMonitor` | Prometheus Operator ServiceMonitor | [values-secure-production.yaml](examples/values-secure-production.yaml) |
| `podMonitor` | Prometheus Operator PodMonitor; cannot be combined with `serviceMonitor` | — ([`podMonitor`](values.yaml)) |
| `prometheusRule` | Prometheus Operator PrometheusRule | — ([`prometheusRule`](values.yaml)) |
| `extraObjects` | Any extra manifest, rendered through `tpl` | — ([`extraObjects`](values.yaml)) |
| `tests` | `helm test` connection check | — ([`tests`](values.yaml)) |

## Security defaults

The default install runs in a namespace that enforces the restricted Pod Security Standard; CI checks this on kind. Each default below can be relaxed per release, except the schema guards.

| Default | Values | How to relax |
|---|---|---|
| Run as non-root with the `RuntimeDefault` seccomp profile | `podSecurityContext.runAsNonRoot: true` | For an image that starts as root, set `podSecurityContext.runAsUser` to its unprivileged user (see [values-statefulset.yaml](examples/values-statefulset.yaml)). Setting `runAsNonRoot: false` fails the restricted standard. |
| No privilege escalation, all capabilities dropped | `securityContext.allowPrivilegeEscalation: false`, `securityContext.capabilities.drop: [ALL]` | Add `NET_BIND_SERVICE` under `securityContext.capabilities.add` to bind ports below 1024. No other capability is allowed. |
| Read-only root filesystem | `securityContext.readOnlyRootFilesystem: true` | Mount a volume at each path the application writes to, or set `securityContext.readOnlyRootFilesystem: false`. |
| Writable `/tmp` | `tmpDir.enabled: true`, `sizeLimit: 64Mi` | Set `tmpDir.enabled: false` to remove it. Set `tmpDir.medium: Memory` for a tmpfs that counts against the memory limit. The chart skips its volume when `volumeMounts` already mounts `/tmp`. |
| No Service environment variables | `enableServiceLinks: false` | Set `enableServiceLinks: true`. Prefer DNS names. |
| No ServiceAccount token in the pod | `serviceAccount.automount: false` | Set `serviceAccount.automount: true` when the pod calls the Kubernetes API, for example with `rbac.rules`. It applies to the ServiceAccount and the pod. |
| DNS egress when a NetworkPolicy restricts Egress | `networkPolicy.allowDNS.enabled: true` | The rule allows port 53 (UDP and TCP) to CoreDNS in `kube-system`, and renders only when `networkPolicy.policyTypes` contains `Egress`. Set `allowDNS.enabled: false` to remove it, or change `allowDNS.to`. |

Guards with no opt-out. The schema rejects these values in the main container, init containers, extra containers and companions:

- `securityContext.privileged: true`.
- Any `hostPath` volume.
- Any entry in `securityContext.capabilities.add` other than `NET_BIND_SERVICE`.

The volume name `tmp` is reserved while the chart adds its own `/tmp` volume. A user volume named `tmp` then fails the render. Rename it, set `tmpDir.enabled: false`, or mount your own volume at `/tmp`, as [values-secure-production.yaml](examples/values-secure-production.yaml) does.

Other recommendations: pin image tags, prefer `externalSecret` over `secret` for real credentials, keep `rbac.rules` least-privilege, and enable `networkPolicy` where the CNI enforces it.

## Workloads and hooks

One release runs one main workload, chosen by `workload.type`. Use one release per component.

`workload.type: Job` renders the Job as a `post-install,post-upgrade` Helm hook, because a Job's pod template is immutable. Every install and upgrade replaces the Job and runs it again, and Helm waits for it to finish, so raise `--timeout` for long jobs. Argo CD maps this hook to PostSync and runs it on every sync. Batch containers (Job, CronJob and companions) get no probes and no ports.

Companion `jobs` and `cronJobs` run next to the main workload. Each key names one resource, `<fullname>-<key>`. The name must fit in 63 characters for a Job and 52 for a CronJob; a longer name fails the render.

- **Every companion Job is a hook.** An empty `hook` means `post-install,post-upgrade`. Companion CronJobs are normal resources.
- **Pre-install hooks run first.** A Job whose `hook` includes `pre-install` runs before the chart's ConfigMap, Secret, ExternalSecret and ServiceAccount exist. Helm creates those normal resources only after pre-install hooks finish. On the first install, read credentials from a Secret that already exists.
- **ServiceAccount.** An explicit `serviceAccountName` on the entry wins. A `pre-install` hook uses the namespace `default` ServiceAccount while `serviceAccount.create` is `true`, because the chart's ServiceAccount does not exist yet. Every other companion uses the release ServiceAccount. When `serviceAccount.create` is `false`, that is `serviceAccount.name`, or `default` when the name is empty.
- **What a companion inherits.** It takes the root image, `imagePullSecrets`, `env`, `envFrom`, `volumes`, `volumeMounts`, pod and container security contexts, scheduling fields and `tmpDir`. It takes `command`, `args` and `resources` only from its own entry; empty means the image defaults and no resources. A companion skips each mount that has no volume in its pod, for example a StatefulSet claim template.
- **Selectors.** Companion pods carry `app.kubernetes.io/name: <name>-<key>`, so the main Service, PodDisruptionBudget and NetworkPolicy do not select them.

## Persistence

`persistence.enabled: true` creates a PersistentVolumeClaim named `<fullname>-data` and mounts it at `persistence.mountPath` (default `/data`). It works for Deployment, Job and CronJob workloads; a StatefulSet uses `statefulSet.volumeClaimTemplates` instead.

- **Kept on uninstall.** While `persistence.keep` is `true` (the default), the claim carries `helm.sh/resource-policy: keep`. Delete it by hand when you no longer need the data.
- **ReadWriteOnce needs one pod at a time.** With more than one replica, or with the default `RollingUpdate` strategy, a new pod can stay pending while the old pod holds the volume. Run one replica with `deploymentStrategy.type: Recreate`, as [values-persistence.yaml](examples/values-persistence.yaml) does, or use a `ReadWriteMany` storage class.
- **Existing claims.** Set `persistence.existingClaim` to mount a claim managed elsewhere; the chart then creates none.
- **Storage class.** `storageClassName: null` uses the cluster default; `""` requests no class.

## Routing

`ingress`, `httpRoute` and `grpcRoute` all point at the chart Service, so they need `service.enabled: true`.

Each Ingress path and each route rule names its backend with `servicePort`, either a `service.ports` name or number. When a route rule gives no `servicePort`, the backend falls back to the Service port named `http` for an HTTPRoute and `grpc` for a GRPCRoute. A `servicePort` that matches no `service.ports` entry fails the render.

## Upgrading

Read [CHANGELOG.md](CHANGELOG.md) before every minor upgrade; 0.3.0 and 0.4.0 have upgrade notes.

0.4.0 renames the chart from `application-chart` to `shipform`. The chart name feeds resource names and the immutable `app.kubernetes.io/name` selector label. Before you upgrade a 0.3.x release that does not set `nameOverride`, add this to its values:

```yaml
nameOverride: application-chart
```

Then point `helm upgrade` or your GitOps source at the new chart:

```bash
helm upgrade user-api oci://ghcr.io/faridlamaul/charts/shipform \
  --version 0.4.0 \
  --namespace applications \
  -f values-user-api.yaml
```

0.4.0 also turns on the read-only root filesystem, the `/tmp` volume, `enableServiceLinks: false` and the schema guards. The schema guards have no opt-out. The CHANGELOG lists how to restore the other behaviors.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `additional properties '…' not allowed` | Unknown or misspelled key | Fix the key; the schema rejects keys the chart does not read. |
| Schema error on `privileged`, `hostPath` or `capabilities.add` | A guard with no opt-out | Remove the setting. |
| `volumes: the name "tmp" is reserved …` | A user volume named `tmp` while the chart adds `/tmp` | Rename the volume or set `tmpDir.enabled: false`. |
| `Read-only file system` in the pod logs | The application writes outside `/tmp` | Mount a volume at that path, or set `securityContext.readOnlyRootFilesystem: false`. |
| Pod fails with a non-root error | The image starts as root | Set `podSecurityContext.runAsUser` to the image's unprivileged user. |
| `… servicePort "x" matches no service.ports entry` | A route rule names a missing port | Use a name or number from `service.ports`. |
| `autoscaling.enabled is supported only for workload.type Deployment` | HPA on another workload type | Disable `autoscaling`, or use `keda` for a StatefulSet. |
| New pod stays `Pending` after an upgrade with `persistence` | ReadWriteOnce volume held by the old pod | Use `deploymentStrategy.type: Recreate` and one replica. |
| Pre-install companion Job cannot read a chart Secret | The Secret does not exist yet on first install | Reference a Secret that exists before the release. |
| `helm test` times out | A NetworkPolicy blocks the test pod | Set `tests.enabled: false`, or allow pods labeled `app.kubernetes.io/component: test`. |

## Scope

- One main workload per release; no multi-Deployment releases.
- Namespaced RBAC only; the chart creates no ClusterRoles.
- No CRDs, no environment-specific domains, no vendor-specific annotations.
- Not a database operator. Use a managed service or a database-specific operator for replication, backup and failover.

## Development

Run the checks that CI runs, from the repository root.

Lint and render the defaults and every example:

```bash
helm lint . --strict
for f in examples/*.yaml; do
  helm lint . --strict -f "$f"
done
helm template app . -f examples/values-api.yaml
```

Run the helm-unittest suites in `tests/`:

```bash
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD:/apps" \
  helmunittest/helm-unittest:4.3.0-1.2.1@sha256:28ea86c3e0b07f501f0c2e9c08b9f41e240f4a4b571cb5106b36cf0f0607e989 .
```

Install on a local [kind](https://kind.sigs.k8s.io) cluster in a namespace that enforces the restricted Pod Security Standard, as the CI `install` job does:

```bash
kind create cluster --name shipform-dev
kubectl create namespace restricted
kubectl label namespace restricted pod-security.kubernetes.io/enforce=restricted
helm install web . -n restricted --wait --timeout 3m
helm test web -n restricted --logs
helm uninstall web -n restricted
```

CI (`.github/workflows/ci.yaml`) runs on every pull request. It lints and renders with Helm v3.22.1 and v4.3.1, then runs the unit tests. kubeconform validates the manifests against Kubernetes 1.25 and 1.33. A kind job then installs the defaults, a StatefulSet and the Redis example. It also checks a Job upgrade, the migration hook and the persistence example.

To release:

1. Bump `version` in `Chart.yaml` and add a `CHANGELOG.md` entry.
2. Merge to `main`.
3. `.github/workflows/publish.yaml` runs CI. If no `shipform-<version>` tag exists yet, it packages the chart and pushes it to `oci://ghcr.io/faridlamaul/charts`. It then adds the chart to the `gh-pages` Helm repository and creates the `shipform-<version>` tag with a GitHub Release.

The tag is created last, so a failed publish can be re-run. A push that does not change `version` publishes nothing.

## Ownership

Maintainer: af/faridlamaul · Repository: <https://github.com/faridlamaul/shipform> · Issues: <https://github.com/faridlamaul/shipform/issues>
