# Pathfinder AI Dev — Phase 1 Milestone Plan

Status: **draft, awaiting approval.** Nov 16, 2026 (milestones rewritten for the expanded scope). Nov 17, 2026: modular agents and a configurable pipeline (A1 to A8); M1 done.

Scope comes from the Phase 1 MVP HLD. Requirement IDs come from the requirements doc. The three design docs were
updated on Nov 16, 2026 to match the decisions below.

## 1. Decisions log (Nov 16, 2026)

### Infrastructure and repo

| # | Decision |
| --- | --- |
| D1 | Add-ons: vendored, pinned upstream release YAML under `deploy/base/addons/`. No Helm. |
| D7, D8 | Folders: `clusters/aks/`, `services/`, `images/`, `hack/`, and a `deploy/overlays/kind/` overlay for local testing. |
| D17 | **Azure Container Registry**, created by Terraform with AcrPull for AKS. The AKS overlay gets a third patch: a Kustomize `images:` rewrite to the ACR hostname. Base uses registry-neutral image names. |
| D18 | Deployment repo on **GitHub**: `grant-terris/pathfinder-ai-dev`, branch `main` (Nov 17, 2026). Flux uses an **SSH deploy key** (read/write, since bootstrap commits to the repo). Milestone work stays on branches until it's merged to `main`, and Flux syncs only `main`. |
| D19 | Peer to an **existing hub VNet**. **Private AKS API server.** Terraform, including the Flux bootstrap, runs from a VPN-connected machine. The API server's private DNS zone must resolve from the hub. |
| D14 | Previews by **hostname per job** (`<job-id>.preview.<internal-domain>`) through an Azure Private DNS wildcard record. |
| D2, D25 | One database `pathfinder` with schemas `orchestrator` and `memory`. CNPG `standard` image (includes pgvector). 2 instances. No backups in Phase 1. |
| D20 | Platform secrets: **SOPS + age**, decrypted by Flux. Terraform creates the age key Secret once. |
| D21 | runc, a hardened securityContext and a per-job NetworkPolicy are accepted for Phase 1. `runtimeClassName` stays configurable. |
| D16 | Generic dev image toolchain: **Node.js / TypeScript** only. |
| D22 | Go for orchestrator, runner and preview proxy. **Web app: React + TypeScript**, built to static files and served by a small container. It talks only to the orchestrator API. |
| F1–F9 | Upstream fact fixes (agent-sandbox `v1beta1`, the `EnvoyProxy` annotation, AKS managed Gateway API CRDs left off, etc.). Applied to the HLD and Architecture doc; see Appendix A. |

### Pipeline behaviour

| # | Decision |
| --- | --- |
| S2 | **Every artifact can be approved or denied with comments.** On a denial, the agent that produced it takes another turn **in its existing session**. Gates are per stage (A3); in the default pipeline they are plan, design (if run) and final review, with Implementer → Tester automatic. Stages without a gate are reviewed at the final gate. |
| C5, C6 | A final approval gate always follows the last stage. The runner pushes `pathfinder/<job-id>` after every run of a stage with `push_branch` set; in the default pipeline that is the Implementer and the Tester (Nov 17, 2026), so added tests reach the branch. |
| S5 | **Skippable stages** (generalised by A3). A gated stage can skip later stages marked `skippable`: its `outcome.json` lists them in `skip` with a reason, and the decision is approved or denied along with that artifact. Default: the Planner decides whether the Designer runs. |
| D11 | **Failure routes** (generalised by A3). A stage can route a `failed` outcome back to an earlier stage, up to a limit, then the job pauses for a person. Default: Tester → Implementer, limit **3**. |
| D13 | A requirements question pauses the job. The answer is delivered to the asking agent's session, which resumes. |
| S1, S3 | **Edits and re-runs:** a person sends a change to an earlier phase's agent (a requirement change goes to the Planner). The pipeline re-runs from there. Each later agent **resumes its own session**, gets the updated upstream artifact as a new message, and **revises its existing artifact**. Normal gates apply. |
| PIP-7 | Between stages, a stage's only input from other stages is their saved artifacts. Session history belongs to its own stage. The Implementer's exit artifact is `implementation.json` (branch, commit SHA, summary); the Tester checks out that SHA. |
| PIP-11 | **The harness must save and resume sessions.** Sessions live on the job's workspace PVC. |
| S6 | **Queue page with "Start now".** It starts a queued job immediately, even over 10. Automatic admission happens only while fewer than 10 jobs are active. The queue is FIFO. A job holds a slot from provisioning until its namespace is fully deleted, including while waiting for a person. No suspend in Phase 1. The `jobs` node pool autoscales. |
| D23 | The runner streams stage logs to the orchestrator, which stores them in PostgreSQL. |
| D26 | Seeded defaults: Opus for Planner and Designer, Sonnet for Implementer and Tester. Editable per agent (A2). |

### Agents and pipeline (Nov 17, 2026)

| # | Decision |
| --- | --- |
| A1 | **Agents are modular configuration.** Add, edit and delete agents on the Agents page. No code change, image build or deployment per agent; every agent runs in the job's dev container through the same runner and `AgentRuntime`. |
| A2 | **Agent config:** `name` (slug), display name, description, system prompt, LLM endpoint (by name) and model, skills (S7), tools (A4), `inputs` (artifact kinds it reads), `output` (exit artifact kind and required files), limits (timeout and max turns per run). |
| A3 | **Pipeline = ordered list of stages.** Each stage: `id`, `agent`, `gate` (bool), `skippable` (bool), `on_fail` (`{return_to: <earlier stage>, max: N}` or none), `push_branch` (bool). A final review always follows the last stage. An agent runs at most one stage, so "the agent that produced it" stays unambiguous. |
| A4 | **Tools:** an allowlist of harness-neutral built-in tool names (`shell`, `read`, `edit`, `write`, `web_fetch`, `web_search`) and Pathfinder tools (`kb_list`, `kb_read`, `memory_search`, `memory_write`, `memory_update`, `memory_delete`), plus extra **MCP servers** by URL (streamable HTTP), with optional header values taken from a platform Secret key. Public servers use the normal internet egress; a server inside the cluster or VNet declares an egress target (CIDR and port, or namespace and pod labels) that the orchestrator adds to the job's NetworkPolicy only when a pinned agent uses it. The harness adapter rejects tool names it can't map, at save time. |
| A5 | **Storage and pinning:** agent configs and the pipeline live in PostgreSQL. Every save is a new version. A job pins the pipeline version and every agent config version (and skill versions, S7) when it starts; edits apply to new jobs only, including re-runs of an open job. Each stage run records its agent version. |
| A6 | **Built-ins are seed data.** Planner, Designer, Implementer and Tester (and the default pipeline) are loaded from `services/orchestrator/seed/` on first start, then edited and deleted like any agent. Seeds never overwrite existing records. |
| A7 | **Validation on save:** at least one stage; every stage input is the output of an earlier stage (the job's requirements are always available); `on_fail.return_to` is an earlier stage; only gated stages can emit `skip`, and only for later `skippable` stages; an agent used by the pipeline can't be deleted until it's removed from it. Versions stay while an open job pins them. |
| A8 | **LLM endpoints** are platform configuration: a ConfigMap lists named endpoints (base URL, API style), with keys in a SOPS-encrypted Secret. An agent picks an endpoint by name and a model. |

### Knowledge base, memory, skills

| # | Decision |
| --- | --- |
| S4 | **Knowledge base:** approved artifacts per repo. Agents get **list and read** tools over it; there's no semantic search over the knowledge base. |
| S4b | **Memory:** short preference snippets per repo. **Agents read and write them at any time** through a memory tool. Each snippet records the job, stage and agent that wrote it. Retrieval is by semantic similarity (pgvector). |
| S4a | **Embedding model: configurable, decided later**, behind an `Embedder` interface. kind tests use a small local model. |
| S4d | Web app pages: **Memory** per repo (view, edit, delete) and **Knowledge base** per repo (browse with previews). |
| C8 | Repo key = normalized `host/owner/name` (lowercase, no `.git`), so HTTPS and SSH URLs for the same repo match. |
| S7, S7a | **Agents page:** lists every agent (A1) and manages each agent's skills (upload, view, enable or disable, replace, delete). Skills use the **Agent Skills folder format** (`.zip`, or a single `SKILL.md` written in the browser). Skills are versioned. **Each job pins the skill versions enabled when it started.** Each run records the versions it used. |

### Security boundaries

| # | Decision |
| --- | --- |
| C1 | The sandbox never connects to PostgreSQL. The runner uses the orchestrator API with a per-job bearer token. NetworkPolicy blocks job namespaces from reaching the database. |
| D24 | The orchestrator's ClusterRole covers namespaces, plus Secrets, Services, NetworkPolicies, ResourceQuotas, `sandboxes.agents.x-k8s.io` and `httproutes` in job namespaces. No `pods/exec`. On restart, it reconciles against namespaces labelled `pathfinder.dev/job-id`. |
| Risk | With no login, anyone on the VPN can upload a skill, edit an agent's system prompt or tools, or register an MCP server, and all of these shape what runs in every new job's sandbox. An MCP server sees the tool calls an agent sends it. LLM-generated code shares the pod with the job's credentials. All are accepted for Phase 1 and tracked as open questions. |

### Still open

| Item | Blocks |
| --- | --- |
| Hub VNet details (subscription, resource group, name, address space, linked Private DNS zones) | M2 |
| Internal DNS domain for previews | M2, M4 |
| Agent harness (must resume sessions and support MCP or equivalent tools) | M13 |
| LLM endpoint and credentials | M13 |
| Embedding model and endpoint | Production use of M12 (kind tests don't need it) |

---

## 2. Design the milestones build on

### Components

- **orchestrator** (Go): deterministic state machine built from each job's pinned pipeline, queue, Kubernetes provisioner, REST API. It stores job state, agent configs, the pipeline, artifacts, the knowledge base, memory, skills and logs. It never calls an LLM. It calls the embedding endpoint only to embed memory snippets and queries, which is a mechanical step with no decisions.
- **runner** (Go, inside the dev container): a deterministic loop. It pulls a task (which carries the pinned agent config), puts the inputs in place, starts or resumes the agent through `AgentRuntime`, uploads the outputs, pushes git after runs of stages with `push_branch`, and reports the outcome. It knows nothing about specific agents. It also serves the **Pathfinder tools** (memory and knowledge base) as a local MCP server that proxies the orchestrator API, exposing only the tools in the agent's allowlist.
- **preview-proxy** (Go, sidecar): serves `/artifacts/…` and reverse-proxies `/` to the app on a configurable port (default 3000).
- **webapp** (React + TypeScript, static files behind a small server): talks only to the orchestrator API.

### AgentRuntime interface (the seam for the undecided harness)

```go
type AgentRuntime interface {
    // Start a new session for this agent and stage. Returns the session ID.
    Start(ctx context.Context, in TurnInput) (TurnResult, error)
    // Continue an existing session with new messages (denial comments, answers,
    // upstream-change notices, Tester bug reports).
    Resume(ctx context.Context, sessionID string, in TurnInput) (TurnResult, error)
}
// TurnInput:  pinned AgentConfig (system prompt, endpoint, model, built-in tool allowlist,
//             MCP servers incl. the runner's Pathfinder server, limits), pinned skills dir,
//             input artifact dir (saved artifacts only), workspace path, output dir,
//             messages []Message, prefetched memory snippets, log writer.
// TurnResult: session ID, outputs incl. machine-readable outcome.json:
//             {status: completed | failed | question, report, question, skip: [{stage, reason}]}
// Implementations also provide Validate(AgentConfig) error, used when an agent is saved (A4).
```

Implementations: `stub` (M8, scripted outcomes, with a real transcript file so resume can be tested) and `<harness>` (M13).

### Job state machine

The machine is generic over the job's pinned pipeline: stages `S0 … Sn-1` in order (A3). In the default pipeline
they are `plan` (gate), `design` (gate, skippable), `implement` (push_branch) and `test` (push_branch, on_fail → implement, max 3).
`next(S)` is the first later stage not skipped by an approved `skip` decision, or the final review if there is none.

States: `queued`, `provisioning`, `running(S)`, `awaiting_review(S)`, `awaiting_answer(S)`,
`awaiting_final_review`, `approved`, `failed(S)`, `closing`, `closed`.

```
queued ──auto admit (active < 10) | start_now──► provisioning ──ready──► running(S0)
running(S) ──completed, gate(S)──► awaiting_review(S) ──approve──► running(next(S))
running(S) ──completed, no gate──► running(next(S))                      (PIP-3)
next(S) = none ──► awaiting_final_review ──approve──► approved
running(S) ──failed, on_fail(S)=(T, N), n < N──► running(T) [resume + report] (PIP-5)
running(S) ──failed, on_fail(S)=(T, N), n = N──► awaiting_answer(T)
running(S) ──failed, no on_fail──► failed(S)
running(S) ──question──► awaiting_answer(S) ──answer──► running(S) [resume]   (PIP-6)
awaiting_review(S) ──deny + comments──► running(S) [resume]                  (PIP-9)
awaiting_final_review ──deny(S) + comments──► running(S) [resume]   (any stage that ran)
any open state ──change(T ≤ current stage) + comments──► running(T) [resume]  (EDT-2..6)
      cancels any running turn; approvals from T onward become stale;
      later stages then run as [resume + upstream-changed notice]; normal gates apply
running(S) ──error──► failed(S) ──retry──► running(S)
any non-closed ──close──► closing ──namespace gone──► closed (slot freed)
```

Edge cases the tests must cover:
- A revision removes a stage from `skip` (the default case: a plan revision now needs design): that stage starts a new session when reached.
- A revision adds a stage to `skip`: its existing artifact is marked superseded.
- A `skip` from a stage with no gate, or naming a stage that isn't `skippable` or isn't later, fails the turn.
- Editing the pipeline or an agent never changes an open job's machine (A5).
- A change sent to `approved` reopens the job.
- Comments sent while a stage is running are queued for that agent's next turn.

### Data (PostgreSQL `pathfinder`)

- `orchestrator` schema:
  - `jobs`
  - `job_events`: append-only transition log
  - `agents`, `agent_versions` (config JSON, system prompt)
  - `pipeline_versions` (stage list JSON)
  - `job_pins`: pipeline version, agent versions
  - `stage_runs`: stage, agent version, turn number, mode, session ID, skill versions, outcome
  - `comments`, `stage_logs`
  - `skills`, `skill_versions` (zip `bytea`, `SKILL.md` front matter), `job_skill_pins`
- `memory` schema:
  - `artifacts`: repo key, job, stage, turn, kind, content, sha256, `approved_at`, `superseded_by`
  - `memory_snippets`: repo key, text, `embedding vector`, embedding model, author job/stage/agent, timestamps, `deleted_at`

Embeddings are stored with their model name. The search is an exact scan per repo, which is fine at Phase 1 sizes. An HNSW
index is added once the model, and so the vector dimension, is fixed.

---

## 3. Milestones

Each milestone ends with an approval stop. "kind" means the local cluster overlay (D8).

| # | Milestone | Needs AKS? | Blocked on |
| --- | --- | --- | --- |
| M1 | Repo skeleton and Kustomize structure | No | — |
| M2 | Terraform: private AKS, ACR, DNS, Flux bootstrap | Yes | Hub VNet, domain |
| M3 | Cluster add-ons via Flux | kind first | — |
| M4 | Internal Gateway and preview DNS | Yes, for the LB | Domain |
| M5 | PostgreSQL and schema | kind first | — |
| M6 | Pipeline spec and orchestrator state machine (pure) | No | — |
| M7 | Orchestrator API, store and queue | kind | — |
| M8 | Per-job namespace lifecycle | kind | — |
| M9 | Runner, AgentRuntime and stub pipeline end to end | kind | — |
| M10 | Web app: jobs, reviews, re-runs, queue | kind | — |
| M11 | Agents page: agent configs, pipeline editor, tools and skills | kind | — |
| M12 | Knowledge base and memory | kind | Embedding model, for production only |
| M13 | Real agent harness | kind, then AKS | Harness, LLM endpoint |
| M14 | Phase 1 done check | Yes | — |

M1, M3, M5 and M6 can start now. M6 has no dependencies and can run alongside the infrastructure milestones.

### M1: Repo skeleton and Kustomize structure

- **Files:** `README.md`, `.gitignore`, `Makefile` (`tools`, `validate`, `test`, `clean`).
  - `deploy/base/addons/kustomization.yaml`
  - `deploy/base/platform/{kustomization.yaml, namespace.yaml, storageclass.yaml}`
  - `deploy/overlays/aks/{addons,platform}/kustomization.yaml`, plus `patches/storageclass.yaml`
  - `deploy/overlays/kind/{addons,platform}/…`
  - `clusters/aks/README.md`, `hack/check-base-portability.sh`, `hack/test-check-base-portability.sh`
  - **Moved to M2:** `.sops.yaml` (needs the age public key Terraform creates) and the ACR `images:` patch (needs the registry name). Neither gets a placeholder.
- **StorageClass:** base defines `pathfinder-standard` with a placeholder provisioner. The AKS patch sets `disk.csi.azure.com`
  with `skuName: StandardSSD_LRS`; kind uses `rancher.io/local-path`. `provisioner` can't be changed on a live object, so
  each overlay must be correct before its first sync.
- **Test:** every overlay builds with `kubectl kustomize`, and `kubeconform` validates the output. The portability script
  fails if `deploy/base/` contains `azure`, `disk.csi.azure.com`, `service.beta.kubernetes.io/azure` or an ACR hostname.
- **Covers:** PLT-2, PLT-9.

### M2: Terraform for private AKS, ACR, DNS and the Flux bootstrap

- **Files:** `infra/{versions.tf, providers.tf, backend.tf, variables.tf, network.tf, aks.tf, acr.tf, dns.tf,
  flux.tf, outputs.tf, terraform.tfvars.example, README.md}`.
- **Content:**
  - **Network:** resource group; VNet and subnets; peering to the hub; Network Contributor on the subnet for the cluster identity (needed for an internal LB).
  - **AKS:** private cluster with its private DNS zone linked to the hub. Azure CNI Overlay with the Cilium dataplane, so standard NetworkPolicy is enforced. A system node pool, plus a `jobs` node pool with the cluster autoscaler and taint `pathfinder.dev/jobs`. **No** `web_app_routing`, **no** managed Gateway API, **no** app-routing Istio.
  - **ACR**, with AcrPull for the kubelet identity.
  - **Private DNS** zone `<internal-domain>`, linked to the hub VNet. The wildcard record is added in M4, once the LB IP exists.
  - **Flux:** `flux_bootstrap_git` with `path = "clusters/aks"` (it can't be changed later) and a deliberate `delete_git_manifests` setting. Terraform also creates the SOPS age key Secret in `flux-system`.
  - **State:** remote state in a pre-created storage account.
- **Test:**
  - `terraform fmt -check`, `validate`, `tflint` and `plan` are clean.
  - Apply from the VPN: `flux check` passes, and the Flux git source is Ready.
  - `kubectl get crd | grep gateway.networking` is empty, which proves AKS isn't managing those CRDs.
  - The API server isn't reachable from off the VPN.
- **Covers:** PLT-1, PLT-10.

### M3: Cluster add-ons via Flux

- **Files:** `deploy/base/addons/{envoy-gateway,agent-sandbox,cloudnative-pg}/{kustomization.yaml, upstream.yaml,
  VERSION}`, `hack/vendor-addons.sh`, and `clusters/aks/addons.yaml` (a Flux Kustomization with `wait: true`).
- **Versions:** Envoy Gateway v1.10.0, agent-sandbox v1.0.2 (core `sandbox.yaml`), and CNPG at the latest stable release on the day it's vendored. Also record which Gateway API version Envoy Gateway bundles.
- **Test:** on kind, `kubectl apply --server-side -k deploy/overlays/kind/addons`. All controllers become Available, and a test
  `Sandbox` (busybox, with a `volumeClaimTemplates` entry) becomes Ready and deletes cleanly along with its PVC. On AKS, the Flux
  `addons` Kustomization is Ready.
- **Covers:** PLT-10.

### M4: Internal Gateway and preview DNS

- **Files:**
  - `deploy/base/platform/gateway/{envoyproxy.yaml, gatewayclass.yaml, gateway.yaml, echo-route.yaml}`
  - `deploy/overlays/aks/platform/patches/envoyproxy-internal-lb.yaml`
  - `clusters/aks/platform.yaml` (Flux Kustomization, `dependsOn: addons`)
  - the wildcard record in `infra/dns.tf`
- **Content:** one HTTP listener that accepts routes only from namespaces labelled `pathfinder.dev/gateway-access: "true"`. Hostnames are `pathfinder.<domain>` for the web app and `*.preview.<domain>` for job previews.
- **Test:**
  - The Envoy Service gets a private IP from the subnet, not a public one.
  - From the VPN, `curl` works for both the web app hostname and a test `x.preview.<domain>`.
  - From off the VPN, neither resolves or connects.
- **Covers:** PRV-2, WEB-3, PLT-9.

### M5: PostgreSQL and schema

- **Files:**
  - `deploy/base/platform/postgres/{cluster.yaml, networkpolicy.yaml}`
  - `services/orchestrator/migrations/0001_init.sql` (both schemas from §2, including `CREATE EXTENSION vector`)
  - `services/orchestrator/internal/store/migrate.go` and its test
- **Test:**
  - The CNPG `Cluster` is healthy with 2 instances.
  - After the primary pod is deleted, the `-rw` Service follows the new primary.
  - Migrations run up, and re-running them is a no-op (tested against an ephemeral `standard` Postgres).
  - The `vector` extension is present.
  - A pod in an unlabelled namespace can't reach the database.
- **Covers:** MEM-1, MEM-2, PLT-8 (a queue that survives restarts).

### M6: Pipeline spec and orchestrator state machine (pure)

- **Files:**
  - `services/orchestrator/internal/pipeline/{spec.go, agent.go, validate.go, validate_test.go}`: the `Pipeline`, `Stage` and `AgentConfig` types and the A7 rules.
  - `services/orchestrator/internal/fsm/{fsm.go, events.go, fsm_test.go, property_test.go}`: the machine, built from a `Pipeline`. No I/O.
- **Test:**
  - Validation accepts the default pipeline and rejects each A7 violation.
  - A table test on the default pipeline covers every (state, event) pair, including illegal ones, plus all the edge cases in §2.
  - The same table runs against variants: one stage only; no gates at all; a fifth stage inserted mid-pipeline; the Designer removed; a failure route spanning two stages.
  - Property tests over random event sequences check that:
    - automatic admission never pushes active jobs past 10, and "Start now" can;
    - the queue stays FIFO among automatically admitted jobs;
    - the loop count resets after a person intervenes;
    - stale approvals never let a job advance;
    - every stage turn after the first resumes a session rather than starting a new one;
    - for random valid pipelines, every job ends in `approved`, `failed`, `awaiting_*` or `closed`, never stuck.
- **Covers:** PIP-1, PIP-3, PIP-5, PIP-6, PIP-8, PIP-9, PIP-10, AGT-5, AGT-6, AGT-10, EDT-1 to EDT-6, PLT-8, LIF-7.

### M7: Orchestrator API, store and queue

- **Files:**
  - `services/orchestrator/{cmd/orchestrator/main.go, internal/store/…, internal/api/…, Dockerfile}`
  - `api/openapi.yaml`
  - `deploy/base/platform/orchestrator/{deployment.yaml, service.yaml, serviceaccount.yaml, rbac.yaml, configmap-llm-endpoints.yaml}`
  - `services/orchestrator/seed/{pipeline.yaml, agents/<name>/{agent.yaml, prompt.md}}` for the four default agents, loaded on first start (A6). Prompts are placeholders until M13.
  - Uses a **fake provisioner** until M8.
- **API:**
  - **Jobs:** `POST/GET /v1/jobs`, `GET /v1/jobs/{id}`, `POST /v1/jobs/{id}/{start-now,close,retry}`, `GET /v1/queue`.
  - **Reviews and changes:** `POST /v1/jobs/{id}/stages/{stage}/{approve,deny}`, `POST /v1/jobs/{id}/changes` (target stage and comment), `POST /v1/jobs/{id}/answer`, `POST/GET /v1/jobs/{id}/comments`.
  - **Artifacts and logs:** `GET /v1/jobs/{id}/{artifacts,logs,events}`, `GET /v1/artifacts/{id}`.
  - **Runner side** (per-job bearer token): `GET /v1/runner/next-task` (long poll), `POST /v1/runner/tasks/{id}/{artifacts,logs,result}`.
- **Test:**
  - Submit 12 jobs: 10 are provisioning and 2 are queued.
  - "Start now" on the 12th job gives 11 active. Closing 2 jobs admits nothing automatically until fewer than 10 are active, after which the remaining queued job starts.
  - Restarting the orchestrator mid-flight leaves state unchanged.
  - Seeds load once; a second start doesn't overwrite an edited agent.
  - A new job pins the current pipeline and agent versions.
  - Every endpoint is checked against the OpenAPI spec.
- **Covers:** PLT-7, PLT-8, LIF-7, WEB-5 (API), AGT-8 (pinning).

### M8: Per-job namespace lifecycle

- **Files:**
  - `services/orchestrator/internal/provisioner/{k8s.go, render.go, render_test.go, testdata/golden/*.yaml}`
  - `services/preview-proxy/…`
  - `images/dev/Dockerfile` (Node.js LTS, git; the runner is added in M9)
- **Objects per job:**
  - Namespace with labels `pathfinder.dev/job-id` and `pathfinder.dev/gateway-access`.
  - Secret: git credential, LLM and embedding credentials, runner token.
  - `Sandbox` with `service: false`, a workspace `volumeClaimTemplates` entry on `pathfinder-standard`, an init container that clones the repo and creates `pathfinder/<job-id>` if the PVC is empty, the dev container, the preview-proxy sidecar, and a toleration for the `jobs` pool.
  - ClusterIP Service pointing at the preview proxy.
  - HTTPRoute for `<job-id>.preview.<domain>`.
  - NetworkPolicy: ingress only from the Gateway; egress only to DNS, the orchestrator API and the internet, excluding cluster and VNet CIDRs, plus the egress targets of MCP servers used by the job's pinned agents (A4).
  - ResourceQuota and LimitRange.
- **Teardown:** delete the namespace, wait until it's gone, then free the slot.
- **Test:**
  - Golden-file tests cover the rendered objects, including a job whose agent uses an in-cluster MCP server.
  - On kind, a job against a test repo creates every object. The PVC holds the clone on the new branch, and the preview hostname serves a placeholder.
  - The sandbox can't reach PostgreSQL or another job's namespace.
  - Closing the job deletes the namespace, and the next queued job starts.
  - Killing the orchestrator mid-provision leads to a correct reconcile.
- **Covers:** LIF-2, LIF-3, LIF-4, LIF-6, PRV-1, PRV-2.

### M9: Runner, AgentRuntime and stub pipeline end to end

- **Files:** `services/runner/{cmd, internal/loop, internal/runtime/runtime.go, internal/runtime/stub/…,
  internal/git/push.go, internal/tools/mcp.go (stub tool server)}`. The runner is added to `images/dev/`.
- **Stub runtime:** generic, with no agent names in code. It writes a transcript file per session, so resume can be checked, records the system prompt and tool list it was given, and produces whatever files the agent's `output` declares, plus `outcome.json`. A stage with `push_branch` also gets a commit. Tokens in the requirements text script the outcomes: `STUB:SKIP=<stage>`, `STUB:FAIL=<stage>:n`, `STUB:QUESTION=<stage>`.
- **Test** (scripted end to end on kind against a local git server, driven through the API):
  1. Happy path to `approved`, with the branch pushed after each Implementer and Tester run.
  2. `STUB:SKIP=design` from the Planner skips the Designer.
  3. Deny the plan with comments: the Planner's transcript shows the same session resumed.
  4. A code-bug loop recovers. Three bugs pause the job; an answer resumes it.
  5. Mid-test, a requirement change goes to the Planner: plan, design, implement and test re-run, each resuming its own session, with gates applied.
  6. Deny the tests at final review: only the Tester re-runs.
  7. Close a job mid-stage.
  8. In every turn, the stage's input dir contains **only** saved artifacts (PIP-7), and only those the agent declares as `inputs`.
  9. A five-stage pipeline seeded through the API (a gated "Reviewer" between Implementer and Tester) runs end to end with no code change.
- **Covers:** AGT-10, PIP-1, PIP-2, PIP-5, PIP-6, PIP-7, PIP-9, PIP-10, PIP-11 (interface), EDT-1 to EDT-6, MEM-1, PRV-3, INT-5 (a branch instead of a PR).

### M10: Web app: jobs, reviews, re-runs, queue

- **Files:**
  - `services/webapp/{package.json, vite.config.ts, src/{api (client generated from openapi.yaml), pages, components}, Dockerfile}`
  - `deploy/base/platform/webapp/{deployment.yaml, service.yaml, httproute.yaml}`
- **Pages:**
  - **Jobs list:** state, stage, active count against the limit.
  - **New job:** requirements, repo URL, base branch.
  - **Job detail:**
    - Stage timeline, with the turn history for each stage.
    - Artifacts with preview links.
    - **Approve / Deny with comments** on the current artifact. At final review this covers both the implementation and the tests.
    - **Send change to stage…** for earlier stages.
    - Answer box when the job is paused.
    - Comments, live logs, Retry and Close.
  - **Queue:** ordered list; open an entry and press **Start now**, with a warning when this goes past 10.
- **Test:**
  - Component tests run against a mocked API.
  - A Playwright end-to-end test on kind with the stub runtime walks through the M9 scenarios 1, 3, 5 and 6 using only the UI, plus "Start now".
- **Covers:** WEB-1, WEB-2 (logs and turn history), WEB-3, WEB-5, PIP-3, PIP-9, EDT-2, INT-1, INT-3, INT-4, PRV-5.

### M11: Agents page: agent configs, pipeline editor, tools and skills

- **Files:**
  - Orchestrator `internal/agents/…` and `internal/skills/…`, with API endpoints:
    - Agents: `GET/POST /v1/agents`, `GET/PUT/DELETE /v1/agents/{agent}`, `GET /v1/agents/{agent}/versions[/{v}]`
    - Pipeline: `GET/PUT /v1/pipeline`, `GET /v1/pipeline/versions[/{v}]`
    - Choices for the editor: `GET /v1/llm-endpoints`, `GET /v1/tools` (built-in and Pathfinder tool names the runtime supports)
    - Skills: `GET/POST /v1/agents/{agent}/skills`, `GET/PUT/PATCH/DELETE /v1/agents/{agent}/skills/{id}`, `GET /v1/skills/{id}/versions/{v}`
  - Runner: put the pinned skills in place at turn start; pass the agent's MCP servers to the runtime; expose only allowlisted Pathfinder tools
  - Web app: **Agents** page: agent list (with "not in pipeline" marked), agent editor (name, description, system prompt, endpoint and model, tools and MCP servers, inputs and output, limits, skills), version history with diff, and a **pipeline editor** (add, remove and reorder stages; gate, skippable, failure route, push branch) that shows validation errors before saving
- **Rules:**
  - Every agent or pipeline save creates a new version; validation (A7) and `AgentRuntime.Validate` (A4) run first.
  - Deleting an agent the pipeline uses is refused; otherwise it hides the agent from new jobs, and versions stay while an open job pins them.
  - MCP header secrets are references to platform Secret keys, never stored in PostgreSQL.
  - Validate the zip: a `SKILL.md` with `name` and `description` front matter, a size limit, no path traversal or symlinks.
  - Each upload or replace creates a new version.
  - A job pins its enabled versions when it starts.
  - Deleting a skill hides it from new jobs; versions are kept while an open job pins them.
- **Test:**
  - Unit tests reject malformed zips.
  - A job started before a skill change still gets the old version, and a new job gets the new one.
  - The skill version appears in `stage_runs`.
  - A Playwright test uploads, disables, replaces and deletes a skill.
  - A Playwright test adds a new agent, inserts it into the pipeline, deletes the Designer from the pipeline, and runs a stub job that follows the new pipeline; a job started earlier keeps the old one.
  - Invalid pipelines (an input with no producer, a forward failure route, a skip from an ungated stage) are rejected with a clear message.
  - Editing an agent's system prompt or tools shows up in the next new job's stub transcript and in `stage_runs.agent_version`.
  - Registering an in-cluster MCP server on an agent adds its egress rule only to jobs that pin that agent.
- **Covers:** PLT-5, PLT-6, AGT-1 to AGT-9, SKL-1 to SKL-7, WEB-4.

### M12: Knowledge base and memory

- **Files:**
  - **Orchestrator:** `internal/kb/…` and `internal/memory/…`, plus the `Embedder` interface with `openai-compatible` and `local` implementations. API: `GET /v1/repos`, `GET /v1/repos/{key}/kb`, `GET /v1/repos/{key}/memory` (list and search), and `POST/PATCH/DELETE` for memory snippets.
  - **Runner:** real MCP tools `kb_list`, `kb_read`, `memory_search`, `memory_write`, `memory_update`, `memory_delete`, all scoped to the job's repo. At turn start, the runner also prefetches the top-k memory snippets for the stage's input.
  - **Web app:** **Memory** and **Knowledge base** pages per repo.
  - **Test model:** a small embedding model Deployment in the kind overlay.
- **Rules:**
  - An artifact joins the knowledge base when it's approved.
  - Snippets record their author: job, stage and agent.
  - Memory writes from one job are visible to other jobs on the same repo straight away.
- **Test:**
  - A stub agent writes "always use react hook form", and a later job's prefetch for a forms-related plan returns it.
  - A different repo never sees it.
  - Knowledge base list and read return only approved artifacts for the job's own repo.
  - Editing or deleting a snippet in the UI takes effect on the next retrieval.
  - Switching the embedding model in config re-embeds the snippets (`hack/reembed`).
- **Covers:** MEM-2 to MEM-8, WEB-6.

### M13: Real agent harness (blocked until the harness and endpoint are chosen)

- **Files:**
  - `services/runner/internal/runtime/<harness>/…`: the adapter mapping `AgentConfig` (system prompt, model, tool allowlist, MCP servers, skills, limits) onto the harness, plus `Validate`
  - Real system prompts in `services/orchestrator/seed/agents/{planner,designer,implementer,tester}/prompt.md`
  - Endpoint entries in `configmap-llm-endpoints.yaml`
  - A SOPS-encrypted Secret for the endpoint
- **Contract:** every turn must produce the agent's declared output files and a valid `outcome.json`. If it doesn't, the stage errors. The orchestrator never reads free text.
- **Test:**
  - Run 3 sample Node/TypeScript repos end to end.
  - Deny and revise in the same session, and run a requirement-change re-run.
  - Agents use their pinned skills and the memory and knowledge base tools.
  - Change one agent's model, system prompt and tool allowlist in the web app with no code change, and see the next job use them (PLT-5, AGT-2).
  - A built-in tool removed from an agent's allowlist is unavailable to it.
  - An agent uses an external MCP server registered in its config.
- **Covers:** PLT-5, PLT-6, PIP-1, PIP-11, AGT-2 to AGT-4, PRV-4.

### M14: Phase 1 done check

- **Files:** `hack/load-test/…` (submits jobs and drives approvals through the API), `docs/runbook.md`.
- **Test:**
  - Submit 12 jobs against a sample repo. Exactly 10 run and 2 queue.
  - "Start now" runs an 11th job.
  - Every job ends with approved, tested code on its own branch.
  - Queued jobs start as slots free.
  - No job can reach another job over the network.
  - The autoscaler absorbs the overflow job. Record CPU and memory per sandbox.
- **Covers:** the Phase 1 done criteria; PLT-8, LIF-7.

---

## Appendix A: upstream fact checks (Nov 16, 2026)

| # | Finding | Applied |
| --- | --- | --- |
| F1 | agent-sandbox `Sandbox` is `agents.x-k8s.io/v1beta1` (release v1.0.2), not `v1alpha1` ([repo](https://github.com/kubernetes-sigs/agent-sandbox)) | Architecture, HLD |
| F2 | Pausing a sandbox uses `spec.operatingMode: Suspended`; the pod is removed and the Sandbox and PVCs are kept ([API ref](https://agent-sandbox.sigs.k8s.io/docs/api/)) | Architecture |
| F3 | A Sandbox creates only a headless Service, and only with `spec.service: true` | HLD (we create our own ClusterIP Service) |
| F4 | Envoy Gateway installs its own CRDs as well as the Gateway API CRDs ([install.yaml](https://gateway.envoyproxy.io/docs/install/install-yaml/)) | HLD |
| F5 | Envoy Gateway generates the LB Service, in `envoy-gateway-system` by default. Annotations go in `EnvoyProxy.spec.provider.kubernetes.envoyService.annotations` ([docs](https://gateway.envoyproxy.io/docs/tasks/operations/customize-envoyproxy/)) | HLD |
| F6 | Envoy Gateway publishes a plain `install.yaml` per release (v1.10.0) | HLD |
| F7 | AKS managed Gateway API CRDs (`--enable-gateway-api`) are GA. They're the upstream standard-channel CRDs, but AKS owns their version, disallows experimental CRDs, and doesn't support self-managed implementations ([Microsoft Learn](https://learn.microsoft.com/azure/aks/managed-gateway-api)). Left off. | HLD, Architecture |
| F8 | Wrong project links for pgvector, Sysbox, Longhorn and DevPod | Architecture |
| F9 | `flux_bootstrap_git` is current. `path` can't be changed later, and `delete_git_manifests` defaults to `true` ([docs](https://github.com/fluxcd/terraform-provider-flux/blob/main/docs/resources/bootstrap_git.md)) | Plan (M2) |
| F10 | CNPG `standard` images include pgvector ([postgres-containers](https://github.com/cloudnative-pg/postgres-containers)) | HLD, Architecture |
| F11 | Anthropic offers no embedding model ([docs](https://platform.claude.com/docs/en/build-with-claude/embeddings)) | HLD, Architecture |

Not verified: whether Envoy Gateway honours `Gateway.spec.infrastructure.annotations`. Nothing depends on it. The embedded
diagrams in the design docs don't come through in the Markdown, and the requirements doc notes that its flow diagram is out of date.
