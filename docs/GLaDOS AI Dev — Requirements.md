# GLaDOS AI Dev — Requirements

Nov 16, 2026 · @Grant Terris

## Overview

GLaDOS AI Dev is a cloud-hosted service that runs a shared pool of specialized AI agents against Jira tickets. Each ticket gets its own long-running dev container, and a configurable pipeline of agents takes it from human-written requirements to a reviewed GitHub PR, with a human approving the plan and the design before work moves on. The default pipeline has four agents (Planner, Designer, Implementer, Tester); people can add, change and remove agents, and edit each agent's system prompt, model, skills and tools.

**In scope**

- Jira-triggered, per-ticket dev containers with an always-listening agent
- A configurable agent pipeline with human approval gates (four agents by default)
- Per-agent configuration: system prompt, model, skills and tools
- Jira and GitHub comments as the main way people interact with agents
- Internal preview links for plans, mockups, running web apps and test results
- Per-repo memory built from saved artifacts and preferences

**Out of scope**

- Agent harnesses installed on developer machines
- Use by Vienta Tech; this tool is for a separate organization
- Ticket intake: requirements are written by humans in Jira

## Platform and hosting

The service runs on Kubernetes in AWS or Azure and is defined entirely as Dockerfiles and Kubernetes API YAML, so it can move between cloud providers.

| ID | Requirement |
| --- | --- |
| PLT-1 | The main service runs on a Kubernetes cluster hosted on AWS or Azure. |
| PLT-2 | All services and dev containers are defined with Dockerfiles and Kubernetes API YAML manifests; Docker Compose is not used and no provider-specific services are required. |
| PLT-3 | No agent harness or app is installed on developer machines. |
| PLT-4 | A shared pool of agents serves all developers. |
| PLT-5 | Each agent's LLM model is configured independently; the system is not tied to one LLM vendor. |
| PLT-6 | Each agent has its own system prompt, skills and tools, set in its configuration in the web app (AGT-1 to AGT-10, SKL-1 to SKL-7). |
| PLT-7 | The system can be controlled through a REST API. |
| PLT-8 | Up to 10 tickets start automatically and run concurrently; further tickets are queued until a slot frees up. A person can start a queued ticket immediately with "Start now", even when 10 are already running; automatic starts resume only once fewer than 10 are running. |
| PLT-9 | No cloud-provider-specific Kubernetes features or add-ons are used (for example managed ingress or load balancer controllers). |
| PLT-10 | Every cluster service and CRD the system needs (traffic routing, sandboxing, storage, secrets) is installed and managed by the team. |

## Ticket lifecycle

A run starts when a Jira ticket is assigned to the team and pulled into the sprint, and its container lives until the ticket closes.

| ID | Requirement |
| --- | --- |
| LIF-1 | A run starts when a Jira ticket is assigned to the team and pulled into the sprint. |
| LIF-2 | Each ticket works in exactly one GitHub repo. |
| LIF-3 | Each ticket gets one dev container with the repo's development environment. |
| LIF-4 | The container is long-running and is reused for every stage of that ticket. |
| LIF-5 | Each container runs an always-on agent that listens for Jira and GitHub comments on its ticket. |
| LIF-6 | The container is torn down when the Jira ticket is closed. |
| LIF-7 | When 10 tickets are active, new tickets wait in a queue and start in order as slots free up, unless a person starts one immediately (PLT-8). |

## Agent pipeline

The pipeline is an ordered list of stages, each run by one agent, and each producing an exit artifact that later stages start from. The stage list is configuration (AGT-5): people can add, remove and reorder stages. The default pipeline below has four stages. In it, a human approves the plan, the design and, after testing, the finished work. The Tester starts automatically once the Implementer finishes. The Planner decides whether a ticket needs the Designer at all. A human can deny any artifact with comments, and the agent that produced it takes another turn.

Default pipeline:

| Stage | Agent | Exit artifact | Delivered via |
| --- | --- | --- | --- |
| 1 | Planner | `plan.md`: spec and task breakdown, plus whether design is needed and why | Jira comment linking to the internal preview |
| 2 | Designer (skipped when the Planner decides design isn't needed) | HTML design mockups; architecture or API design | Jira comment linking to the internal preview |
| 3 | Implementer | Branch and pull request | Jira comment with the GitHub PR link |
| 4 | Tester | Added tests, HTML test results, pass/fail | GitHub PR comment linking to the internal preview |

| ID | Requirement |
| --- | --- |
| PIP-1 | The pipeline is a configurable, ordered list of stages, each run by one agent (AGT-5). The default pipeline is Planner, Designer, Implementer and Tester. |
| PIP-2 | Each stage's agent produces an exit artifact; later stages that declare it as an input receive it. |
| PIP-3 | Each stage has a configurable human approval gate. When it is on, a human approves the stage's artifact before the next stage starts; when it is off, the next stage starts automatically. After the last stage, a human always gives a final approval. Default: gates after the Planner and Designer, none between the Implementer and Tester, then the final approval of the implementation and tests. |
| PIP-4 | Approval is a Jira status transition. |
| PIP-5 | A stage can be configured to send a failure back to an earlier stage automatically, at most N times in a row; after that the work pauses and goes to a human. Default: when the Tester finds a code bug, the work loops back to the Implementer, at most 3 times. |
| PIP-6 | When an agent hits a requirements question, the work pauses and the question goes to a human. |
| PIP-7 | State passes between stages only through saved exit artifacts; agents do not hand off state any other way. An agent's own session history stays within its stage: it is reused when that agent revises its artifact, and is never passed to another stage. |
| PIP-8 | Stages are sequenced by a deterministic orchestrator, not an LLM; no agent starts, calls or manages another agent. |
| PIP-9 | A human can approve or deny any agent's artifact (plan, design, implementation, tests) with comments. On a denial, the agent that produced it takes another turn in its existing session, with the comments as input. |
| PIP-10 | A stage can be marked skippable. An earlier stage with an approval gate can decide to skip it, recording the decision and its reason in its exit artifact; the decision is approved along with that artifact, and the orchestrator skips the stage. Default: the Planner decides whether a ticket needs the Designer. |
| PIP-11 | The agent harness must be able to save an agent's session and resume it later, for revisions (PIP-9) and re-runs (EDT-5). |

## Agent configuration

The set of agents is modular. People add, change and remove agents from the web app, and each agent is defined entirely by its configuration: no code change, image build or deployment is needed. Every agent runs inside the ticket's sandbox container. The four default agents ship as editable configurations, not as special cases.

| ID | Requirement |
| --- | --- |
| AGT-1 | People can add, view, edit and delete agents from the web app. Planner, Designer, Implementer and Tester are seeded as ordinary, editable and deletable agents. |
| AGT-2 | Each agent has a configuration: name and description, system prompt, LLM endpoint and model, skills (SKL-1 to SKL-7), tools (AGT-3), the artifacts it reads, the exit artifact it produces, and run limits (time and turns per run). |
| AGT-3 | An agent's tools are an allowlist over the harness's built-in tools (for example shell, file editing, web fetch) and the GLaDOS tools (knowledge base, memory). An agent can also use additional MCP servers registered by URL; each one must be reachable from the cluster, and its network access is opened for that agent's sandbox only. |
| AGT-4 | Agents are defined independently of any harness. The harness adapter maps an agent's configuration to the harness; a configuration the harness can't honour (for example an unknown built-in tool) is rejected when it is saved. |
| AGT-5 | The pipeline is configured in the web app as an ordered list of stages. For each stage: which agent runs it, whether it has an approval gate (PIP-3), whether it is skippable (PIP-10), and an optional failure route back to an earlier stage with a retry limit (PIP-5). An agent runs at most one stage. |
| AGT-6 | A pipeline is saved only if it is valid: it has at least one stage, every artifact a stage reads is produced by an earlier stage, failure routes point to earlier stages, and only stages with a gate can skip later ones. An agent that the pipeline uses can't be deleted until it is removed from the pipeline. |
| AGT-7 | Agent configurations and the pipeline are versioned. Every save creates a new version; earlier versions are kept while any open ticket or job uses them. |
| AGT-8 | A ticket or job uses the pipeline and agent configuration versions current when it started; changes apply to new tickets or jobs only, including re-runs of an existing one. |
| AGT-9 | Each agent run records which agent configuration version it used. |
| AGT-10 | The orchestrator builds each job's state machine from its pinned pipeline. Configuration never lets an agent start, call or manage another agent (PIP-8). |

## Agent skills

People extend what each agent can do by giving it skills: packaged instructions, plus optional scripts and reference files, that the agent can use while it works. Skills are managed per agent in the web app.

| ID | Requirement |
| --- | --- |
| SKL-1 | The web app lists every configured agent (AGT-1), whether or not the pipeline uses it. |
| SKL-2 | Each agent has its own set of skills; a skill belongs to one agent. |
| SKL-3 | People can upload, view, enable or disable, replace and delete an agent's skills from the web app. |
| SKL-4 | Skills use the Agent Skills folder format: a `SKILL.md` with name and description front matter, plus optional scripts and reference files. A skill is uploaded as a `.zip`, or written as a single `SKILL.md` in the browser. |
| SKL-5 | Skills are versioned. Replacing a skill creates a new version; earlier versions are kept while any open ticket or job still uses them. |
| SKL-6 | A ticket or job uses the skill versions that were enabled when it started; skill changes apply to new tickets or jobs only. |
| SKL-7 | Each agent run records which skill versions it used. |

## Edits and re-runs

The system is designed for edits at every phase. Ideally an artifact is edited while its phase is still active, but late changes are expected: a requirement can be added after implementation has started, and the pipeline re-runs from the edited phase through to the end.

| ID | Requirement |
| --- | --- |
| EDT-1 | Each phase's artifact (requirements, plan, design, implementation) can be changed while that phase is active, by denying it with comments (PIP-9). |
| EDT-2 | An earlier phase's artifact can be changed after the pipeline has moved past it, by sending the change to that phase's agent. A requirement change, including one added during implementation or testing, goes to the Planner, which updates the requirements and the plan. |
| EDT-3 | A change to an earlier phase re-triggers the pipeline from that phase and runs every later phase again. |
| EDT-4 | A change to the requirements re-triggers the pipeline from the Planner. |
| EDT-5 | During a re-run, each later agent resumes its own session and revises its existing artifact using the updated input, rather than starting from scratch. |
| EDT-6 | The normal human approval gates (PIP-3) apply to every phase of a re-run. |

**Example:** a ticket is in the Test phase when someone sends a design change to the Designer. The pipeline goes back to Design: the Designer revises its existing design in its own session, and a human approves it. Then the Implementer revises the code, the Tester re-tests, and a human gives the final approval. The plan is kept, because the change came after the Planner's phase.

## Interaction

People work with the agents through Jira until a PR exists, then the conversation moves to GitHub.

| ID | Requirement |
| --- | --- |
| INT-1 | Jira and GitHub comments are the main way people talk to agents. |
| INT-2 | Requirements are written in the Jira ticket by a human. |
| INT-3 | Agents post a Jira comment with the internal link to `plan.md` when planning finishes. |
| INT-4 | Agents post a Jira comment with the internal link to the HTML design mockups when design finishes. |
| INT-5 | Agents post a Jira comment with the GitHub PR link when the PR is ready. |
| INT-6 | After the PR link is posted, the conversation continues in GitHub PR comments. |
| INT-7 | The always-on agent in each container responds to new comments on its ticket and PR. |

## Preview proxy

Each ticket's container exposes an internal-only preview so a human can review artifacts and try changes before merge.

| ID | Requirement |
| --- | --- |
| PRV-1 | Each dev container runs a proxy server that serves previews over a network link. |
| PRV-2 | Previews are reachable from the internal network only. |
| PRV-3 | The proxy serves `plan.md`, HTML design mockups, the running web app, and HTML test results. |
| PRV-4 | Humans can try code changes through the preview before the PR is merged. |
| PRV-5 | Preview links are posted in Jira or GitHub comments as each artifact is ready. |

## Knowledge base and memory

Each repo has two stores that outlive its tickets. The **document knowledge base** holds the repo's approved artifacts, so later agents can read existing plans, designs and mockups and build on them. **Memory** holds short preference snippets, such as "always use react hook form for forms" or "Jon is the manager and prefers gray card backgrounds", which agents read and write on their own, the way a chat assistant's memory works.

| ID | Requirement |
| --- | --- |
| MEM-1 | Each exit artifact is saved when its stage completes. |
| MEM-2 | Saved artifacts and memory are stored per repo and outlive the ticket's container. |
| MEM-3 | The document knowledge base holds each repo's approved plans, HTML mockups, designs and other exit artifacts. |
| MEM-4 | Memory holds short preference snippets for the repo. Snippets are scoped to one repo. |
| MEM-5 | Agents on later tickets in the same repo can list and read the repo's knowledge base. |
| MEM-6 | Agents read and write memory snippets on their own, at any point in their run. Each snippet records the ticket, stage and agent that wrote it. |
| MEM-7 | During each run, an agent retrieves the memory snippets relevant to its work by semantic similarity. The embedding model is configurable. |
| MEM-8 | People can view, edit and delete a repo's memory snippets, and browse its knowledge base, in the web app. |

## Monitoring agents

A separate, modular system runs custom monitoring agents on a schedule. Each one checks a source, such as an application's logs, and opens Jira tickets to investigate problems it finds. A human reviews those tickets before they enter the agent pipeline.

| ID | Requirement |
| --- | --- |
| MON-1 | Monitoring agents run in a system separate from the ticket pipeline. |
| MON-2 | The system is modular: the team can add custom monitoring agents. |
| MON-3 | A monitoring agent can watch any source; application logs are one example. |
| MON-4 | Each monitoring agent runs on its own cron-style schedule. |
| MON-5 | When a monitoring agent finds a problem, it opens a Jira ticket automatically to investigate it. |
| MON-6 | A human reviews every ticket a monitoring agent opens; it enters the pipeline only through the normal trigger (LIF-1). |
| MON-7 | Once in the pipeline, these tickets go through the same stages and human approvals as other tickets. |

## Status and debug web app

An internal web app shows what the system is doing and lets the team test and debug agents. Its detailed scope is still being defined.

| ID | Requirement |
| --- | --- |
| WEB-1 | An internal web app shows the status of the system. |
| WEB-2 | The web app includes a test and debug tool for agents. |
| WEB-3 | The web app is reachable from the internal network only, like previews. |
| WEB-4 | The web app has an Agents page that lists every agent, lets people add, edit and delete agents and manage each agent's configuration and skills, and edit the pipeline (AGT-1 to AGT-10, SKL-1 to SKL-7). |
| WEB-5 | The web app shows the queue, and a person can open any queued entry and start it now (PLT-8). |
| WEB-6 | The web app has a Memory page and a Knowledge base page for each repo (MEM-8). |

## End-to-end flow

&#91;embedded content: GLaDOS AI Dev ticket flow · 4 agents, 3 approval gates\]

The diagram shows the default pipeline and predates the final approval gate and the Planner's design decision. A code bug found by the Tester loops back to the Implementer without a human, up to 3 times. A requirements question from any agent pauses the run for a human. Any artifact can be denied with comments, and its agent takes another turn. Approved artifacts feed the repo's knowledge base, and agents keep the repo's memory up to date as they work.

## Open questions

Checked items were answered on Nov 16, 2026; the answer follows each one.

- [ ] Which Jira statuses mark each approval gate, and who is allowed to make those transitions?
- [ ] Which Jira status does a ticket move to when an agent raises a requirements question?
- [x] Is there a retry limit on the automatic Tester-to-Implementer loop before a human is pulled in? Yes: 3, configurable (PIP-5).
- [x] Does every ticket go through the Designer, or can backend-only tickets skip it? The Planner decides (PIP-10).
- [ ] Is the queue first in, first out, or ordered by Jira priority? Phase 1 is first in, first out, plus manual "Start now" (PLT-8). Jira priority is still open.
- [x] How is "internal only" enforced for previews: VPN, SSO, private network, or a mix? VPN only in Phase 1; SSO is still open for later.
- [ ] Should memory also keep human feedback and rejection reasons, and how long is memory retained?
- [x] How are repo preferences captured: written by humans, learned from feedback, or both? Agents write memory snippets themselves (MEM-6); people can edit or delete them (MEM-8).
- [ ] How are secrets handled (Jira, GitHub and LLM keys, repo credentials) inside each container? Phase 1: a Secret per job namespace, sourced from SOPS-encrypted platform Secrets.
- [ ] How many developers will use the system?
- [ ] Which agent harness runs inside each container? Still open; it must support saving and resuming sessions (PIP-11).
- [x] How does traffic reach the cluster without a cloud load balancer? Phase 1 uses the Azure internal load balancer, as the one AKS-specific exception (see the Phase 1 HLD).
- [x] Which traffic controller implements routing? Envoy Gateway, with the Gateway API CRDs installed by the team rather than the cloud provider.
- [x] How is a backward edit triggered: a Jira status transition back to the edited phase, a comment, or the web app? By sending the change to that phase's agent; requirement changes go to the Planner (EDT-2). Phase 1 does this from the web app.
- [x] Do re-run phases need human approval again under PIP-3? Yes (EDT-6).
- [ ] Are superseded artifacts kept in the knowledge base as earlier versions?
- [ ] Who may add or change agents, skills and MCP servers? An agent's system prompt, skills and tools control what runs in every new container, and Phase 1 has no web app login.
- [x] Is the set of agents fixed? No: agents and the pipeline are configured in the web app (AGT-1 to AGT-10). Answered Nov 17, 2026.
- [ ] Which embedding model does memory search use (MEM-7)?
