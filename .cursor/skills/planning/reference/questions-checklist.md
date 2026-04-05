# Engineering discipline checklist

Use this checklist when reviewing a plan for completeness and rigor. In Plan mode, use it to drive real-time questions to the user. In Agent mode, use it to generate remaining questions for the questions doc.

Not every item yields a question — use judgment. Favor questions that resolve ambiguity or prevent over- or under-engineering.

## Checklist

- **Requirements & scope** — Are success criteria testable? Is scope frozen enough to avoid gold-plating? What is explicitly deferred?
- **Architecture & boundaries** — Do module/service boundaries match actual coupling? Is there one obvious place for each responsibility, or redundant ownership?
- **Simplicity & YAGNI** — Can the same outcome be achieved with fewer moving parts? Is any abstraction solving a problem we do not yet have?
- **Complexity tradeoffs** — For each meaningful complexity: what failure mode or requirement does it address? What is the simplest alternative, and why is it insufficient?
- **Data & APIs** — Are schemas and contracts stable and minimal? Versioning, migrations, and backward compatibility where needed?
- **Correctness & edge cases** — Idempotency, concurrency, partial failure, retries, timeouts, and error contracts defined where they matter?
- **Security & privacy** — Authn/z boundaries, secret handling, input validation, least privilege, and data minimization for the features in scope?
- **Reliability & operations** — Health checks, graceful degradation, rollback story?
- **Observability** — Logging, metrics, or tracing at the right depth — not none, not a sprawling platform unless justified.
- **Performance** — Hot paths identified; premature optimization avoided; load or latency assumptions stated where relevant?
- **Testing & quality** — What must be automated (unit, integration, e2e) vs manual; test data and environments; definition of done for each phase?
- **Delivery & change safety** — Feature flags, incremental rollout, migration strategy, and compatibility with existing users or data?
- **Maintainability** — Onboarding cost, documentation touchpoints, and consistency with repo conventions?

## Question format (for questions doc)

One question per block. Each question:
- Is stated clearly and standalone (answerable without reading the plan)
- Has exactly three blank lines after it before the next question

Before drafting questions, review the plan from a technical engineering perspective: check that it is implementable, internally consistent, and honest about risks. Prefer simplicity: flag unnecessary layers, speculative generalization, or "future-proofing" that does not serve the stated goal.

Every non-trivial source of complexity (new service, abstraction, async boundary, config surface) should be defensible with a clear tradeoff. If the plan adds complexity without stating what it buys and what simpler option was passed over, surface that as a question.
