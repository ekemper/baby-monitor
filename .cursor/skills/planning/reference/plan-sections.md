# Plan sections template

Every planning doc must include these sections in this order. If a section would be empty, write "N/A" with a one-line reason — never omit a section.

---

## Summary / goal

One short paragraph: what we're building and why it matters.

## Scope

- **In scope** — numbered list of what this plan delivers
- **Out of scope** — what is explicitly deferred or excluded
- **Dependencies** — what must already exist or be true for this plan to work

## Approach

High-level strategy: phases, milestones, or workflow. No vague hand-waving; each step should be actionable. Structure as discrete, independently validated phases. For each phase: (1) show the user what changed, (2) ask whether to continue.

## Technical implementation detail

Enough concrete detail that an implementing agent can proceed without guessing. Include:

1. **Layout** — repository and directory structure; key files and modules
2. **Data and APIs** — storage schemas or document shapes; exact API contracts (paths, request/response bodies, status codes)
3. **Data flow** — step-by-step flow for critical paths (user action → backend → persistence → response)
4. **Integrations** — how external services are called, how responses are parsed, where secrets live (env vars only)
5. **Frontend integration** — which components to touch, how they connect to the backend

Cross-reference this section from the approach so each phase points to the relevant spec.

## Risks & mitigations

Known risks, unknowns, or trade-offs; what we'll do if they materialize. Be honest — performative risk sections are worse than none.

## Open decisions

Anything that must be decided before or during implementation. Link to questions doc where relevant. If all decisions were resolved during the collaborative design session, write: "All decisions resolved during design. See approach for rationale."

## Dependency graph (complex plans with parallelization)

If the plan has work streams that can run in parallel, include a dependency graph before the deliverables manifest. This tells the implementing agent what can be launched as parallel sub-agents.

Structure:

1. **Parallel tracks** — named work streams that can execute simultaneously. Each track lists its deliverables and what interface contracts it depends on.
2. **Interface contracts** — the agreed boundaries between tracks. Defined before any track starts, so parallel sub-agents can build against them independently. Each contract specifies the exact shape (API endpoint + request/response, schema, file format, function signature).
3. **Sync points** — where all tracks must complete before the next phase or batch of tracks can start.

Example format:

```markdown
## Dependency Graph

### Interface contracts (define before parallel work begins)
- **Research API contract:** `POST /api/research` returns `{ run_id, status }`, `GET /api/research/{id}/status` returns `{ status, agents: [...] }`
- **Fixture schema:** `testing/e2e/fixtures/research/*.md` — one markdown file per research agent output

### Phase 1 — Foundation (parallel tracks)

Track A: Backend service [sub-agent: generalPurpose]
  - Items 1, 2, 3 from manifest
  - Depends on: none
  - Produces: Research API contract (implementation)

Track B: Frontend mock mode [sub-agent: generalPurpose]
  - Items 4, 5 from manifest
  - Depends on: Research API contract (shape only, not implementation)
  - Produces: Mock mode toggle, header injection

Track C: Test fixtures [sub-agent: shell]
  - Items 6, 7 from manifest
  - Depends on: Fixture schema (shape only)
  - Produces: Fixture files on disk

**Sync point:** All tracks complete → verify integration → proceed to Phase 2
```

If the plan has no parallelizable work, omit this section.

## Deliverables manifest

A numbered checklist of every concrete artifact the plan produces. Each entry:

1. Operation: **NEW**, **MOD**, or **DELETE**
2. Exact file path relative to repo root (in backtick code formatting)
3. One-line description of what it contains or why it changes
4. **Track** (if parallelized): which track this item belongs to

Group by phase if the plan has phases. Within each phase, group by track if the phase has parallel tracks. This manifest is the **contract between the planning agent and the implementing agent**. The implementing agent uses it as its primary task list and must produce every item.

If a deliverable is ambiguous, the implementing agent must ask for clarification before substituting a different artifact. See the [manifest example](deliverables-manifest-example.md) for formatting.

At the bottom of the manifest, add:

```
**Implementation protocol:** The implementing agent must follow the `plan-implementation` cursor rule when executing this plan.
```
