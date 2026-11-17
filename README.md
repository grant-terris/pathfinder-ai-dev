# Pathfinder AI Dev

A shared pool of AI agents (Planner, Designer, Implementer, Tester) that take a job from
written requirements to tested code on its own git branch, with a human reviewing every
artifact. Phase 1 runs on Azure AKS and is driven from an internal web app.

## Documents

- [Requirements](docs/Pathfinder%20AI%20Dev%20—%20Requirements.md): the full target system
- [Architecture](docs/Pathfinder%20AI%20Dev%20—%20Architecture.md): how it maps onto Kubernetes
- [Phase 1 MVP HLD](docs/Pathfinder%20AI%20Dev%20—%20Phase%201%20MVP%20HLD.md): what's being built now
- [Phase 1 plan](docs/phase1-plan.md): decisions log and milestones

## Layout

| Path | Contents |
| --- | --- |
| `infra/` | Terraform for Azure and the Flux bootstrap |
| `clusters/aks/` | Flux bootstrap path and Flux Kustomizations |
| `deploy/base/` | Plain Kubernetes YAML, no cloud-specific settings |
| `deploy/overlays/aks/` | Azure-only patches |
| `deploy/overlays/kind/` | Local test cluster overlay |
| `services/` | Orchestrator, runner, preview proxy (Go); web app (React) |
| `images/` | Dev container image |
| `hack/` | Scripts |

## Checks

Requires `kubectl`, `curl` and `make`. Other tools are downloaded, pinned, into `.bin/`.

```bash
make validate   # portability check, build every overlay, schema-validate the output
make test       # repo self-tests
```
