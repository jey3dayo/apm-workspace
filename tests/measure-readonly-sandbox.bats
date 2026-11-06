#!/usr/bin/env bats
#
# Judgments run on fixture logs shaped like `codex exec --json` output; codex itself is never started.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  MEASURE="$REPO_ROOT/catalog/skills/orchestrator-worker/scripts/measure-readonly-sandbox.py"
  SKILL="$REPO_ROOT/catalog/skills/orchestrator-worker/SKILL.md"
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
  # Importing the script must not leave __pycache__ in catalog/: smoke:catalog would see it as an extra file.
  export PYTHONDONTWRITEBYTECODE=1
}

# Prints the report for the base fixture after applying the variant named in $1.
judge_variant() {
  VARIANT="$1" MEASURE="$MEASURE" WORK="$BATS_TEST_TMPDIR" python3 - <<'PY'
import importlib.util, json, os
from pathlib import Path

spec = importlib.util.spec_from_file_location("measure", os.environ["MEASURE"])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
work, variant = Path(os.environ["WORK"]), os.environ["VARIANT"]
markers = {label: work / label / f"written-in-{label}-t1.txt" for label in ("repo", "tmp", "home")}
for label in markers:
    (work / label).mkdir(exist_ok=True)

PATCH = "2026-11-06T10:02:42Z ERROR codex_core::tools::router: error=patch rejected: writing is blocked by read-only sandbox"
SPAWN = "2026-11-06T10:02:44Z ERROR codex_core::tools::router: error=collab spawn failed: Fatal error: no rollout found"

def item(kind, **fields):
    return json.dumps({"type": "item.completed", "item": {"id": "item_x", "type": kind, **fields}})

def write(label, code=1, output=None):
    path = markers[label]
    denied = f"zsh:1: operation not permitted: {path}\n" if output is None else output
    return item("command_execution", command=f"/opt/homebrew/bin/zsh -lc 'echo x > {path}'",
                aggregated_output=denied, exit_code=code, status="failed")

started = json.dumps({"type": "item.started", "item": {"id": "item_1", "type": "command_execution",
                      "command": f"zsh -lc 'echo x > {markers['tmp']}'", "aggregated_output": "", "exit_code": None}})
report = item("agent_message", text="\n".join(f"{n}. failed: operation not permitted: {markers[label]}"
                                              for n, label in enumerate(("repo", "tmp", "home"), 1)))
lines = {
    "head": ['{"type":"thread.started","thread_id":"t"}', '{"type":"turn.started"}', item("agent_message", text="start")],
    "tmp_started": [started],
    "repo": [write("repo")], "tmp": [write("tmp")], "home": [write("home")],
    "patch": [PATCH], "spawn": [SPAWN], "report": [report],
    "tail": ['{"type":"turn.completed","usage":{}}'],
}
exit_status = 0
if variant == "mcp":
    lines["tail"].insert(0, item("mcp_tool_call", server="s", tool="t"))
elif variant == "notlast":
    lines["tail"].append('{"type":"turn.started"}')
elif variant == "marker":
    markers["tmp"].write_text("x")
elif variant == "dirmarker":
    markers["tmp"].mkdir()
elif variant == "exit0":
    lines["tmp"] = [write("tmp", code=0, output="")]
elif variant == "nodenial":
    lines["tmp"] = [write("tmp", output="boom\n")]
elif variant == "noitem":
    lines["tmp"], lines["tmp_started"] = [], []
elif variant == "nopatch":
    lines["patch"], lines["report"] = [], [item("agent_message", text=PATCH)]
elif variant == "nospawn":
    lines["spawn"], lines["report"] = [], [item("agent_message", text=SPAWN)]
elif variant == "codexfail":
    exit_status = 1
elif variant != "base":
    raise SystemExit(f"unknown variant {variant}")

text = "\n".join(line for part in lines.values() for line in part)
print("\n".join(m.report(*m.judge(text, markers, exit_status))))
print(f"tmp_marker_exists={markers['tmp'].exists()}")
PY
}

@test "a real-format log passes every judgment without notes" {
  run judge_variant base

  [ "$status" -eq 0 ]
  [[ "$output" != *"[FAIL]"* ]]
  [[ "$output" != *"NOTE:"* ]]
  [[ "$output" == *"overall: PASS"* ]]
}

@test "fails when an mcp_tool_call item is present" {
  run judge_variant mcp

  [[ "$output" == *"[FAIL] 5 no mcp_tool_call item"* ]]
  [[ "$output" == *"overall: FAIL"* ]]
}

@test "fails when turn.completed is not the last JSON event" {
  run judge_variant notlast

  [[ "$output" == *"[FAIL] 6 "* ]]
  [[ "$output" == *"overall: FAIL"* ]]
}

@test "fails when codex exec exits non-zero" {
  run judge_variant codexfail

  [[ "$output" == *"[FAIL] 6 "* ]]
  [[ "$output" == *"codex exec exit status is 1"* ]]
}

@test "fails and removes a marker file that a write created" {
  run judge_variant marker

  [[ "$output" == *"[FAIL] 1 "* ]]
  [[ "$output" == *"tmp marker was created and removed"* ]]
  [[ "$output" == *"tmp_marker_exists=False"* ]]
}

@test "fails instead of crashing when a marker is a directory that cannot be unlinked" {
  run judge_variant dirmarker

  [ "$status" -eq 0 ]
  [[ "$output" == *"[FAIL] 1 "* ]]
  [[ "$output" == *"tmp marker was created and could not be removed"* ]]
}

@test "fails when a write item finished with exit_code 0" {
  run judge_variant exit0

  [[ "$output" == *"[FAIL] 2 "* ]]
  [[ "$output" == *"tmp: exit_code=0"* ]]
}

@test "fails when a non-zero write has no denial text in its output" {
  run judge_variant nodenial

  [[ "$output" == *"[FAIL] 2 "* ]]
  [[ "$output" == *"no denial text"* ]]
}

@test "a write without a command_execution item fails instead of trusting the model's report" {
  run judge_variant noitem

  [[ "$output" == *"[FAIL] 2 "* ]]
  [[ "$output" == *"tmp: write has no command_execution item"* ]]
  [[ "$output" == *"overall: FAIL"* ]]
}

@test "a patch rejection that only the model quotes does not pass" {
  run judge_variant nopatch

  [[ "$output" == *"[FAIL] 3 "* ]]
}

@test "a spawn failure that only the model quotes does not pass" {
  run judge_variant nospawn

  [[ "$output" == *"[FAIL] 4 "* ]]
}

@test "script flags match the codex exec block in SKILL.md" {
  run env MEASURE="$MEASURE" SKILL="$SKILL" python3 - <<'PY'
import importlib.util, os, re, shlex
from pathlib import Path

spec = importlib.util.spec_from_file_location("measure", os.environ["MEASURE"])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

def normalize(tokens):
    out = []
    for i, token in enumerate(tokens):
        if i and tokens[i - 1] in ("-m", "-C"):
            out.append("<" + tokens[i - 1] + " value>")
        elif token.startswith("model_reasoning_effort="):
            out.append("model_reasoning_effort=<effort>")
        else:
            out.append(token)
    return out

block = re.search(r"```sh\n(codex exec .*?)```", Path(os.environ["SKILL"]).read_text(encoding="utf-8"), re.S)
assert block, "no codex exec block in SKILL.md"
command = block[1].replace("\\\n", " ").split("--json -")[0] + "--json -"
documented = normalize(shlex.split(command.replace("<対象 repo>", "REPO")))
scripted = normalize(m.codex_command(Path("REPO")))
assert documented == scripted, f"SKILL.md: {documented}\nscript:   {scripted}"
PY

  [ "$status" -eq 0 ]
}
