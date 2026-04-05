# Deliverables manifest — format and example

## Format

Each entry is a numbered line with three parts:

```
N. OPERATION  `exact/file/path` — One-line description
```

- **N** — sequential number across all phases
- **OPERATION** — one of: `NEW` (file does not exist yet), `MOD` (file exists, will be modified), `DELETE` (file will be removed)
- **Path** — exact path relative to repo root, in backtick code formatting
- **Description** — what the file contains (for NEW) or why it changes (for MOD/DELETE)

Group by phase. Each phase gets a heading.

## Example

```markdown
## Deliverables Manifest

### Phase 1 — Backend mock pipeline
1. NEW  `backend/services/mock_research_pipeline.py` — Mock pipeline that reads fixture files instead of calling research agents
2. MOD  `backend/routers/research.py` — Add 5-line conditional to route mock vs real pipeline based on X-Mock-Research header

### Phase 2 — Frontend mock mode
3. MOD  `frontend/src/lib/api.ts` — Add localStorage-based mock mode toggle and inject X-Mock-Research header into API calls
4. MOD  `frontend/src/components/Navbar.tsx` — Add red "Mock Mode" indicator badge, clickable to toggle off

### Phase 3 — Fixture data
5. NEW  `testing/e2e/fixtures/research/00-summary.md` — Exported Cadrex research summary with HTML comment markers
6. NEW  `testing/e2e/fixtures/research/01-company.md` — Exported company research
7. NEW  `testing/e2e/scripts/capture-fixtures.sh` — Script to export research from MongoDB to fixture files

### Phase 4 — Cursor skill for manual testing
8. NEW  `.cursor/skills/e2e-manual-test/SKILL.md` — Workflow orchestration for browser-based manual testing
9. NEW  `.cursor/skills/e2e-manual-test/personas/cadrex-ae.md` — Test persona with relationship knowledge
10. NEW `.cursor/skills/e2e-manual-test/verification/prd-checklist.md` — PRD field verification criteria
11. DELETE `.cursor/rules/manual-test-relationship-chat.mdc` — Replaced by the skill above

**Implementation protocol:** The implementing agent must follow the `plan-implementation` cursor rule when executing this plan.
```

## Rules

- Every file the plan produces must appear in the manifest. No exceptions.
- The implementing agent treats this as its task list. Items not on the list are not delivered.
- If the implementing agent believes a manifest item is wrong (wrong path, wrong artifact type, unnecessary), it must ask the user before substituting — never silently deviate.
- The manifest footer must reference the `plan-implementation` cursor rule.
