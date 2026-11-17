# GLaDOS AI Dev

## Source of truth

Read these before changing anything. Requirement IDs (PLT-, LIF-, PIP-, EDT-, MON-, WEB-, …) come from the requirements doc.

1. `docs/GLaDOS AI Dev — Phase 1 MVP HLD.md`: **what we build now; it decides scope.** Anything it marks "Later" or "Deferred" is out of scope.
2. `docs/GLaDOS AI Dev — Requirements.md`: the full target system.
3. `docs/GLaDOS AI Dev — Architecture.md`: how the full system maps onto Kubernetes.
4. `docs/phase1-plan.md`: milestone plan, plus the resolutions agreed for conflicts between the docs.

If the docs conflict, don't pick a side on your own. Raise it.

## Hard rules

- Everything in the cluster is plain Kubernetes API YAML, organized with Kustomize:
  `deploy/base/` (no cloud-specific settings) and `deploy/overlays/aks/` (only the Azure-specific
  patches: internal LB annotation, StorageClass provisioner, ACR image registry rewrite). No Docker
  Compose. No Helm charts of our own. Upstream add-ons are vendored, pinned release YAML.
- No cloud-provider-specific Kubernetes features beyond what the AKS overlay holds (PLT-9). Do not
  enable the AKS application routing add-on, AKS managed Gateway API CRDs, or AKS's Gateway API
  implementation. Routing uses Envoy Gateway with the Gateway API.
- Infrastructure is Terraform (`azurerm` provider). Flux is bootstrapped from Terraform with the Flux
  provider (`flux_bootstrap_git`) and syncs the AKS overlay. Per-job namespaces are created at runtime
  by the orchestrator, not by Flux.
- The orchestrator is a deterministic state machine. It never calls an LLM. No agent starts, calls or
  manages another agent (PIP-8).
- State passes between stages only through saved exit artifacts (PIP-7).
- Agents and the pipeline are versioned configuration (AGT-1 to AGT-10): system prompt, model, skills, tools and
  MCP servers per agent; stages with gate, skip and failure-route settings. No agent name is hard-coded in the
  orchestrator, runner or stub runtime. Planner, Designer, Implementer and Tester exist only as seed data.
- Phase 1 has no Jira or GitHub API integration. Jobs are started from the web app. Agents use plain
  git (HTTPS or SSH) to clone, commit, and push to a new branch per job. Git credentials live in the
  job namespace Secret.
- Access is VPN only; no web app login in Phase 1. Nothing is public.
- The agent harness and LLM endpoint are not chosen yet: the harness sits behind the `AgentRuntime`
  interface; endpoint, credentials and model per agent are configuration only.

## Repository layout (from the HLD Deployment section)

| Path | Contents |
| --- | --- |
| `infra/` | Terraform for Azure and the Flux bootstrap |
| `deploy/base/` | Plain Kubernetes YAML for every GLaDOS component, with no Azure settings |
| `deploy/overlays/aks/` | Kustomize patches for AKS only: internal LB annotation, StorageClass provisioner |

Approved additions:

| Path | Contents |
| --- | --- |
| `clusters/aks/` | Flux bootstrap path and the Flux Kustomizations (addons, then platform) |
| `deploy/overlays/kind/` | Local test overlay (no Azure settings) |
| `services/` | `orchestrator`, `runner`, `preview-proxy` (Go); `webapp` (React + TypeScript) |
| `images/` | Dev container image (Node.js/TypeScript toolchain + runner) |
| `hack/` | Scripts (add-on vendoring, portability check, load test) |

## Commands

- `make validate`: portability check on `deploy/base/`, builds every overlay, schema-validates the output
  with a pinned kubeconform (downloaded to `.bin/`). Add new overlays to `OVERLAYS` in the Makefile.
- `make test`: repo self-tests.

## Working rules

- When you cite how a tool or API works, check its current docs first. Pin every upstream version.
- Stop for approval at the end of each milestone in `docs/phase1-plan.md`.
