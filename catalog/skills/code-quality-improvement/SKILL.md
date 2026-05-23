---
name: code-quality-improvement
description: |
  [What] Specialized skill for systematic code quality improvement. Provides Phase 1→2→3 workflow for ESLint error fixing, type safety improvements, and code quality enhancements
  [When] Use when: users mention "ESLintエラー", "大量修正", "段階的修正", "code quality", or need systematic code quality improvement
  [Keywords] ESLintエラー, 大量修正, 段階的修正, code quality
---

# Code Quality Improvement Skill

## When to Use

This skill is automatically triggered when:

- You need to fix a large number of ESLint errors
- You want to incrementally improve code quality
- You are performing systematic refactoring
- You want to improve type safety
- You need to fix clean architecture boundary violations

## Trigger Keywords

- "ESLintエラー", "ESLint error", "lint error"
- "大量修正", "一括修正", "bulk fix"
- "段階的修正", "phased approach"
- "コード品質改善", "code quality", "品質改善"
- "リファクタリング", "refactoring"
- "型安全性", "type safety"
- "未使用変数", "unused variables"

## Phased Workflow

### Phase 1: Preparation & Analysis (15-30 min)

#### 1.1 Assess Error State

```bash
# Check total error count
pnpm lint 2>&1 | tee lint-errors.log

# Count errors by category
echo "Unused vars: $(pnpm lint 2>&1 | grep -c 'no-unused-vars')"
echo "Type assertions: $(pnpm lint 2>&1 | grep -c 'no-type-assertions-without-validation')"
echo "Result<T,E> pattern: $(pnpm lint 2>&1 | grep -c 'neverthrow/must-use-result')"
echo "Layer boundary: $(pnpm lint 2>&1 | grep -c 'enforce-layer-boundaries')"
```

#### 1.2 Prioritize Errors

Classify errors by priority:

| Priority    | Category                       | Timeline    | Examples                                            |
| ----------- | ------------------------------ | ----------- | --------------------------------------------------- |
| 🔴 Critical | Build failures, security risks | Immediately | `any` type, type assertions, missing validation     |
| 🟠 High     | Potential runtime errors       | Within 24h  | Incorrect unused var removal, Result<T,E> violation |
| 🟡 Medium   | Architecture consistency       | Within 1w   | Layer boundary violations, separation of concerns   |
| 🟢 Low      | Style guide violations         | Within 1mo  | Code formatting, naming conventions                 |

#### 1.3 Draft Fix Plan

```markdown
## Fix Plan

### Current State

- Total errors: XXX
- Critical: XX
- High: XX
- Medium: XX
- Low: XX

### Goals

- After Phase 2: Critical 0, High reduced by 50%
- After Phase 3: All errors reduced by 80%

### Approach

1. Auto-fixable errors → pnpm lint:fix
2. Pattern-applicable errors → bulk replacement script
3. Manual fixes required → handle individually
```

### Phase 2: Execution (1-3 hours)

#### 2.1 Apply Auto-Fixes

```bash
# Step 1: Format
pnpm format:prettier

# Step 2: ESLint auto-fix
pnpm lint:fix

# Step 3: Measure impact
echo "Remaining errors: $(pnpm lint 2>&1 | grep -c 'error')"
```

#### 2.2 Pattern-Based Bulk Fixes

```bash
# Remove underscore prefix from unused vars in tests
find src/tests -name "*.test.ts" -exec sed -i '' 's/const _\([a-zA-Z][a-zA-Z0-9_]*\) = /const \1 = /g' {} \;

# Type assertion → type guard replacement (manual review recommended)
# See references/patterns.md for details
```

#### 2.3 Manual Fixes

Fix in priority order:

1. Remove `any` types → Zod schema + `unknown`
2. Remove type assertions → create type guards
3. Apply Result<T,E> pattern → integrate into service layer
4. Fix layer boundary violations → clean up dependencies

See [references/patterns.md](references/patterns.md) for detailed fix patterns.

#### 2.4 Incremental Commits

```bash
# Commit by feature/file
git add src/tests/**/*.test.ts
git commit -m "fix: remove unused variable underscore prefixes in tests"

git add src/lib/services/**/*.ts
git commit -m "refactor: apply Result<T,E> pattern to services"
```

### Phase 3: Verification & Completion (30 min-1 hour)

#### 3.1 Quality Assurance

```bash
# Required checks (all must pass)
pnpm test          # All tests pass
pnpm type-check    # 0 type errors
pnpm lint          # 0 lint violations
pnpm build         # Build succeeds (if applicable)
```

#### 3.2 Measure Impact & Report

```markdown
## Fix Completion Report

### Results

- Total errors: XXX → YY (ZZ% reduction)
- Critical: XX → 0 (100% resolved)
- High: XX → Y (ZZ% reduction)

### Quality Indicators

- [ ] All tests pass
- [ ] 0 type errors
- [ ] 0 lint violations
- [ ] Build succeeds

### Key Fixes Applied

1. `any` type removal: XX locations
2. Type assertion removal: XX locations
3. Result<T,E> pattern applied: XX locations
4. Layer boundary violations fixed: XX locations
```

## Important Notes

### Boundary Owner Mapping

Before fixing validation, type-safety, Result, or data-access issues, identify
the repository's existing owner folder for each concern. Prefer the owner proven
by imports, exports, tests, docs, or repeated call patterns. Do not infer owner
folders from technology names alone, and do not invent a new owner folder from
this table alone.

| Technology / concern signals                                                                              | Expected owner pattern                                                                          | Move / centralize here                                                | Non-owner layers should do                                    | Common exceptions                                                         |
| --------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- | ------------------------------------------------------------- | ------------------------------------------------------------------------- |
| Valibot, Zod, ArkType, Yup, schema objects, parser helpers, `safeParse`, `parse`                          | `schemas/...`, `schema/...`, `validation/...`, or validation owner                              | Schema definitions, parser helpers, typed validation results          | Import exported schema/parser/helper                          | Test fixtures, mocks, route-local thin wrappers when supported            |
| FormData parsing, server action input validation, request body validation                                 | action-specific schema owner, `schemas/...`, action validation helper                           | Reusable form/request parsers and validation error shaping            | Call parser before service/repository logic                   | One-off tiny action parser if the repo already keeps action-local schemas |
| `unknown` to domain type conversion, type guards, assertion replacement                                   | `schemas/...`, `guards/...`, `mappers/...`, or transform owner                                  | Type guards, decode/parse functions, assertion-free conversion        | Call guard/parser, avoid `as`                                 | Framework-required casts with documented narrow scope                     |
| neverthrow, byethrow, `Result`, `ResultAsync`, error wrapping/unwrapping                                  | repository, service, action, or adapter boundary that already translates errors                 | Conversion between thrown errors, infra errors, and domain/app errors | Consume the boundary result; do not re-wrap equivalent errors | Tests, adapter-specific normalization, framework response adapters        |
| DB access, Drizzle, Prisma, Kysely, SQL, query builder, `.select`, `.insert`, `.update`, transaction `tx` | `db/...`, `repository/...`, `repositories/...`, or data-access owner                            | Queries, transactions, persistence mapping                            | Call repository/service API                                   | Migrations, seeds, test setup, generated ORM artifacts                    |
| External API SDK/client, `fetch` to third-party services, webhook signature verification                  | `clients/...`, `adapters/...`, `integrations/...`, `services/...` when established              | HTTP client setup, retries, response parsing, external error mapping  | Call adapter/client function                                  | Mock clients, local test stubs                                            |
| Environment variables, feature flags, runtime config                                                      | `config/...`, `env/...`, `settings/...`, or config module                                       | Env parsing, defaults, required variable validation                   | Import typed config values                                    | Test env setup, build-tool config files                                   |
| Auth/session/permission checks                                                                            | `auth/...`, `session/...`, `permissions/...`, middleware/service owner                          | Session lookup, permission predicates, auth error normalization       | Call auth helper/policy                                       | Route-level guard composition, tests                                      |
| Cache/Redis/storage concerns                                                                              | `cache/...`, `storage/...`, `repositories/...`, adapter owner                                   | Key construction, TTL policy, cache serialization                     | Call cache/storage helper                                     | Test fakes, one-off migration scripts                                     |
| Queue/job/scheduler concerns                                                                              | `jobs/...`, `queue/...`, `workers/...`, adapter owner                                           | Enqueue/dequeue payload schema, retry/error policy                    | Call job/queue API                                            | Worker entrypoints, test helpers                                          |
| Logging, metrics, tracing, telemetry                                                                      | `logger/...`, `observability/...`, `telemetry/...`, infra helper                                | Logger construction, metric names, span helpers                       | Call shared logger/metric helper                              | Local debug logs during development should not be committed               |
| DTO/domain mapping, API response shaping, presenter mapping                                               | `mappers/...`, `transformers/...`, `presenters/...`, or established service/repository boundary | Conversion between persistence/API/domain/view shapes                 | Import mapper, avoid duplicate object reshaping               | Trivial inline projection if local and not repeated                       |

Treat tests, mocks, fixtures, seeds, migrations, generated code, and thin
framework/library wrappers as exception candidates. Keep them explicit instead
of forcing every matching technology signal into an owner move.

Operational rules:

1. Search first with `rg --files` and import-pattern scans.
2. Treat a folder as owner only with repository evidence.
3. Move implementation to the owner and export a public API.
4. Preserve the destination owner's existing public API style instead of introducing a new abstraction shape.
5. Update callers to import the owner API.
6. Add focused tests only for the changed boundary contract.
7. Keep exception candidates explicit instead of forcing moves.
8. If the work reveals a reusable boundary concern not covered here, call it
   out in the final response and ask whether to add it to this mapping.

### Dangerous Patterns — Fixes to Absolutely Avoid

#### 1. Auto-Fix Mis-fix Pattern

```typescript
// ❌ 危険: アンダースコアだけ追加して使用箇所は未修正
export function verifyFormDataSupport(): void {
  const _formData = new FormData(); // ← _追加

  // 使用箇所は_なし → ReferenceError!
  formData.append("test", "value"); // ← 未定義変数参照
  expect(formData.get("test")).toBe("value");
}

// ✅ 正しい: 一貫した命名
export function verifyFormDataSupport(): void {
  const formData = new FormData();

  formData.append("test", "value");
  expect(formData.get("test")).toBe("value");
}
```

### Important

#### 2. Rules Where Auto-Fix Is Dangerous

The following rules have auto-fix disabled (manual fix required):

- `no-manual-success-error-patterns` - Risk of generating undefined variables
- `no-type-assertions-without-validation` - Complex type conversions
- `require-result-pattern-in-services` - Risk of breaking logic

### Safe Fix Order

1. Auto-fixable → run automatically with `pnpm lint:fix`
2. Pattern-applicable → bulk script (must run tests)
3. Manual fix required → handle individually with care

## Layer-Specific Fix Strategy

### Service Layer

```typescript
// 🔴 修正前: any型 + 型アサーション
async function getUser(id: string): Promise<any> {
  const response = await fetch(`/api/users/${id}`);
  return response.json() as User;
}

// ✅ 修正後: Zodスキーマ + Result<T,E>
async function getUser(id: string): ResultAsync<User, Error> {
  return handleApiResponse(fetch(`/api/users/${id}`), UserSchema);
}
```

### Action Layer

```typescript
// 🔴 修正前: FormData型安全性なし
export async function createUser(formData: FormData) {
  const name = formData.get("name") as string;
  const email = formData.get("email") as string;
  return await userService.create({ name, email });
}

// ✅ 修正後: Zodスキーマ検証 + Result<T,E>
export async function createUser(formData: FormData) {
  const validated = validateFormData(formData, CreateUserSchema);
  if (!validated.success) {
    return { success: false, error: validated.error };
  }

  const result = await userService.create(validated.data);
  return toServerActionResult(result);
}
```

### Transform Layer

```typescript
// 🔴 修正前: 型アサーション
function transformData(raw: unknown): User {
  return raw as User;
}

// ✅ 修正後: 型ガード + バリデーション
function transformData(raw: unknown): Result<User, Error> {
  const validated = UserSchema.safeParse(raw);
  if (!validated.success) {
    return err(new Error(validated.error.message));
  }
  return ok(validated.data);
}
```

## Checklist

### Phase 1: Preparation & Analysis

- [ ] Error state assessed (by category)
- [ ] Priorities determined (Critical/High/Medium/Low)
- [ ] Fix plan drafted (goals and approach defined)
- [ ] Backup created (git stash or branch)

### Phase 2: Execution

- [ ] Auto-fixes applied (prettier + lint:fix)
- [ ] Pattern-based fixes complete (script run)
- [ ] Manual fixes complete (in priority order)
- [ ] Incremental commits done (by feature/file)
- [ ] Tests run after each step

### Phase 3: Verification & Completion

- [ ] All tests pass (pnpm test)
- [ ] 0 type errors (pnpm type-check)
- [ ] 0 lint violations (pnpm lint)
- [ ] Build succeeds (if applicable)
- [ ] Impact measurement report created
- [ ] Documentation updated (if needed)

## Related Resources

### Detailed Fix Patterns

- [references/patterns.md](references/patterns.md) - Fix patterns by ESLint error type

### Project-Specific Guides

- Result<T,E> pattern guide from your repository, if one exists
- Layer overview: `docs/layers/layer-overview.md`
- Type safety guide: `docs/development/type-safety-comprehensive-guide.md`

### Related Commands

- `/refactor` - Integrated refactoring
- `/review` - Code review
- `/polish` - Code quality assurance

## Track Record

### v2.1.0 /fix command results (2025-07-07)

- TypeScript errors: 6 → 0 (100% resolved)
- ESLint warnings: 9 → 0 (100% resolved)
- Auto-fix rate: 100% AI-driven resolution

### Large-scale fix results

- Unused variables: 2,523 → 2,137 (386 removed, 15% improvement)
- Type errors: multiple → 0 (100% resolved)
- ESLint errors: 500+ → 32 (94% reduction)
- `any` types: 93 → 0 (100% eliminated)

## Troubleshooting

### Common Issues

#### Q: pnpm lint:fix doesn't fix some errors

A: The following rules require manual fixes (auto-fix disabled):

- Type assertion rules
- Result<T,E> pattern rules
- Layer boundary violation rules

#### Q: Tests fail after fixes

A: Likely a mis-fix when removing unused variables. Check:

1. Verify all usages of locations where `_` prefix was added
2. Confirm the removed variable was truly unused
3. Review changes in detail with `git diff`

#### Q: Type errors increased after fixes

A: A temporary increase when removing type assertions is normal. Add appropriate type guards or validation to resolve.

## Lessons Learned

### Success Patterns

1. Incremental fixes (50-100 at a time)
2. Measure impact (quantitative before/after comparison)
3. Continuous test execution
4. Commit by feature

### Patterns to Avoid

1. Large bulk fixes (high risk)
2. Fixing without running tests
3. Over-reliance on auto-fix
4. Ignoring error messages

## 🤖 Agent Integration

This skill provides expertise to agents executing phased code quality improvement tasks:

### Error-Fixer Agent (especially important)

- Provides: 3-phase quality improvement strategy, ESLint error fixing, type safety improvements
- When: ESLint error fixing, bulk fixes, code quality improvement tasks
- Context:
  - Phase 1: Surface linter fixes (ESLint auto-fix)
  - Phase 2: Type safety improvements (eliminate `any`, implement type guards)
  - Phase 3: Deep quality improvements (Result<T,E>, architecture patterns)
  - Incremental fix strategy (50-100 at a time)
  - Impact measurement and quantitative evaluation

### Orchestrator Agent

- Provides: Quality improvement planning, multi-phase coordination
- When: Large-scale quality improvement projects
- Context: Phase progress management, session management, impact measurement, risk management

### Code-Reviewer Agent

- Provides: Quality improvement impact evaluation, continuous quality checks
- When: Quality verification after phase completion
- Context: Quantitative before/after comparison, identifying remaining issues, next phase recommendations

### Auto-load Conditions

- Mentions of "ESLintエラー", "大量修正", "段階的修正"
- Mentions of "code quality", "品質改善", "リファクタリング"
- Detection of projects with 100+ ESLint errors
- When `/refactor` command is executed

### Integration Example

```
User: "Fix ESLint errors incrementally and improve type safety"
    ↓
Create TaskContext
    ↓
Project detected: TypeScript (300 ESLint errors)
    ↓
Skills auto-loaded: code-quality-improvement, typescript
    ↓
Agent selected: error-fixer
    ↓ (skill context provided)
3-phase strategy + TypeScript type safety patterns
    ↓
Phase 1 executed (100 fixes) → confirm continuation → Phase 2
    ↓
Complete (incremental quality improvement, impact measurement report)
```
