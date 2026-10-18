# MemoTrail Docs

These docs are a routing layer for implementation work, not a project archive.
Load only the document and section needed for the current request.

## Route the request

| Question                                | Read                                           | Purpose                                                      |
| --------------------------------------- | ---------------------------------------------- | ------------------------------------------------------------ |
| Why does it exist, and what belongs?    | [positioning.md](./positioning.md)             | Problem, audience, core model, and the feature filter        |
| What should the product do?             | [product.md](./product.md)                     | Intended behavior, terminology, scope, and boundaries        |
| Where and how should it be changed?     | [architecture.md](./architecture.md)           | System contracts and request-to-code map                     |
| What is done or still open?             | [status.md](./status.md)                       | Current completion, next work, blockers, and acceptance gaps |
| How do I run the repository?            | [../README.md](../README.md)                   | Local setup, validation, and deployment shape                |
| Does Web have framework-specific rules? | [../apps/web/AGENTS.md](../apps/web/AGENTS.md) | Rules generated for the installed Next.js version            |

Start with `status.md`, then use `rg` to find the relevant heading in one other document.
Do not read all docs unless the request genuinely spans the whole product.

## Ownership

The explicitly retained [AI direction record](./ai-direction-record.md) preserves earlier AI requirements and exploration for future reconsideration.
It is background, not the current product contract.

- `product.md` says what is true for the user. It contains no implementation progress or decision history.
- `architecture.md` says how the system is divided and where work belongs. It contains no delivery diary.
- `status.md` says what is true right now. It keeps only actionable gaps and recent evidence boundaries.
- Git commits and pull requests retain historical detail.

Each fact should have one owner.
Use a link instead of copying the same explanation into another document.

## Updating docs

- Change docs in the same commit when their owned truth changes.
- Remove resolved status items instead of preserving them as history.
- Keep paths broad enough to survive small refactors but precise enough to route an agent.
- Add a new document only when none of the three existing responsibilities can own the information cleanly.
