# Pathfinder AI Dev — Phase 1 MVP HLD

Nov 16, 2026 · @Grant Terris · Draft (revised Nov 16 and Nov 17, 2026 with the decisions in `docs/phase1-plan.md`)

## Purpose and scope

Phase 1 proves the core loop on Azure AKS. A person starts a job from the Pathfinder web app, and a configurable pipeline of agents (four by default) takes it from requirements to tested code inside one sandbox. A human reviews every artifact in the web app, approving it or denying it with comments. There is no Jira or GitHub integration yet; the web app replaces both. Agents do use plain git to clone the job's repository, commit, and push. Requirement IDs refer to the requirements doc.

| Area | Phase 1 | Later | Requirement IDs |
| --- | --- | --- | --- |
| Hosting | Azure AKS | Any Kubernetes | PLT-1, PLT-2 |
| Starting work | A person starts a job from the web app, entering requirements as text and a git repository URL | Jira trigger when a ticket is pulled into the sprint | LIF-1 |
| Code source | The job clones the repository over git | Same | LIF-2 |
| Agent pipeline | A configurable, ordered list of stages, each run by one agent, with exit artifacts. Default: Planner, Designer, Implementer, Tester, where the Planner decides whether the Designer runs | Same | PIP-1, PIP-2, PIP-7, PIP-8, PIP-10, AGT-5, AGT-6, AGT-10 |
| Agents | Modular: add, edit and delete agents in the web app. Each agent's configuration sets its system prompt, LLM endpoint and model, skills, tools (built-in allowlist, Pathfinder tools, extra MCP servers), input and exit artifacts, and run limits. The four defaults are seeded as editable agents. Versioned; each job pins the versions current when it started | Same | AGT-1 to AGT-9, PLT-5, PLT-6 |
| Approvals | Approve, or deny with comments, on every artifact in the web app. A gate per stage is configurable, and a final review always follows the last stage. Default: gates after plan and design, Implementer → Tester automatic, then the final review | Jira status transitions | PIP-3, PIP-4, PIP-9 |
| Revisions | A denied artifact goes back to the agent that produced it, which takes another turn in its existing session | Same | PIP-9, PIP-11 |
| Failure loops | A stage can send a failure back to an earlier stage automatically, up to a limit, then the job pauses for a person. Default: the Tester sends code bugs to the Implementer, at most 3 times | Same | PIP-5 |
| Conversation | Comments in the web app | Jira and GitHub comments | INT-1 to INT-7 |
| Code delivery | The job's branch `pathfinder/<job-id>` is pushed to its git remote after every run of a stage configured to push. Default: the Implementer and the Tester | GitHub pull request and PR comments | INT-5, INT-6 |
| Previews | Internal preview proxy per job, one hostname per job | Same | PRV-1 to PRV-5 |
| Concurrency | Up to 10 jobs start automatically, the rest queue first in, first out. "Start now" on a queued job starts it immediately, even over 10 | Same | PLT-8, LIF-7, WEB-5 |
| Knowledge base | Approved artifacts saved per repository. Later jobs' agents can list and read them | Same | MEM-1 to MEM-3, MEM-5 |
| Memory | Per-repo preference snippets that agents read and write on their own, retrieved by semantic similarity (pgvector). Embedding model is configurable, not yet chosen | Same | MEM-4, MEM-6, MEM-7 |
| Access | VPN only; no web app login | To be decided | WEB-3 |
| Edits and re-runs | A change sent to an earlier phase's agent re-runs the pipeline from that phase. Requirement changes go to the Planner. Later agents resume their own sessions and revise their existing artifacts. Normal gates apply | Jira-triggered edits | EDT-1 to EDT-6 |
| Monitoring agents | Deferred | Cron-scheduled monitors | MON-1 to MON-7 |
| Web app | Job list, stage view, agent logs, queue with "Start now", Agents page (agents, their configuration and skills, and the pipeline editor), Memory and Knowledge base pages per repo | Full debugger | WEB-1 to WEB-6 |
| Agent skills | Agents page: upload and manage skills per agent, versioned. Each job uses the skill versions enabled when it started | Same | PLT-6, SKL-1 to SKL-7, WEB-4 |

**Done for Phase 1:** 10 jobs run at the same time, each going from requirements to approved, tested code pushed to its own branch, while further jobs wait in the queue and start as slots free up.

## Architecture

Phase 1 keeps the full design's shape but drops everything that faces Jira or GitHub. There is no public endpoint and no listener agent. People reach the web app and previews over the internal network. Outbound traffic goes only to the LLM and embedding endpoints and to git remotes.

&#91;embedded content: Phase 1 on AKS · one shared namespace and one namespace per active job\]

## Components

| Namespace | Component | Kubernetes objects | Phase 1 role |
| --- | --- | --- | --- |
| envoy-gateway-system | Envoy Gateway | Envoy Gateway controller and the Envoy proxy it generates, including one Service of type `LoadBalancer` configured through an `EnvoyProxy` resource | Data plane for the single internal entry point |
| pathfinder-system | Gateway | `GatewayClass`, `Gateway` with an internal listener, `EnvoyProxy` | Routes the web app and per-job previews |
| pathfinder-system | Web app | Deployment, Service, internal HTTPRoute | React app. Start jobs, enter requirements, review (approve or deny with comments) every artifact, send changes to an earlier phase, view status, queue and agent logs, start a queued job now, add, edit and delete agents and their skills, edit the pipeline, browse each repo's memory and knowledge base |
| pathfinder-system | Orchestrator | Deployment, Service | Go. Deterministic state machine: queue, stage per job, approvals and revisions, re-runs, creates and deletes job namespaces, REST API for the web app and job runners (PIP-8). Builds each job's state machine from its pinned pipeline. Stores agent configurations, the pipeline, skills, the knowledge base and memory |
| pathfinder-system | PostgreSQL | CloudNativePG `Cluster` (`standard` image, which includes pgvector), 2 instances, with PVCs | Orchestrator state, agent configurations and pipeline, knowledge base, memory with embeddings, agent skills |
| Per job | Job sandbox | `Sandbox` (agent-sandbox, `agents.x-k8s.io/v1beta1`) = one pod with a dev container and a preview proxy | Dev container runs the job runner and the agent harness for every agent in the job's pipeline |
| Per job | Workspace volume | PVC from the Sandbox's `volumeClaimTemplates` | Code, build output, artifacts and agent sessions for the job's whole life |
| Per job | Preview routing | ClusterIP Service, internal HTTPRoute | Exposes the preview proxy through the internal Gateway |
| Per job | Credentials | Secret | LLM and embedding endpoint keys, credentials for the pinned agents' MCP servers, git credentials, and the runner's API token for that job |
| Per job | Network policy | NetworkPolicy | Ingress only from the Gateway. Egress only to DNS, the orchestrator API, the internet, and any in-cluster or VNet MCP servers the pinned agents use |

The always-on listener agent from the full design is left out, because there are no Jira or GitHub comments to listen for. Comments and change requests entered in the web app go to the orchestrator, which routes them to the right agent's next turn.

**Job runner.** Each dev container runs a small deterministic runner, not an agent. It pulls its next task from the orchestrator API and puts the saved input artifacts in place. It then starts or resumes the agent's session through the `AgentRuntime` interface, uploads the outputs, pushes the branch after each run of a stage configured to push, and reports the outcome. The sandbox never connects to PostgreSQL directly; everything goes through the orchestrator API.

**Agents are configuration.** An agent is a versioned record: name, description, system prompt, LLM endpoint and model, skills, tools, the artifacts it reads, the exit artifact it produces, and run limits. Adding an agent needs no image build or deployment; every agent runs in the same dev container through the same runner. The pipeline is a separate versioned record: an ordered list of stages, each naming one agent, with a gate flag, a skippable flag, an optional failure route to an earlier stage with a retry limit, and a push-branch flag. The orchestrator validates both on save and pins the versions in force when each job starts (AGT-6, AGT-8). Planner, Designer, Implementer and Tester are seed data, loaded on first start and editable afterwards.

**Tools.** Each agent's tools are an allowlist of harness-neutral built-in tool names (such as `shell`, `read`, `edit`, `web_fetch`) and Pathfinder tools (knowledge base list and read, memory search and write), plus any extra MCP servers registered by URL. The runner serves the Pathfinder tools as a local MCP server and passes the agent's extra MCP servers to the harness. Public MCP servers are reached through the normal internet egress; an MCP server inside the cluster or the VNet is opened in that job's NetworkPolicy only when a pinned agent uses it. MCP credentials are referenced from platform Secrets and copied into the job Secret.

**Agent harness.** Not yet chosen. It sits behind the `AgentRuntime` interface, and its adapter maps an agent's configuration (system prompt, model, tool allowlist, MCP servers, skills) onto the harness. It must support saving and resuming a session (PIP-11) and MCP tools.

## Job flow

A job replaces the Jira ticket as the unit of work in Phase 1.

1. A person starts a job in the web app, enters the requirements as text, and gives the git repository URL to work on.
2. The orchestrator records the job in PostgreSQL. It queues the job if 10 jobs are already running, unless a person presses "Start now".
3. When a slot is free, the orchestrator creates the job namespace, Secret, `Sandbox` (with its workspace volume), Service, HTTPRoute and NetworkPolicy. The sandbox clones the repository into the workspace volume and creates the job's branch.
4. The orchestrator pins the pipeline, agent configuration and skill versions current at that moment, and runs the stages in order. Steps 5 to 8 describe the default pipeline; a customised pipeline follows the same rules with its own stages, gates, skips and failure routes.
5. The Planner writes `plan.md`, including whether design is needed and why. A person approves it, or denies it with comments, and the Planner takes another turn in the same session.
6. If design is needed, the Designer produces the HTML mockups and design, and goes through the same review. Otherwise the job goes straight to implementation.
7. The Implementer writes and commits the code. The runner pushes the job's branch. The Tester starts automatically (PIP-3).
8. The Tester adds and commits tests and produces HTML test results. The runner pushes the job's branch. A code bug sends the work back to the Implementer automatically, at most 3 times before the job pauses for a person. A requirements question pauses the job for a person (PIP-5, PIP-6).
9. A person tries the running app through the preview and gives the final approval, or denies any stage's artifact with comments. Each agent can only take another turn on its own artifact.
10. At any point, a person can send a change to an earlier phase's agent. A requirement change goes to the Planner. The pipeline re-runs from that phase: each later agent resumes its own session and revises its existing artifact, and the normal gates apply (EDT-1 to EDT-6).
11. Each exit artifact is saved to PostgreSQL as its stage completes, and is the only input a later stage receives from it (PIP-7). Approved artifacts join the repo's knowledge base. Agents read and write the repo's memory as they work.
12. When the person closes the job, the orchestrator deletes the job namespace and frees the slot.

## Storage

Manifests request storage through a Pathfinder-named StorageClass, so the driver behind it can change without touching the workloads. For Phase 1 that class points at the Azure Disk CSI driver to get running quickly.

| Data | Store | Phase 1 backing |
| --- | --- | --- |
| Orchestrator state: jobs, stage runs, events, comments, logs | PostgreSQL database `pathfinder`, schema `orchestrator` | CloudNativePG on Azure Disk |
| Knowledge base: `plan.md`, HTML mockups, designs, HTML test results, keyed by repository | PostgreSQL database `pathfinder`, schema `memory` | CloudNativePG on Azure Disk |
| Memory: per-repo preference snippets with pgvector embeddings | PostgreSQL database `pathfinder`, schema `memory` | CloudNativePG on Azure Disk |
| Agent configurations and pipeline, versioned | PostgreSQL database `pathfinder`, schema `orchestrator` | CloudNativePG on Azure Disk |
| Agent skills: versioned skill packages per agent | PostgreSQL database `pathfinder`, schema `orchestrator` | CloudNativePG on Azure Disk |
| Job workspace and agent sessions | PVC in the job namespace, deleted with the job | Azure Disk |

- **Azure Disk CSI.** AKS creates built-in classes for it, such as `managed-csi` (Standard SSD LRS) and `managed-csi-premium` (Premium LRS), and the driver supports volume snapshots ([Microsoft Learn](https://learn.microsoft.com/en-us/azure/aks/azure-disk-csi)). The Pathfinder class uses the same `disk.csi.azure.com` provisioner.
- **One database, two schemas.** CloudNativePG bootstraps one database and generates its credentials. Splitting `orchestrator` and `memory` into separate databases later is a dump and restore.
- **No object store and no backups yet.** Phase 1 artifacts are small text and HTML files, so they can live in PostgreSQL. Losing the whole cluster loses job history in Phase 1. An S3-compatible store comes in when backups or larger files need it.
- **Portability.** Azure Disk is an exception to PLT-9 for Phase 1 only. Moving to Rook-Ceph or Longhorn later means changing the StorageClass, not the Pathfinder manifests.

## Networking and access

Without Jira or GitHub webhooks, Phase 1 has nothing public. All inbound traffic comes from people on the internal network.

| Direction | From | To | Path |
| --- | --- | --- | --- |
| Inbound | Developers on VPN | Web app | Hub VNet peering, Azure internal load balancer, Gateway, internal HTTPRoute |
| Inbound | Developers on VPN | Job preview (`<job-id>.preview.<internal-domain>`) | Azure Private DNS wildcard, Azure internal load balancer, Gateway, per-job HTTPRoute, Service |
| Outbound | Job sandbox | LLM and embedding endpoints | Pod egress |
| Outbound | Job sandbox | MCP servers registered on the job's agents | Pod egress; in-cluster or VNet servers only when a pinned agent uses them |
| Outbound | Job sandbox | Git remote | Pod egress; clone, fetch and push only |
| In-cluster | Job runner | Orchestrator API | Cluster Service, authenticated with a per-job token |
| In-cluster | Orchestrator | PostgreSQL | Cluster Service; job namespaces are blocked from PostgreSQL by NetworkPolicy |

- **Internal load balancer.** On AKS a `LoadBalancer` Service becomes internal-only with the annotation `service.beta.kubernetes.io/azure-load-balancer-internal: "true"` ([Microsoft Learn](https://learn.microsoft.com/en-Us/azure/aks/internal-lb)). Envoy Gateway generates that Service, so the annotation is set on the `EnvoyProxy` resource (`spec.provider.kubernetes.envoyService.annotations`) through a patch in the AKS overlay ([Envoy Gateway docs](https://gateway.envoyproxy.io/docs/tasks/operations/customize-envoyproxy/)).
- **Gateway controller.** Envoy Gateway v1.10, installed from its pinned release `install.yaml`. Its install includes the Gateway API CRDs plus Envoy Gateway's own CRDs. Pathfinder routes use only standard-channel Gateway API kinds (`GatewayClass`, `Gateway`, `HTTPRoute`), and `EnvoyProxy` is the one Envoy-specific object. ingress-nginx is retired and ruled out ([Kubernetes blog](https://www.kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/)).
- **No Azure routing add-on or managed Gateway API.** AKS's application routing add-on (managed NGINX) is opt-in, enabled with `--enable-app-routing` or `az aks approuting enable` ([Microsoft Learn](https://learn.microsoft.com/en-us/azure/aks/app-routing)). AKS also offers managed Gateway API CRDs (`--enable-gateway-api`) and an Istio-based Gateway API implementation ([Microsoft Learn](https://learn.microsoft.com/azure/aks/managed-gateway-api)). The Terraform leaves all of these off. The managed CRDs are the same upstream API, but AKS would own their version and doesn't support self-managed implementations like Envoy Gateway. Pathfinder installs the CRDs itself, so routing moves unchanged when it leaves AKS.
- **Git.** Jobs clone and push over standard git (HTTPS or SSH), so any git host works. Each job's git credential is a token or SSH key in its namespace Secret.
- **Web app sign-in.** No login in Phase 1. Access is limited to people on the VPN, since nothing is exposed outside the internal network.
- **Private cluster.** The AKS API server is private. The cluster VNet is peered to the existing hub VNet that VPN users connect through. Terraform, including the Flux bootstrap, runs from a VPN-connected machine.

## Deployment

Terraform builds the Azure infrastructure and bootstraps Flux in the same run. From then on, Flux keeps everything inside the cluster in sync with a Git repository.

| Layer | Tool | What it manages |
| --- | --- | --- |
| Azure infrastructure | Terraform with the `azurerm` provider | Resource group, VNet and subnets, peering to the hub VNet, the private AKS cluster (`azurerm_kubernetes_cluster`) and extra node pools (`azurerm_kubernetes_cluster_node_pool`), Azure Container Registry, Private DNS zone for previews |
| GitOps bootstrap | Terraform with the Flux provider (`flux_bootstrap_git`) | Installs the Flux controllers and points them at the deployment repo on GitHub (SSH deploy key) |
| Cluster add-ons | Flux | Envoy Gateway, agent-sandbox, CloudNativePG, from pinned upstream release YAML committed to the repo |
| Pathfinder services | Flux | Web app, orchestrator, PostgreSQL cluster, StorageClass, Gateway and routes, platform Secrets (SOPS-encrypted) |
| Job namespaces | Orchestrator at runtime | Created and deleted per job; not managed by Flux |

**Bootstrap order**

1. `terraform apply`, run from a VPN-connected machine, creates the AKS cluster and bootstraps Flux against the deployment repo.
2. Flux installs the cluster add-ons.
3. Flux applies the Pathfinder services from the AKS overlay, once the add-ons are ready.
4. Later changes, including Flux upgrades, go through Git pushes instead of direct cluster access ([Flux docs](https://fluxcd.io/docs/installation/)).

**Repository layout**

| Path | Contents |
| --- | --- |
| `infra/` | Terraform for Azure and the Flux bootstrap |
| `clusters/aks/` | Flux bootstrap path and the Flux Kustomizations (add-ons, then platform) |
| `deploy/base/` | Plain Kubernetes YAML for every Pathfinder component and the vendored add-ons, with no Azure settings |
| `deploy/overlays/aks/` | Kustomize patches for AKS only: the internal load balancer annotation, the StorageClass provisioner, and the ACR image registry |
| `deploy/overlays/kind/` | Local test overlay |
| `services/` | Orchestrator, job runner and preview proxy (Go); web app (React and TypeScript) |
| `images/` | Dev container image (Node.js and TypeScript toolchain, plus the runner) |
| `hack/` | Scripts |

The deployment repo lives on GitHub, but Flux's generic bootstrap works with any Git server ([Flux docs](https://fluxcd.io/docs/installation/)). Kustomize works on plain Kubernetes YAML and is built into kubectl, so the base stays valid YAML and a future overlay for another cluster swaps only the Azure-specific patches.

**Why Flux.** Flux and Argo CD are both CNCF graduated and Apache 2.0 ([WZ-IT](https://wz-it.com/en/knowledge/kubernetes/argo-cd-vs-flux/)). Flux was chosen because its Terraform provider bootstraps it in the same `terraform apply` as the cluster ([Flux Terraform provider](https://github.com/fluxcd/terraform-provider-flux)). The trade-off is no built-in dashboard; sync status comes from the `flux` CLI.

## Open questions

- [ ] Which agent harness runs the agents inside the dev container? It must support saving and resuming sessions (PIP-11), MCP tools, and per-agent system prompts and tool allowlists (AGT-4).
- [ ] Model endpoint for Claude Opus and Sonnet: to be provided.
- [x] Which agents use Opus and which use Sonnet? Opus for the Planner and Designer, Sonnet for the Implementer and Tester. These are the seeded defaults; each agent's model is editable in the web app.
- [x] Is the agent set fixed? No. Agents and the pipeline are configuration, edited on the Agents page (AGT-1 to AGT-10).
- [ ] Who may add or change agents, skills and MCP servers, given there is no login in Phase 1?
- [ ] Which embedding model does memory search use?
- [ ] Hub VNet details, the internal DNS domain for previews, and the GitHub repo for Flux.
