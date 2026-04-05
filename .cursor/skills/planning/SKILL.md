---
name: planning
description: >-
  Create implementation plans and clarifying questions for engineering work.
  Use when the user asks to create a plan, plan a feature, design an approach,
  write a planning doc, or says "plan for X". Also use this skill when
  switching to Plan mode, when already in Plan mode, or when the agent
  proactively enters Plan mode for a complex task. Triggers on references to
  prompts/generic-plan-prompt.txt or the plans/ directory.
---

# Planning skill

This skill governs how plans are created in this project. Plans are the contract between you (the planning agent) and a future implementing agent. A sloppy plan produces sloppy implementation. A precise plan with a clear deliverables manifest gets followed to the letter.

## Workflow overview

Planning has two phases that use different Cursor modes:

1. **Plan mode** — collaborative design with the user (read-only, no file writes)
2. **Agent mode** — formal document creation (writes the plan and questions files)

Always start in Plan mode for the collaborative phase. Switch to Agent mode only when the design is settled and you're ready to write documents.

### Simple vs. complex plans

During the Plan mode conversation, assess the plan's complexity. Use this to decide the output format:

- **Simple plan** (1-2 phases, under ~300 lines, implementable in one conversation): produce a single `<name>-PLAN.md` with an inline deliverables manifest. This is the default.
- **Complex plan** (3+ phases, multiple days of work, phases are independently testable, total spec would exceed ~400 lines): produce a **master plan** plus **separate phase implementation docs**. See [Phase implementation doc template](reference/phase-impl-template.md) for the format.

When in doubt, ask the user: *"This looks like it could be 3-4 phases of work. Should I break this into separate phase implementation docs so each phase can be handed off and tested independently, or keep it as a single plan?"*

---

## Phase 1: Collaborative design (Plan mode)

If you are not already in Plan mode, switch to it now. This phase is a real-time conversation — no files are written.

### 1A. Understand the request

Ask the user what they want to build and why. Listen for:
- The core problem or capability
- Who benefits and how
- Any constraints they already know (timeline, tech stack, dependencies)
- Whether they have prior art or reference material

### 1B. Explore the codebase

Use read-only tools to understand the current state:
- Search for related modules, services, components, and data models
- Identify what already exists that the plan will touch or extend
- Note conventions (naming, directory structure, patterns) the plan should follow

### 1C. Propose high-level approaches

Present 1-3 approaches with trade-offs. For each:
- What it looks like at a high level
- What it costs in complexity, code, and ops
- What it buys (capabilities, flexibility, simplicity)
- Your recommendation and why

Let the user react and steer. This is the most valuable part of the process — real-time shaping of the design before anything is committed to a document.

### 1D. Resolve ambiguities in real time

Work through the [engineering discipline checklist](reference/questions-checklist.md) mentally. For any item that surfaces a meaningful question, ask the user **now** — don't defer it to a questions doc. Cover:
- Scope boundaries (what's in, what's out, what's deferred)
- Architectural decisions (where does each responsibility live)
- Simplicity checks (can we do this with fewer moving parts)
- Data and API contracts (schemas, endpoints, status codes)
- Integration points (external services, env vars, secrets)

Track decisions as you go. Summarize periodically: *"So far we've decided X, Y, Z. Still open: A, B."*

### 1E. Analyze dependencies and parallelization (complex plans)

For complex plans, map the dependency graph before finalizing the phase structure. This is where the most implementation time is saved — identifying work that can run in parallel via sub-agents.

1. **List all deliverables** at a high level (backend service, API endpoints, frontend component, test fixtures, etc.).
2. **For each deliverable, ask: what does this depend on?** A frontend component depends on the API contract it consumes, but not on the backend implementation behind that contract. A test fixture depends on the schema shape, but not on the service that reads it.
3. **Identify interface contracts** — the boundaries where parallel tracks can agree on a shape and build independently. Common boundaries:
   - API contracts (request/response shapes, endpoint paths, status codes)
   - Database schemas (collection names, document shapes)
   - File formats (fixture structure, config shape)
   - Component props / function signatures
4. **Group deliverables into parallel tracks** — work streams that share no dependencies beyond their interface contracts. Common patterns:
   - Backend service + Frontend UI (connected by API contract)
   - Core implementation + Test infrastructure (connected by schema/fixture format)
   - Multiple independent backend services
   - Data migration + Code that reads the new shape
5. **Present the dependency graph to the user.** Show:
   - Which tracks can run in parallel
   - What interface contracts connect them
   - Where sync points are needed (all tracks must complete before the next phase)
   - Estimated time savings from parallelization

The user may see parallelization opportunities you missed, or may prefer sequential execution for simpler oversight. Confirm the approach.

### 1F. Confirm readiness

Before switching to Agent mode, confirm with the user:
- *"Here's what I'll write up: [summary of approach, scope, key decisions]. The plan will have N phases with M parallel tracks. I still have open questions about [list]. Ready for me to write the formal docs?"*
- For complex plans with parallelization, also summarize: *"Phases that can run in parallel: [list]. Interface contracts needed: [list]. Estimated sync points: [list]."*

---

## Phase 2: Formal document creation (Agent mode)

Switch to Agent mode.

### 2A. Read reference material

Before writing, read these reference files for format and structure requirements:
- [Plan sections template](reference/plan-sections.md) — required sections and what goes in each
- [Deliverables manifest example](reference/deliverables-manifest-example.md) — format for the manifest
- [Questions checklist](reference/questions-checklist.md) — only for remaining unresolved items
- [Phase implementation doc template](reference/phase-impl-template.md) — format for phase docs (complex plans only)

### 2B. Check manual test rules for UX impact

Before writing the plan, determine whether the plan modifies any frontend pages, components, layouts, or user-facing flows. If it does, scan all manual test rules in `.cursor/rules/manual-test-*.mdc` and check whether any rule's test steps, layout verification, navigation instructions, or element selectors are invalidated by the plan's changes. For each affected rule, add a `MOD` entry to the deliverables manifest with a description of what needs updating (e.g., "Update layout verification steps and navigation flow to reflect persistent chat panel replacing inline chat").

If the plan has no frontend or UX impact, skip this step.

### 2C. Write the planning doc(s)

#### Simple plan (single file)

Create `plans/<feature-name>-PLAN.md` with all required sections from the template. Key rules:
- Every section from the template must be present. If empty, write "N/A" with a one-line reason.
- The **Deliverables Manifest** is mandatory. It is the contract the implementing agent follows. Every file to create, modify, or delete must be listed with its exact path.
- Incorporate all decisions made during the Plan mode conversation. Do not re-open settled questions.
- Cross-reference the technical detail section from the implementation outline so each phase points to the relevant spec.

#### Complex plan (master + phase docs)

Create these files:

1. **`plans/<feature-name>-PLAN.md`** — the master plan. Contains:
   - Summary, scope, approach overview, risks, and open decisions (same as a simple plan)
   - A **phase map**: numbered list of phases with one-line descriptions, dependencies between phases, and links to the phase implementation docs
   - The **full deliverables manifest** across all phases (so the complete scope is visible in one place)
   - Does NOT contain detailed technical implementation specs — those live in the phase docs

2. **`plans/<feature-name>-phase-N-IMPL.md`** — one per phase. Each is self-contained. See the [phase implementation doc template](reference/phase-impl-template.md) for the required format. Key properties:
   - An implementing agent can pick up a phase doc and start work **without reading the master plan or other phase docs**
   - Each has its own deliverables manifest (a subset of the master manifest)
   - Each has its own acceptance criteria and test plan
   - Each states its prerequisites: what must be true before starting (prior phases completed, specific files/APIs must exist)
   - Each defines its interface contract: what it produces that later phases depend on

### 2D. Write the questions doc

Create `plans/<feature-name>-QUESTIONS.md`. This should contain **only** questions that were NOT resolved during the Plan mode conversation. If all questions were resolved live, write a short doc noting that: *"All clarifying questions were resolved during the collaborative design session. See the plan for decisions made."*

Format: one question per block, three blank lines between questions, each question standalone (answerable without reading the plan).

### 2E. Present for review

Show the user:
- A summary of what the plan covers
- The phase map (for complex plans: number of phases, dependencies, what each phase delivers)
- The full deliverables manifest (so they can verify completeness across all phases)
- The remaining questions (if any)
- Ask: *"Review the plan and questions. I'll integrate your answers and finalize."*

---

## Phase 3: Q&A integration

When the user provides answers to remaining questions:

1. Re-read the plan document from the file (not from memory).
2. For each answer, update the relevant plan section to incorporate the decision.
3. If an answer changes scope or approach, update the deliverables manifest accordingly.
4. After all answers are integrated, re-read the plan once more and verify internal consistency: do the manifest items still match the approach? Do the technical details still match the outline?
5. Present the changes: *"I've integrated your answers. Here's what changed: [list]. The deliverables manifest now has N items across M phases."*

---

## Quality bar

The plan must meet this standard before it's considered ready for implementation:

- An implementing agent reading it can start work without guessing structure or contracts
- Every deliverable has an exact file path, operation type, and description
- The deliverables manifest is the single source of truth for "done"
- The implementing agent must follow the `plan-implementation` cursor rule when executing — reference this in the plan
- Phases are discrete and independently validatable
- Risks are honest, not performative

---

## Backward compatibility

If the user references `@prompts/generic-plan-prompt.txt` directly, treat that as a trigger for this skill. The prompt file contains the same requirements in a flattened format. Follow this skill's workflow instead — it supersedes the prompt file.
