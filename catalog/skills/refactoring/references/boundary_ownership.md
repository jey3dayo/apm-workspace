# Boundary Ownership Reference

Use this reference during Phase 1-C when refactoring involves validation,
Result/error flow, data access, runtime configuration, or external IO. This is a
diagnostic aid, not a source of new folder conventions.

Treat a folder as an owner only when repository evidence supports it: existing
imports, exports, tests, docs, or repeated call patterns. If multiple owner
folders are plausible, keep the plan conditional until the boundary is
confirmed.

| Technology concern                                                          | Expected owner pattern                                                     | Drift signal                                                                      |
| --------------------------------------------------------------------------- | -------------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| Schema validation, e.g. Valibot/Zod/ArkType/Yup/FormData/request body       | `schemas/...`, `schema/...`, `validators/...`, or validation owner         | Same schema/parser/type assertion repeated in routes/actions/components           |
| Result/error flow, e.g. neverthrow/byethrow/ResultAsync/error translation   | Existing repository, service, action, adapter, or error owner boundary     | Equivalent `ok`/`err`, `ResultAsync`, error serialization scattered across layers |
| Action/route response serialization                                         | Existing action, route adapter, presenter, or response serialization owner | Domain/app errors converted to HTTP/UI response shapes in many callers            |
| DB/query/transaction logic, e.g. Drizzle/Prisma/Kysely/SQL/query builder/tx | `db/...`, `repository/...`, or `repositories/...`                          | `.select()`, `.insert()`, raw SQL, `tx` usage outside data-access owner           |
| Multi-repository transaction orchestration                                  | Existing service/use-case, repository transaction, or unit-of-work owner   | Raw `tx` threaded through routes/actions/components or spanning owners ad hoc     |
| Env/auth/request parsing                                                    | config/env/auth/schema owner                                               | `process.env`, cookie/header/session parsing, FormData parsing repeated inline    |
| External IO/API clients                                                     | `clients/...`, `adapters/...`, `integrations/...`, or service owner        | Direct `fetch`/SDK calls inside UI or unrelated feature code                      |

Valid exceptions include test fixtures, mocks, migrations, seeds, generated
code, and thin framework/library wrappers when repository evidence supports
them.

If a refactoring uncovers a reusable boundary concern not represented in this
table, mention the missing viewpoint in the final response and ask whether to
add it to this reference.
