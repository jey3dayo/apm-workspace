---
name: mutation-testing-audit
description: >-
  Audit test quality with mutation testing (@mizchi/mutator) on TypeScript/Vitest
  projects: pick pure-logic targets, classify survived mutants (real gap /
  equivalent / timeout), add adversarial tests, and re-run until targeted
  survivors reach zero（「ミューテーションテスト」「mutation testing」「テスト品質の監査」）.
  Not for UI/jsdom tests and not a CI gate.
---

# Mutation Testing Audit

Spot-audit test quality for important pure logic. The goal is not a score; it is
finding the spots where behavior exists but no test would notice it breaking,
and closing exactly those.

## Preconditions

- Vitest 5 and Node 24+.
- A fast machine. The dry run collects coverage over the whole test suite; on a
  slow VM it can take 15+ minutes and makes the audit impractical. Run on the
  fastest machine available. Splitting execution (an agent runs it) from
  analysis is fine.

## Setup

Work in a throwaway worktree/branch; the setup changes are never committed.

1. `pnpm add -D @mizchi/mutator`
2. `mutator.config.ts`:

   ```ts
   import { defineConfig } from "@mizchi/mutator";

   export default defineConfig({
     include: ["src/lib/<target>.ts"],
     excludedMutators: ["StringLiteral"],
     reporters: ["text", "json"],
   });
   ```

3. Add `.mutator/` to `.gitignore`.
4. Run with `pnpm exec mutator` (there is no `run` subcommand).

## Target selection

- Pure logic only: sorting/comparison, classification, date math, URL parsing,
  state derivation. Skip UI, jsdom component tests, locale/contract pins, and
  anything whose tests are mostly rendering.
- Start with 2–4 files that already have unit tests. Roughly 300 mutants ≈ 4–6
  minutes on a fast laptop.

## Reading the result

- Killed / Survived / Timeout / CompileError. CompileError mutants are rejected
  by the type checker and are outside the score denominator.
- Timeout counts as detected. Timeout counts inflate under machine load and
  vary between runs; a mutant that times out on every run may be
  non-terminating when mutated — note it, do not chase it.

## Classifying survivors

Every survivor gets exactly one class, decided by reading the code:

- Real gap: an observable behavior changes and a test could catch it. Write
  the test.
- Equivalent: no input can observe the change. Prove it from the code
  before claiming it — typical proofs: a downstream fallback returns the same
  value; the mutated condition is always true at the point it is reached; a
  comparator stage is structurally redundant because its keys are a function of
  the earlier keys, so it can never decide alone. Document equivalents in the
  PR/brief; do not write tests for them and do not chase the score.
- Timeout: detected; see above.

## Writing tests that kill mutants

- Make the stages disagree. Fixtures where two sort keys (or branches) always
  point the same way hide gaps: removing one stage changes nothing. Build
  adversarial fixtures where the stage under test is the only one that can
  produce the expected order.
- Comparator operand position matters. Sort implementations do not compare
  every pair in both orders; a mutant in one operand's fallback can survive
  depending on input order. Exercise both input orders (normal and reversed)
  and expect the same output.
- Pin boundaries with equal values in different representations, e.g. the same
  instant written with different UTC offsets distinguishes `>` from `>=`.
- Check error-type contracts separately from happy paths: empty,
  whitespace-only, and invalid inputs may map to different error kinds, and a
  redundant-looking trim can be the only thing separating them.
- Follow the project's test policy: a new test must name a concrete bug it
  catches. If it cannot, the mutant is probably equivalent — prove that
  instead.

## Loop and exit criteria

1. Trial run → classify → add tests (test-only PR) → full re-run.
2. Exit when targeted survivors reach zero. Equivalent survivors remain,
   documented.
3. Production code stays unchanged. If classification proves code redundant,
   report it as a finding; simplifying it is a separate decision.

## Reporting

Before/after score, the per-survivor classification table, which tests killed
which mutants, and what was deliberately not done (equivalents and why).
