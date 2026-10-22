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

### Changed

- Chart, repository, OCI path, Helm repository URL, release tags (`shipform-<version>`), and template helper names use `shipform`.

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
