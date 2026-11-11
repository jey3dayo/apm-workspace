#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}

@test "versioned model IDs only appear in the policy source and runtime mirrors" {
  local matches pattern
  pattern='gpt-[0-9]+(\.[0-9]+)?-[a-z][a-z0-9]*(-[a-z0-9]+)*|claude-((fable|opus|sonnet|haiku)-[0-9]+(-[0-9]+)+|[0-9]+(-[0-9]+)+-(fable|opus|sonnet|haiku))(-[a-z0-9]+)*|(opus|sonnet|haiku)[ -][0-9]+(\.[0-9]+)?|grok-[0-9]+(\.[0-9]+)?'

  matches="$(
    git -C "$REPO_ROOT" grep -nE "$pattern" -- \
      . \
      ':(exclude)catalog/.apm/skills/orchestrator-worker/references/models.md' \
      ':(exclude)catalog/.apm/skills/agmsg-delegation/scripts/run-codex-worker.sh' \
      ':(exclude)catalog/.apm/skills/agmsg-delegation/scripts/run-cursor-worker.sh' \
      ':(exclude)tests/run-codex-worker.bats' \
      ':(exclude)tests/run-cursor-worker.bats' \
      || true
  )"

  [ -z "$matches" ] || {
    printf 'versioned model IDs found outside policy source or runtime mirrors:\n%s\n' "$matches" >&2
    return 1
  }
}
