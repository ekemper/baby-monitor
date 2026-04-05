# Phase implementation doc template

Use this format for each phase of a complex plan. Each phase doc must be **self-contained** — an implementing agent reads only this doc and can start work without the master plan or other phase docs.

File naming: `plans/<feature-name>-phase-N-IMPL.md` where N is the phase number.

---

## Required sections

### Header block

```markdown
# <Feature name> — Phase N: <Phase title>

**Master plan:** [<feature-name>-PLAN.md](<feature-name>-PLAN.md)
**Phase:** N of M
**Prerequisites:** <what must be true before starting>
**Parallel tracks:** <Yes (N tracks) / No — sequential>
**Estimated scope:** <small / medium / large>
```

The prerequisites line is critical. It tells the implementing agent what prior work must be complete. Examples:
- "Phase 1 must be complete (backend service and API endpoint exist)"
- "None — this phase has no dependencies"
- "Phase 1 and Phase 2 must be complete (mock pipeline + frontend toggle exist)"

### Summary

One paragraph: what this phase delivers and why it matters in the context of the larger feature.

### Context for this phase

Enough background that the implementing agent understands the domain without reading the master plan. Include:
- What the broader feature is (1-2 sentences)
- What prior phases produced (if any) — specific file paths and APIs the agent can inspect
- What this phase adds on top of that

This section replaces the need to read a 500-line master plan. Keep it to the essentials.

### Technical implementation detail

Same structure as a simple plan's technical detail, but scoped to this phase only:
1. **Layout** — files and directories this phase touches
2. **Data and APIs** — schemas, endpoints, contracts relevant to this phase
3. **Data flow** — step-by-step flow for this phase's critical paths
4. **Integrations** — external services or internal modules this phase connects to
5. **Frontend integration** — components this phase touches (if applicable)

### Parallel tracks and interface contracts (if applicable)

If this phase has work streams that can run simultaneously via sub-agents, define them here. This section appears only in phases with `Parallel tracks: Yes` in the header.

```markdown
## Parallel tracks

### Interface contracts (established before tracks launch)

These contracts are the agreed boundaries between tracks. Sub-agents build against these shapes independently.

- **Research API:** `POST /api/research` accepts `X-Mock-Research: true` header → returns `{ run_id: string }` with status 202. `GET /api/research/{run_id}/status` → returns `{ status: string, agents: Array<{ name, status }> }`
- **Fixture format:** One markdown file per research agent in `testing/e2e/fixtures/research/`. Filenames: `00-summary.md` through `05-case-studies.md`

### Track A: Backend mock pipeline [sub-agent: generalPurpose]
- Deliverables: items 1-2 from manifest
- Depends on: none
- Produces: Research API contract (working implementation)

### Track B: Test fixtures and capture script [sub-agent: shell]
- Deliverables: items 3-4 from manifest
- Depends on: Fixture format (shape only — does not need Track A complete)
- Produces: Fixture files on disk

**Sync point:** Both tracks complete → integration verification → phase acceptance criteria
```

Each track specifies:
- Which manifest items it covers
- What it depends on (interface contracts or other tracks)
- What it produces
- The recommended sub-agent type (`generalPurpose` for code, `shell` for scripts/commands, `browser-use` for UI work)

### Deliverables manifest

Same format as the master manifest, but **only items for this phase**. Numbered sequentially within the phase. If the phase has parallel tracks, annotate each item with its track.

```markdown
## Deliverables Manifest

### Track A: Backend mock pipeline
1. NEW  `backend/services/mock_research_pipeline.py` — Mock pipeline that reads fixture files
2. MOD  `backend/routers/research.py` — Add mock header routing conditional

### Track B: Test fixtures
3. NEW  `testing/e2e/fixtures/research/00-summary.md` — Exported research summary with HTML markers
4. NEW  `testing/e2e/scripts/capture-fixtures.sh` — MongoDB export script

**Implementation protocol:** The implementing agent must follow the `plan-implementation` cursor rule when executing this phase.
```

For phases without parallel tracks, omit track annotations and list items sequentially as before.

### Acceptance criteria

A checklist of observable outcomes that prove this phase is done. Written as testable assertions — the implementing agent or the user can verify each one.

```markdown
## Acceptance criteria

- [ ] `POST /api/research` with `X-Mock-Research: true` header returns 202 and completes in under 5 seconds
- [ ] Research status endpoint shows all agents as "complete" after mock run
- [ ] Fixture files are read from `testing/e2e/fixtures/research/` (not generated)
- [ ] Without the mock header, the real research pipeline runs as before (no regression)
```

### Test plan

How to verify the acceptance criteria. Can be manual steps, automated test commands, or both.

```markdown
## Test plan

1. Start the dev stack: `docker compose up`
2. Run: `curl -X POST http://localhost:8000/api/research -H "X-Mock-Research: true" -H "Content-Type: application/json" -d '{"prospect_name": "Test", "company_url": "https://example.com"}'`
3. Verify 202 response with `run_id`
4. Poll `GET /api/research/{run_id}/status` — expect `complete` within 5 seconds
5. Run without mock header — verify real pipeline starts (cancel after confirming)
```

### Interface contract

What this phase produces that later phases depend on. This is how phases communicate without coupling their implementation details.

```markdown
## Interface contract (for subsequent phases)

- **API:** `POST /api/research` accepts `X-Mock-Research: true` header to activate mock pipeline
- **Fixture location:** `testing/e2e/fixtures/research/*.md` — mock pipeline reads from here
- **Behavior:** Mock pipeline writes to the same `research_runs` collection with the same document shape as the real pipeline
```

If this is the final phase, write: "N/A — this is the final phase."

---

## Design principles

**Self-contained over DRY.** It's fine to repeat context that's in the master plan. The implementing agent should never need to open another file to understand what to build. Redundancy between the master plan and phase docs is intentional.

**Concrete over abstract.** File paths, API endpoints, schema fields, CLI commands. Not "create a service that handles X" but "create `backend/services/foo.py` with an async function `bar(baz: str) -> dict` that does X."

**Testable over complete.** Each phase's acceptance criteria should be verifiable in under 10 minutes. If a phase can't be tested independently, it's either too small (merge with an adjacent phase) or too entangled (refactor the phase boundaries).

**Interface contracts enable parallelism.** The key to parallel tracks is agreeing on the boundary shapes before implementation starts. If Track A (backend) and Track B (frontend) agree on the API contract, both can build against it simultaneously — just like human teams doing API-first development. The contract must be concrete enough that both tracks produce compatible code: exact paths, exact request/response shapes, exact status codes.
