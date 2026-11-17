# clusters/aks

Flux bootstrap path for the AKS cluster. Terraform's `flux_bootstrap_git` resource (M2)
writes the Flux controller manifests into `flux-system/` here. **This path can't be changed
after bootstrap**, so don't move or rename this folder.

Flux Kustomizations defined here, applied in order:

| File | Syncs | Depends on | Milestone |
| --- | --- | --- | --- |
| `addons.yaml` | `deploy/overlays/aks/addons` (Envoy Gateway, agent-sandbox, CloudNativePG) | — | M3 |
| `platform.yaml` | `deploy/overlays/aks/platform` (Pathfinder services) | `addons` | M4 |

Per-job namespaces are created at runtime by the orchestrator, never by Flux.
