# Pathfinder AI Dev — Architecture

Nov 16, 2026 · @Grant Terris · Draft (revised Nov 16 and Nov 17, 2026: decisions from `docs/phase1-plan.md`, upstream fact checks)

## Overview

This is a first draft of how Pathfinder AI Dev maps onto Kubernetes. Shared services run in one namespace, monitoring agents run as scheduled jobs in another, and each active ticket gets its own namespace with a single sandbox pod. All add-ons are installed by the team, with no cloud-provider-specific features (PLT-9, PLT-10).

&#91;embedded content: Proposed cluster layout · shared services, monitors, and one namespace per active ticket\]

## Components

Every component below is a proposal; the requirement IDs refer to the requirements doc.

| Namespace | Component | Kubernetes objects | Purpose | Requirements |
| --- | --- | --- | --- | --- |
| Gateway (shared) | Gateway | Gateway with a public and an internal listener, from Envoy Gateway; Gateway API CRDs installed by the team, not the cloud provider | Single entry point for all inbound traffic | PLT-9, PLT-10 |
| glados-system | Webhook receiver | Deployment, Service, public HTTPRoute | Receives Jira and GitHub webhooks and hands events to the orchestrator | LIF-1, INT-7 |
| glados-system | Orchestrator | Deployment, Service | Holds the queue, tracks stages, approvals, revisions and re-runs, creates and removes ticket namespaces, serves the REST API for the web app and ticket runners, builds each ticket's state machine from its pinned pipeline, stores agent configurations, the pipeline, skills, knowledge base and memory | PLT-7, PLT-8, LIF-6, LIF-7, PIP-3, PIP-4, PIP-9, EDT-1 to EDT-6, AGT-5 to AGT-10 |
| glados-system | Status web app | Deployment, Service, internal HTTPRoute | Status view, queue, reviews, agent test/debug tool, Agents page (add, edit and delete agents, their configuration and skills, and the pipeline), Memory and Knowledge base pages | WEB-1 to WEB-6, AGT-1 to AGT-10, SKL-1 to SKL-7 |
| glados-system | Knowledge base and memory | PostgreSQL Cluster (CloudNativePG `standard` image, which includes pgvector), plus an object store bucket for larger files | Per-repo knowledge base of approved artifacts (list and read) and per-repo memory snippets that agents read and write, searched by embedding similarity; both outlive ticket containers | MEM-1 to MEM-8 |
| glados-system | Agent and pipeline store | PostgreSQL | Versioned agent configurations (system prompt, endpoint and model, tools and MCP servers, input and exit artifacts, limits), the versioned pipeline, and versioned skill packages per agent, all managed from the web app | PLT-5, PLT-6, AGT-1 to AGT-10, SKL-1 to SKL-7 |
| glados-monitors | Monitoring agents | One CronJob per monitor | Check a source on a schedule and open Jira tickets for human review | MON-1 to MON-7 |
| Per ticket | Ticket sandbox | One `Sandbox` (agent-sandbox CRD, `agents.x-k8s.io/v1beta1`) = one pod with three containers: dev container (ticket runner and agent harness), listener agent, preview proxy | Runs the dev environment and every agent in the ticket's pinned pipeline | LIF-3, LIF-4, LIF-5, PRV-1 |
| Per ticket | Workspace volume | PersistentVolumeClaim, from the Sandbox's `volumeClaimTemplates` | Keeps the repo checkout, artifacts and each agent's saved session between stages | LIF-4, PIP-11 |
| Per ticket | Preview routing | ClusterIP Service (created by the orchestrator; a Sandbox only creates a headless Service when `spec.service: true`), internal HTTPRoute | Exposes the preview proxy on the internal listener only | PRV-1, PRV-2 |
| Per ticket | Credentials | Secrets scoped to the ticket namespace | Jira, GitHub, LLM and embedding keys, credentials for the pinned agents' MCP servers, and the runner's API token for that ticket | Phase 1: copied from SOPS-encrypted platform Secrets |

## Traffic

Inbound traffic splits into a small public surface for webhooks and an internal-only surface for people.

| Direction | From | To | Path | Exposure |
| --- | --- | --- | --- | --- |
| Inbound | Jira, GitHub | Webhook receiver | Gateway public listener, public HTTPRoute | Public, webhook route only |
| Inbound | Developers | Status web app | Gateway internal listener, internal HTTPRoute | Internal only |
| Inbound | Developers | Ticket preview proxy | Gateway internal listener, per-ticket HTTPRoute, Service | Internal only |
| Outbound | Ticket sandbox | LLM providers | Pod egress | Per-agent model configuration |
| Outbound | Ticket sandbox | MCP servers registered on agents | Pod egress | Opened per ticket only for MCP servers its pinned agents use (AGT-3) |
| Outbound | Listener agent, monitoring agents | Jira and GitHub APIs | Pod egress | Comments, PR links, new tickets |
| In-cluster | Ticket runner | Orchestrator API (artifacts, knowledge base, memory, skills) | In-cluster Service | Cluster only; ticket namespaces never connect to PostgreSQL directly |

If Jira and GitHub are cloud-hosted, their webhooks have to reach the cluster from the internet, so the public listener should carry nothing but the webhook route. How the Gateway itself is exposed without a cloud load balancer is still open: a `LoadBalancer` Service depends on the environment's load balancer provider, which is cloud-specific on EKS and AKS ([Kubernetes docs](https://kubernetes.io/docs/tasks/access-application-cluster/create-external-load-balancer/)).

## Ticket sandbox lifecycle

The orchestrator owns every ticket namespace from creation to deletion.

1. A Jira webhook reports that a ticket was assigned to the team and pulled into the sprint (LIF-1).
2. The orchestrator queues the ticket if 10 sandboxes are already active (LIF-7).
3. When a slot is free, it creates the ticket namespace, Secrets, workspace volume, `Sandbox`, Service and internal HTTPRoute.
4. The pod clones the ticket's repo into the workspace volume and builds its dev environment.
5. The agents in the ticket's pinned pipeline run in the same pod across all stages; the listener agent and preview proxy stay up the whole time (LIF-4, LIF-5). Each agent's session is saved in the workspace volume, so it can resume to revise its artifact (PIP-9, EDT-5).
6. Each exit artifact is sent to the orchestrator as its stage completes (MEM-1); approved artifacts join the repo's knowledge base.
7. When the Jira ticket closes, the orchestrator deletes the namespace and everything in it, which frees a slot (LIF-6).

Agent Sandbox can suspend an idle sandbox and resume it later: setting `spec.operatingMode: Suspended` terminates the pod but keeps the Sandbox and its volumes, and `Running` recreates the pod ([API reference](https://agent-sandbox.sigs.k8s.io/docs/api/)). That suits tickets that wait days for a human approval. Whether a suspended sandbox still counts against the 10-ticket limit is a design decision below; Phase 1 doesn't suspend sandboxes.

## Storage

All persistent data lives on volumes from a CSI driver the team installs and runs inside the cluster, so nothing depends on a cloud disk or database service (PLT-9, PLT-10). The node VMs still need raw disks attached; the CSI driver turns those into replicated volumes.

&#91;embedded content: Proposed storage layers · data, data services, CSI, node disks\]

| Data | Store | Lifetime |
| --- | --- | --- |
| Orchestrator state: queue, stage and approval per ticket | PostgreSQL, `orchestrator` database | Permanent |
| Knowledge base: approved plans, designs, artifact metadata | PostgreSQL, `memory` database, keyed by repo | Permanent, outlives tickets (MEM-2) |
| Memory: per-repo preference snippets | PostgreSQL, `memory` database, with pgvector embedding columns for similarity search | Permanent, editable in the web app (MEM-8) |
| Knowledge base files: HTML mockups, HTML test results | Object store bucket, referenced from the `memory` database (Phase 1 keeps them in PostgreSQL) | Permanent |
| Agent skills | PostgreSQL, versioned per agent | Permanent |
| Ticket workspace: repo checkout, build output | PVC in the ticket namespace | Deleted when the ticket closes (LIF-6) |
| PostgreSQL backups | Object store | Per retention policy |

**PostgreSQL.** CloudNativePG defines a `Cluster` resource with one primary and optional replicas, and keeps the Service pointed at the primary through failovers ([CloudNativePG docs](https://cloudnative-pg.io/documentation/1.24)). It supports continuous WAL archiving and backups to S3-compatible object stores, plus volume-snapshot backups where the storage class supports them. Object-store backups now go through the Barman Cloud Plugin ([backup docs](https://cloudnative-pg.io/documentation/preview/backup)).

**Memory search.** pgvector adds exact and approximate nearest-neighbour search to Postgres and uses the WAL, so embeddings get the same replication and point-in-time recovery as the rest of the database ([pgvector](https://github.com/pgvector/pgvector)). CloudNativePG's `standard` images include it ([postgres-containers](https://github.com/cloudnative-pg/postgres-containers)). That keeps memory in one system instead of adding a separate vector database. Anthropic doesn't offer an embedding model ([docs](https://platform.claude.com/docs/en/build-with-claude/embeddings)), so the embedding model is configured separately.

**CSI driver.** Two candidates:

|  | Rook-Ceph | Longhorn |
| --- | --- | --- |
| Maturity | CNCF graduated ([CNCF](https://www.cncf.io/announcements/2020/10/07/cloud-native-computing-foundation-announces-rook-graduation/)) | CNCF incubating ([GitHub](https://github.com/longhorn/longhorn)) |
| Provides | Block volumes, shared filesystem, and S3-compatible object storage through Ceph RGW ([Rook](https://rook.io/docs/rook/v1.11/Getting-Started/intro/)) | Block volumes replicated synchronously across nodes; backups to NFS or S3 ([Longhorn](https://github.com/longhorn/longhorn)) |
| Object store | Built in (RGW) | Needs a separate one |
| Trade-off | One system for volumes and objects; more to operate | Simpler to run; one more component for objects |

If Longhorn is chosen, the object store needs its own project. Avoid MinIO: its community repository was archived in 2026 after moving to maintenance mode ([TuxCare](https://tuxcare.com/blog/minio-els/)). SeaweedFS, Garage and Ceph RGW are the usual replacements.

## Cluster components

Each cluster add-on is installed and run by the team (PLT-10). Only the sandbox CRD has a working pick so far.

| Need | Candidate | Notes |
| --- | --- | --- |
| Ticket sandboxes | Agent Sandbox (`kubernetes-sigs/agent-sandbox`) | `Sandbox` CRD for a single stateful pod with stable identity and storage; now `agents.x-k8s.io/v1beta1` (release v1.0.2), under SIG Apps ([repo](https://github.com/kubernetes-sigs/agent-sandbox)) |
| Sandbox isolation | gVisor or Kata Containers | Agent Sandbox supports both runtimes for running untrusted, LLM-generated code |
| Routing | Envoy Gateway (chosen) | Kubernetes recommends Gateway over the frozen Ingress API ([docs](https://kubernetes.io/docs/concepts/services-networking/ingress-controllers)); avoid ingress-nginx, retired in March 2026 ([announcement](https://www.kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/)) |
| Gateway exposure | Phase 1: Azure internal load balancer (an explicit PLT-9 exception); later to choose | Cloud load balancers are ruled out by PLT-9; bring-your-own-node setups typically use a controller such as MetalLB ([Avisi Cloud](https://docs.avisi.cloud/docs/product/overview/kubernetes/load-balancers)), not yet verified on EC2 or Azure VMs |
| Persistent volumes (CSI) | Rook-Ceph or Longhorn | See Storage |
| PostgreSQL | CloudNativePG operator with pgvector | Orchestrator state and memory; see Storage |
| Object store | Ceph RGW (with Rook-Ceph), or SeaweedFS or Garage (with Longhorn) | Memory files and Postgres backups; not MinIO |
| Dev environment build | DevPod Kubernetes provider (option) | Builds a workspace pod from a repo's `devcontainer.json`, including in-cluster builds ([DevPod](https://github.com/loft-sh/devpod)) |
| Docker inside dev containers | Sysbox, or Kata via Agent Sandbox | Sysbox avoids privileged pods but does not match VM-level isolation ([Sysbox](https://github.com/nestybox/sysbox)) |
| Agent harness | To choose | Runs the configured agents inside the dev container; must save and resume sessions (PIP-11), support MCP tools, and accept a per-agent system prompt, model and tool allowlist (AGT-4) |
| Secrets management | Phase 1: SOPS + age, decrypted by Flux | Ticket-scoped credentials copied into each ticket namespace |

## Open design decisions

- [x] Managed control plane (EKS or AKS) or self-managed (k3s or kubeadm on VMs)? Phase 1: AKS, private API server.
- [ ] How is the Gateway exposed without a cloud load balancer, and how are the public and internal listeners kept apart?
- [ ] Do Jira and GitHub push webhooks to a public route, or does the system poll them so nothing is public?
- [ ] Does a suspended sandbox still count against the 10-ticket limit? (Phase 1 doesn't suspend sandboxes; every open job counts.)
- [ ] Do the listener agent and preview proxy run as containers in the ticket pod, as drawn, or as separate pods?
- [ ] Which network policies limit what ticket pods can reach (other tickets, the cluster API, the internet)?
- [ ] Rook-Ceph or Longhorn for persistent volumes?
- [ ] Where do backups go so they survive losing the cluster? An in-cluster object store does not, and cloud object storage would conflict with PLT-9.
- [x] How many PostgreSQL instances (one primary, or a primary plus replicas)? Phase 1: a primary plus one replica.
