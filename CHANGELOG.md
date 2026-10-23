# Changelog

## 0.4.0

### Upgrade notes

Read these before upgrading a 0.3.x release.

- **The chart is renamed from `application-chart` to `shipform`.** It is published as `oci://ghcr.io/faridlamaul/charts/shipform` and in the Helm repository at `https://faridlamaul.github.io/shipform`. Point `helm upgrade` and GitOps sources at the new name.
- **The chart name feeds resource names and the `app.kubernetes.io/name` selector label.** Selectors are immutable, so an existing release must keep the old name. Add this to its values before upgrading:

  ```yaml
  nameOverride: application-chart
  ```

  With it, resource names and selectors stay the same. Only the `helm.sh/chart` label and the headless Service label `application-chart/governing-service` (now `shipform/governing-service`) change; both are mutable. Releases that already set `nameOverride` need no change; `fullnameOverride` alone does not keep the selector.
- **Containers run with a read-only root filesystem.** `securityContext.readOnlyRootFilesystem` now defaults to `true`, and an `emptyDir` is mounted at `/tmp`. Applications that write elsewhere fail. Mount a volume at that path, or set `securityContext.readOnlyRootFilesystem: false` to restore the old behavior. Setting `tmpDir.enabled: false` also drops the `/tmp` mount.
- **The `/tmp` volume is named `tmp` and is reserved.** A user volume named `tmp` fails the render while the chart adds its own `/tmp` volume. That holds while `tmpDir.enabled` is `true` and no user mount uses `/tmp`. Rename the user volume, or set `tmpDir.enabled: false` to remove the chart volume.
- **Pods no longer receive Service environment variables.** `enableServiceLinks` now defaults to `false`. Use DNS names instead, or set `enableServiceLinks: true` to restore the old behavior.
- **The schema rejects privileged containers and `hostPath` volumes.** `securityContext.privileged: true` and any `hostPath` volume now fail the render. These guards have no opt-out.
- **The schema allows only `NET_BIND_SERVICE` in `securityContext.capabilities.add`.** Any other added capability fails the render. This guard has no opt-out.
- **NetworkPolicies that include Egress get a DNS rule.** `networkPolicy.allowDNS` allows port 53 to CoreDNS in `kube-system`. Set `networkPolicy.allowDNS.enabled: false` to remove it, or change `networkPolicy.allowDNS.to`.

### Changed

- Chart, repository, OCI path, Helm repository URL, release tags (`shipform-<version>`), and template helper names use `shipform`.

### Added

- `httpRoute` and `grpcRoute` render Gateway API routes.
- `persistence` adds a PersistentVolumeClaim named `<fullname>-data`. It is kept on uninstall while `persistence.keep` is `true`. Use `persistence.existingClaim` for an existing claim.
- `jobs` and `cronJobs` define companion Jobs and CronJobs. A Job with an empty `hook` runs as `post-install,post-upgrade`.
- `keda` renders a KEDA ScaledObject, and `verticalPodAutoscaler` renders a VerticalPodAutoscaler.
- `prometheusRule` and `podMonitor` render Prometheus Operator resources. `podMonitor` cannot be combined with `serviceMonitor`.
- `extraObjects` renders additional Kubernetes objects with the release.
- `tmpDir` configures the `/tmp` volume: `enabled`, `sizeLimit`, and `medium`.
- `networkPolicy.allowDNS` controls the DNS egress rule.
- CI installs the chart into a namespace that enforces the restricted Pod Security Standard.

## 0.3.0

### Upgrade notes

Read these before upgrading a 0.2.x release.

- **Values are validated strictly.** Unknown or misspelled keys now fail the render, and ConfigMap/Secret data, labels, and annotations must be strings. `job.enabled` and `cronjob.enabled` were never read and are removed: delete them from values files copied from the old defaults.
- **Pods no longer mount a ServiceAccount token unless `serviceAccount.automount: true`.** The value is now set on the pod as well as on the ServiceAccount, so it also applies when `serviceAccount.create: false` uses the namespace's `default` ServiceAccount. Set it to `true` for workloads that call the Kubernetes API.
- **StatefulSets without `service.headless: true` change their governing Service** to the new `<fullname>-headless` Service. `spec.serviceName` is immutable, so delete the StatefulSet without deleting its pods before upgrading, then upgrade:

  ```bash
  kubectl delete statefulset <fullname> --cascade=orphan
  helm upgrade <release> ...
  ```

  StatefulSets with `service.headless: true` or `statefulSet.serviceName` set are unaffected.
- **`workload.type: Job` runs as a Helm hook.** The upgrade removes the previous non-hook Job and runs the Job again as a `post-install,post-upgrade` hook; `helm upgrade` now waits for it to finish.
- **`externalSecret.apiVersion` defaults to `external-secrets.io/v1`.** Set it back to `external-secrets.io/v1beta1` only for External Secrets Operator older than v0.16.
- **`podDisruptionBudget.minAvailable` and `maxUnavailable` default to null**, with `minAvailable: 1` applied when both are unset. Setting only `maxUnavailable` now works.
- **The default image is `nginxinc/nginx-unprivileged:1.27`.** Releases that relied on the default `nginx:1.27` image never started, because it runs as root under `runAsNonRoot: true`.

### Fixed

- The default values install and pass `helm test`: the default image runs as non-root on port 8080.
- `deploymentStrategy.type: Recreate` no longer renders `rollingUpdate`, which the API rejects.
- StatefulSets get a headless governing Service, so per-pod DNS (`<pod>.<service>`) resolves.
- Job and CronJob containers no longer inherit `livenessProbe`, `readinessProbe`, and `startupProbe` from the service settings.
- A Job release can be upgraded after its pod template changes (Helm hook instead of an immutable Job).
- `ingress…servicePort` given with `--set` renders `port.number` instead of an invalid `port.name`.
- `terminationGracePeriodSeconds: 0`, `job.ttlSecondsAfterFinished: 0`, and `podDisruptionBudget.minAvailable: 0` are rendered instead of dropped.
- Labels from `labels`, `service.labels`, and the other `*.labels` values replace standard labels instead of producing duplicate keys, and cannot change the selector labels.
- Enabling `secret` and `externalSecret` with the same Secret name fails instead of letting two controllers fight over one Secret.
- `autoscaling.enabled` with a non-Deployment workload fails instead of being ignored.
- The `helm test` pod uses its own labels, so it no longer joins the application's Service, NetworkPolicy, and PodDisruptionBudget, and it runs with a restricted security context and resource limits.
- The ServiceMonitor skips the headless governing Service, so StatefulSet pods are scraped once.
- `examples/values-statefulset.yaml` runs Redis as its non-root user; `examples/values-secure-production.yaml` lets Prometheus scrape, allows database egress, mounts a writable `/tmp`, and disables `helm test`, which its NetworkPolicy would block.

### Added

- `component` and `partOf` values for the `app.kubernetes.io/component` and `app.kubernetes.io/part-of` labels.
- CI in this repository (`ci.yaml`): lint and render with Helm 3 and 4, kubeconform against Kubernetes 1.25 and 1.33, helm-unittest suites, and installs on kind. It replaces the workflows that called reusable workflows no longer present in `faridlamaul/ci-template`.
- `publish.yaml`: publishes new chart versions to GHCR (OCI) and the GitHub Pages repository, with a tag and GitHub Release.

## 0.2.0

- StatefulSet workload type, GitHub Pages and GHCR publishing.
