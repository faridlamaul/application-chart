# Implementation plan: shipform resource templates

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship shipform 0.4.0 with Gateway API routes, companion jobs, persistence, KEDA, VPA, PrometheusRule, PodMonitor, `extraObjects`, and restricted-by-default pods.

**Architecture:** Each feature is one values block, one template, schema entries, and one helm-unittest suite. Shared logic lives in split helper files; cross-field rules live in `shipform.validate`, rendered on every install by `templates/validate.yaml`.

**Tech stack:** Helm 3/4 templates, JSON Schema draft-07 (`values.schema.json`), helm-unittest 4.3.0-1.2.1, kubeconform v0.8.0, kind.

**Spec:** `docs/superpowers/specs/2026-10-23-shipform-resource-templates-design.md`

## Global constraints

- Branch `feat/resource-templates`, stacked on `refactor/rename-to-shipform`; chart version stays `0.4.0`.
- Every new block defaults to `enabled: false` or empty; only the hardening defaults change the default render.
- Every new schema object sets `additionalProperties: false`.
- Main selector labels stay `app.kubernetes.io/name` + `app.kubernetes.io/instance`.
- `kubeVersion: ">=1.25.0-0"`; the chart installs no CRDs.
- Validation messages start with the exact text in the spec's validation table.
- Commits are signed (`git commit -S`), Conventional Commits, and end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. No push until the user asks.

Commands used below:

```bash
UT='docker run --rm --user '"$(id -u):$(id -g)"' -e HOME=/tmp -v '"$PWD"':/apps helmunittest/helm-unittest:4.3.0-1.2.1@sha256:28ea86c3e0b07f501f0c2e9c08b9f41e240f4a4b571cb5106b36cf0f0607e989'
$UT .                                   # all suites
$UT -f 'tests/<suite>_test.yaml' .     # one suite
helm lint . --strict && for f in examples/*.yaml; do helm lint . --strict -f "$f"; done
```

## Review focus

1. A user who already mounts `/tmp` (as `examples/values-secure-production.yaml` does) must not get a duplicate mount. Test in Task 2.
2. A route `servicePort` given as a number (from `--set`, an int64) must resolve the same as a YAML int. Test in Task 3.
3. A companion Job must not join the main Service endpoints while running. Test in Task 5 asserts its pod `app.kubernetes.io/name` differs.
4. `replicas` must be absent from Deployment and StatefulSet when `keda.enabled`, or KEDA and Helm fight over it. Test in Task 6.
5. A `pre-install` hook with `serviceAccount.create: false` and a named ServiceAccount must keep that name, not fall back to `default`. Test in Task 5.

---

### Task 1: Split helpers and add the validation entry point

**Files:**
- Create: `templates/_names.tpl`, `templates/_labels.tpl`, `templates/_pod.tpl`, `templates/_validate.tpl`, `templates/validate.yaml`
- Delete: `templates/_helpers.tpl`

**Interfaces:**
- Produces: the existing `define` names unchanged; `shipform.validate` (takes root context, renders nothing, may `fail`); `templates/validate.yaml` containing only `{{- include "shipform.validate" . -}}`.

- [ ] **Step 1: Capture baseline renders**

```bash
B=$TMPDIR/shipform-baseline; mkdir -p $B
helm template app . > $B/default.yaml
for f in examples/*.yaml; do helm template app . -f "$f" > "$B/$(basename "$f")"; done
```

- [ ] **Step 2: Move defines** into the four files per the spec's Structure table. `_validate.tpl` defines an empty `shipform.validate`.
- [ ] **Step 3: Verify the render is byte-identical**

Run the Step 1 loop into `$TMPDIR/shipform-split` and `diff -r $B $TMPDIR/shipform-split`.
Expected: no output.

- [ ] **Step 4: Run `$UT .`.** Expected: 4 suites, 28 tests pass.
- [ ] **Step 5: Commit** `refactor(chart): split helpers by responsibility`

### Task 2: security hardening

**Files:**
- Modify: `values.yaml`, `values.schema.json`, `templates/_pod.tpl`, `templates/networkpolicy.yaml`
- Test: `tests/hardening_test.yaml`

**Interfaces:**
- Produces: `shipform.container` takes an extra dict key `mountPersistence` (bool, default false; used in Task 4) and always appends the `tmp` mount when `shipform.needsTmpDir` is true. `shipform.needsTmpDir` (root) returns `"true"` when `tmpDir.enabled` and no `volumeMounts[].mountPath` equals `/tmp`. `shipform.podSpec` takes extra keys `companion` (bool) and `serviceAccountName` (string override), and appends volume `{name: tmp, emptyDir: {sizeLimit, medium?}}` when `shipform.needsTmpDir`.
- Values: `securityContext.readOnlyRootFilesystem: true`; `tmpDir: {enabled: true, sizeLimit: 64Mi, medium: ""}`; `enableServiceLinks: false`; `networkPolicy.allowDNS: {enabled: true, to: [{namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: kube-system}}, podSelector: {matchLabels: {k8s-app: kube-dns}}}]}`.

- [ ] **Step 1: Write failing tests** in `tests/hardening_test.yaml` (templates `deployment.yaml`, `networkpolicy.yaml`):
  - `it: defaults to a read-only root with a /tmp emptyDir`: `equal spec.template.spec.containers[0].securityContext.readOnlyRootFilesystem true`; `contains spec.template.spec.volumes {name: tmp, emptyDir: {sizeLimit: 64Mi}}`; `contains ...containers[0].volumeMounts {name: tmp, mountPath: /tmp}`.
  - `it: skips the /tmp volume when the user mounts /tmp` (Review focus 1): set `volumes: [{name: scratch, emptyDir: {}}]`, `volumeMounts: [{name: scratch, mountPath: /tmp}]`; `notContains volumes {name: tmp, ...}`; `lengthEqual ...volumeMounts 1`.
  - `it: disables service links`: `equal spec.template.spec.enableServiceLinks false`.
  - `it: allows DNS egress when Egress is enforced`: set `networkPolicy.enabled: true`, `networkPolicy.policyTypes: [Ingress, Egress]`; `contains spec.egress` with the default `to` and ports `[{port: 53, protocol: UDP}, {port: 53, protocol: TCP}]`.
  - `it: adds no DNS rule for Ingress-only policies`: `notExists spec.egress`.
  - Schema: `rejects privileged containers` (`securityContext.privileged: true`), `rejects hostPath volumes`, `rejects added capabilities other than NET_BIND_SERVICE` (`capabilities.add: [SYS_ADMIN]`), `accepts NET_BIND_SERVICE`, `rejects privileged extraContainers`. Each uses `failedTemplate: {}` or `notFailedTemplate: {}`.
- [ ] **Step 2: Run `$UT -f 'tests/hardening_test.yaml' .`.** Expected: FAIL.
- [ ] **Step 3: Implement** the values, helpers, and schema. Add a schema `definitions.securityContext` (`privileged: {const: false}`, `capabilities.add.items: {enum: [NET_BIND_SERVICE]}`) and `definitions.volume` (`not: {required: [hostPath]}`); reference them from `securityContext`, `initContainers.items.properties.securityContext`, `extraContainers.items.properties.securityContext`, `volumes.items`.
- [ ] **Step 4: Run `$UT .`.** Expected: all pass. If an existing test asserts the old `securityContext`, update it to the new default.
- [ ] **Step 5: Install check on kind**

```bash
kind create cluster --name shipform-dev
kubectl create ns restricted && kubectl label ns restricted pod-security.kubernetes.io/enforce=restricted
helm install web . -n restricted --wait --timeout 3m && helm test web -n restricted --logs
```

Expected: install succeeds and `helm test` passes; nginx-unprivileged starts with a read-only root.

- [ ] **Step 6: Commit** `feat(chart)!: default to a read-only root filesystem and restricted pods`

### Task 3: Gateway API routes

**Files:**
- Create: `templates/httproute.yaml`, `templates/grpcroute.yaml`, `examples/values-gateway.yaml`
- Modify: `values.yaml`, `values.schema.json`, `templates/_pod.tpl` (add helper), `templates/_validate.tpl`
- Test: `tests/routes_test.yaml`

**Interfaces:**
- Produces: `shipform.servicePortNumber` taking `(dict "root" $ "port" <string|int>)`, returning the port number as a string, or `""` when no `service.ports` entry matches. Accepts int, int64, and float64 (from `--set`) by comparing `toString`.

- [ ] **Step 1: Write failing tests**:
  - `it: renders an HTTPRoute to the chart Service`: set `httpRoute.enabled: true`, `httpRoute.parentRefs: [{name: gw}]`, `httpRoute.hostnames: [app.example.com]`; `equal spec.rules[0].backendRefs [{name: RELEASE-NAME-shipform, port: 80}]` (use the suite's release name).
  - `it: resolves a numeric servicePort` (Review focus 2): `httpRoute.rules[0].servicePort: 80` → port `80`.
  - `it: renders a GRPCRoute`: `grpcRoute.enabled: true`, `service.ports: [{name: grpc, port: 9090, targetPort: grpc}]` → `backendRefs[0].port 9090`, `isKind GRPCRoute`, `isAPIVersion gateway.networking.k8s.io/v1`.
  - `it: fails without a Service`: `service.enabled: false` → `errorPattern: httpRoute.enabled requires service.enabled`.
  - `it: fails on an unknown servicePort`: `servicePort: admin` → `errorPattern: servicePort "admin" matches no service.ports entry`.
  - `it: rejects an empty parentRefs` (schema): `failedTemplate`.
- [ ] **Step 2: Run the suite.** Expected: FAIL.
- [ ] **Step 3: Implement** values per the spec, templates, schema (`parentRefs` `minItems: 1` via `if enabled const true then`), and the two route rules in `shipform.validate`.
- [ ] **Step 4: Add `examples/values-gateway.yaml`** (HTTPRoute with `parentRefs: [{name: public, namespace: gateway-system, sectionName: https}]`, one hostname, a 30s request timeout). Run `$UT .` and the lint loop. Expected: pass.
- [ ] **Step 5: Commit** `feat(chart): add Gateway API HTTPRoute and GRPCRoute`

### Task 4: persistence

**Files:**
- Create: `templates/pvc.yaml`, `examples/values-persistence.yaml`
- Modify: `values.yaml`, `values.schema.json`, `templates/_pod.tpl`, `templates/deployment.yaml`, `templates/job.yaml`, `templates/cronjob.yaml`, `templates/_validate.tpl`
- Test: `tests/persistence_test.yaml`

**Interfaces:**
- Consumes: `shipform.container` key `mountPersistence` (Task 2).
- Produces: `shipform.persistenceClaimName` (root) → `existingClaim` or `<fullname>-data`. `shipform.podSpec` adds volume `{name: persistence, persistentVolumeClaim: {claimName}}` when `persistence.enabled` and not `companion`. Main workload templates pass `mountPersistence: true`.

- [ ] **Step 1: Write failing tests**:
  - `it: creates a PVC with keep policy`: `persistence.enabled: true` → `isKind PersistentVolumeClaim`, `equal metadata.name RELEASE-NAME-shipform-data`, `equal metadata.annotations["helm.sh/resource-policy"] keep`, `equal spec.resources.requests.storage 1Gi`, `notExists spec.storageClassName`.
  - `it: renders an empty storageClassName when set to ""`: `exists spec.storageClassName` equal `""`.
  - `it: mounts the claim in the main container`: deployment `contains volumeMounts {name: persistence, mountPath: /data}`.
  - `it: uses an existing claim without creating one`: `existingClaim: shared` → pvc `hasDocuments 0`; deployment volume `claimName: shared`.
  - `it: fails for a StatefulSet`: `errorPattern: persistence is not supported for workload.type StatefulSet`.
- [ ] **Step 2: Run the suite.** Expected: FAIL.
- [ ] **Step 3: Implement.** `storageClassName` renders only when not `kindIs "invalid"`; `subPath` renders only when non-empty.
- [ ] **Step 4: Add `examples/values-persistence.yaml`** (`replicaCount: 1`, `deploymentStrategy.type: Recreate`, `persistence.enabled: true`, size 1Gi). Run `$UT .` and the lint loop. Expected: pass.
- [ ] **Step 5: Commit** `feat(chart): add a standalone PersistentVolumeClaim`

### Task 5: Companion jobs and cron jobs

**Files:**
- Create: `templates/companion-jobs.yaml`, `templates/companion-cronjobs.yaml`, `examples/values-migration-job.yaml`
- Modify: `values.yaml`, `values.schema.json`, `templates/_names.tpl`, `templates/_labels.tpl`, `templates/_pod.tpl`, `templates/_validate.tpl`
- Test: `tests/companions_test.yaml`

**Interfaces:**
- Consumes: `shipform.podSpec` keys `companion`, `serviceAccountName` (Task 2).
- Produces: `shipform.companionName` `(dict "root" $ "key" $k)` → `<fullname>-<key>` untruncated; `shipform.companionSelectorLabels` same args → `app.kubernetes.io/name: <name>-<key>`, `app.kubernetes.io/instance`, `app.kubernetes.io/component: <key>`; `shipform.companionServiceAccountName` `(dict "root" $ "job" $j)` per the spec's ServiceAccount rule. With `companion: true`, `shipform.podSpec` omits `initContainers` and `extraContainers`, and `shipform.container` drops probes.

- [ ] **Step 1: Write failing tests**:
  - `it: renders an enabled job with inherited image and env`: `jobs.migrate: {enabled: true, command: [migrate, up]}`, root `env: [{name: A, value: "1"}]` → `isKind Job`, `equal metadata.name RELEASE-NAME-shipform-migrate`, container image equals root image, `contains env {name: A, value: "1"}`, `notExists ...livenessProbe`.
  - `it: labels companion pods apart from the main workload` (Review focus 3): `equal spec.template.metadata.labels["app.kubernetes.io/name"] shipform-migrate`.
  - `it: adds hook annotations`: `hook: pre-install,pre-upgrade` → `helm.sh/hook`, `helm.sh/hook-weight: "0"`, `helm.sh/hook-delete-policy: before-hook-creation,hook-succeeded`.
  - `it: runs pre-install hooks as the default ServiceAccount`: → `serviceAccountName: default`.
  - `it: keeps a named ServiceAccount for pre-install hooks` (Review focus 5): `serviceAccount.create: false`, `serviceAccount.name: app-sa` → `serviceAccountName: app-sa`.
  - `it: skips disabled entries`: `enabled: false` → `hasDocuments 0`.
  - `it: omits sidecars`: root `extraContainers: [{name: proxy, image: x:1}]` → `lengthEqual containers 1`.
  - `it: renders a cron job with timeZone`: `cronJobs.cleanup: {enabled: true, schedule: "0 3 * * *", timeZone: Asia/Jakarta}` → `isKind CronJob`, `equal spec.timeZone Asia/Jakarta`.
  - `it: fails on a cron job name over 52 characters`: `fullnameOverride` of 48 chars + key `cleanup` → `errorPattern: cronJobs.cleanup: name .* exceeds 52 characters`.
  - `it: rejects invalid keys` (schema): `jobs.Bad_Key.enabled: true` → `failedTemplate`.
- [ ] **Step 2: Run the suite.** Expected: FAIL.
- [ ] **Step 3: Implement** values: `jobs: {}` and `cronJobs: {}`, with commented examples per spec. Schema: `patternProperties` with the spec's key regex and `additionalProperties: false` per entry. Templates iterate `.Values.jobs` in key order. Add the name-length rule.
- [ ] **Step 4: Add `examples/values-migration-job.yaml`**: busybox `1.36` main Deployment with `podSecurityContext.runAsUser: 65534`, `service.enabled: false`, and `jobs.migrate` as a `pre-install,pre-upgrade` hook running `sh -c 'echo migrated'`. Run `$UT .` and the lint loop. Expected: pass.
- [ ] **Step 5: Commit** `feat(chart): add companion jobs and cron jobs`

### Task 6: KEDA and VPA

**Files:**
- Create: `templates/scaledobject.yaml`, `templates/vpa.yaml`, `examples/values-worker-keda.yaml`
- Modify: `values.yaml`, `values.schema.json`, `templates/deployment.yaml`, `templates/statefulset.yaml`, `templates/_validate.tpl`
- Test: `tests/autoscaling_test.yaml`

- [ ] **Step 1: Write failing tests**:
  - `it: renders a ScaledObject targeting the Deployment`: `keda.enabled: true`, one `cron` trigger → `isAPIVersion keda.sh/v1alpha1`, `equal spec.scaleTargetRef.name RELEASE-NAME-shipform`, `equal spec.maxReplicaCount 10`.
  - `it: omits replicas when KEDA scales the workload` (Review focus 4): deployment and statefulset `notExists spec.replicas`.
  - `it: fails with KEDA and HPA`: `errorPattern: keda.enabled and autoscaling.enabled cannot both be true`.
  - `it: fails with KEDA on a CronJob`: `errorPattern: keda.enabled is supported only for Deployment and StatefulSet`.
  - `it: requires a trigger` (schema): `keda.enabled: true`, `triggers: []` → `failedTemplate`.
  - `it: renders a recommend-only VPA`: `verticalPodAutoscaler.enabled: true` → `isAPIVersion autoscaling.k8s.io/v1`, `equal spec.updatePolicy.updateMode "Off"`, `equal spec.targetRef.kind Deployment`.
  - `it: fails with a VPA on a Job`: `workload.type: Job` → `errorPattern: verticalPodAutoscaler.enabled is supported only for Deployment and StatefulSet`.
  - `it: fails with an active VPA and HPA`: `updateMode: Auto`, `autoscaling.enabled: true` → `errorPattern: verticalPodAutoscaler.updateMode must be Off`.
- [ ] **Step 2: Run the suite.** Expected: FAIL.
- [ ] **Step 3: Implement** per the spec. `targetRef.kind` follows `workload.type`.
- [ ] **Step 4: Add `examples/values-worker-keda.yaml`**: worker Deployment, `service.enabled: false`, KEDA `rabbitmq` trigger with `authenticationRef: {name: rabbitmq-auth}`, `minReplicaCount: 0`. Run `$UT .` and the lint loop. Expected: pass.
- [ ] **Step 5: Commit** `feat(chart): add KEDA ScaledObject and VerticalPodAutoscaler`

### Task 7: Prometheus rules, pod monitors, and extra objects

**Files:**
- Create: `templates/prometheusrule.yaml`, `templates/podmonitor.yaml`, `templates/extra-objects.yaml`
- Modify: `values.yaml`, `values.schema.json`, `templates/_validate.tpl`
- Test: `tests/monitoring_test.yaml`

- [ ] **Step 1: Write failing tests**:
  - `it: renders a PrometheusRule with the given groups`: one group with one alert → `isKind PrometheusRule`, `equal spec.groups[0].name app.rules`.
  - `it: renders a PodMonitor selecting the main pods`: `equal spec.selector.matchLabels` the main selector labels, `equal spec.podMetricsEndpoints[0].port http`.
  - `it: fails with PodMonitor and ServiceMonitor`: `errorPattern: podMonitor.enabled and serviceMonitor.enabled cannot both be true`.
  - `it: renders extraObjects maps through tpl`: item `{apiVersion: v1, kind: ConfigMap, metadata: {name: "{{ .Release.Name }}-extra"}}` → `equal metadata.name RELEASE-NAME-extra`.
  - `it: renders extraObjects strings`: a multi-line string ConfigMap → `isKind ConfigMap`.
- [ ] **Step 2: Run the suite.** Expected: FAIL.
- [ ] **Step 3: Implement** per the spec.
- [ ] **Step 4: Run `$UT .` and the lint loop.** Expected: pass.
- [ ] **Step 5: Commit** `feat(chart): add PrometheusRule, PodMonitor, and extraObjects`

### Task 8: CI coverage on a restricted namespace

**Files:**
- Modify: `.github/workflows/ci.yaml`

- [ ] **Step 1: Change the kind job** so every install runs in namespace `restricted`, labeled `pod-security.kubernetes.io/enforce=restricted`, created in a first step. Existing steps add `-n restricted`; the busybox Job step keeps `runAsUser=65534`.
- [ ] **Step 2: Add two steps**:
  - `Migration hook runs before the Deployment`: `helm install mig . -n restricted -f examples/values-migration-job.yaml --wait --timeout 3m`, then `kubectl -n restricted logs job/mig-shipform-migrate | grep -x migrated`. Hook deletion on success removes the Job, so set `--set jobs.migrate.hookDeletePolicy=before-hook-creation` in this step.
  - `Persistence survives a pod restart`: install `values-persistence.yaml` as `data`, `kubectl exec deploy/data-shipform -- sh -c 'echo ok > /data/probe'`, `kubectl rollout restart deploy/data-shipform && kubectl rollout status ...`, then `kubectl exec deploy/data-shipform -- cat /data/probe | grep -x ok`. The example image is nginx-unprivileged, which has `sh`.
- [ ] **Step 3: Run the kind steps locally** against the `shipform-dev` cluster from Task 2. Expected: every command exits 0.
- [ ] **Step 4: Commit** `ci: install on a restricted namespace and cover hooks and persistence`

### Task 9: CHANGELOG and render diff

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Render diff.** Render default and the 7 original examples into `$TMPDIR/shipform-final` and diff against `$TMPDIR/shipform-baseline` from Task 1. Expected differences only: `readOnlyRootFilesystem: true`, the `tmp` volume and mount (absent in `values-secure-production.yaml`), `enableServiceLinks: false`. Any other difference is a bug to fix in its owning task.
- [ ] **Step 2: Extend the 0.4.0 entry.** Add upgrade notes for the read-only root, service links, and schema guards, each with the value that restores old behavior. Add an `Added` list naming every new block.
- [ ] **Step 3: Run `vale --config ~/.claude/vale/.vale.ini CHANGELOG.md`.** Expected: 0 alerts.
- [ ] **Step 4: Commit** `docs(changelog): describe 0.4.0 resources and hardening`

### Task 10: README rewrite

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Read the structure** of `github/opensource/shiptag/README.md`, `github/opensource/shipguard/README.md`, `github/opensource/omp-cost/README.md`, and `~/.claude/skills/writing-style/templates/readme.md`. Use their shared section order, badge row, and `Ownership` section (`Maintainer: af/faridlamaul`).
- [ ] **Step 2: Rewrite `README.md`.** Required content:
  - one-line outcome; install from OCI and the Helm repo; a quick start values file
  - a feature table linking each values block to its example
  - the security defaults and how to relax each one
  - upgrade pointer to CHANGELOG; hook and persistence caveats from the spec
  - development commands (`$UT`, lint loop, kind) and the release flow from `publish.yaml`
- [ ] **Step 3: Verify** every command in the README by running it, every example path exists, and `vale` reports 0 alerts.
- [ ] **Step 4: Commit** `docs(readme): rewrite for shipform 0.4.0`
