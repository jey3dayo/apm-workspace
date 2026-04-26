# Windows Shells for mise

Use this reference when the task involves `run_windows`, `config.windows.toml`, `windows_default_inline_shell_args`, `windows_default_file_shell_args`, or Windows-specific quoting and env var behavior.

## Identify the Actual Task Shell First

On Windows, the shell that mise uses for tasks is configurable and may differ from the interactive shell you started in.

Check:

- `windows_default_inline_shell_args`
- `windows_default_file_shell_args`
- any repository-local task overrides

Typical examples:

- `bash -lc`
- `pwsh -NoProfile -Command`
- `powershell.exe -NoProfile -Command`

Do not assume that `run_windows` means "this runs in PowerShell". It only means "this string is used on Windows".

## Match Task Syntax to the Configured Shell

### If the task shell is PowerShell

Use PowerShell syntax consistently:

- env vars: `$env:USERPROFILE`
- script invocation: `& "./scripts/task.ps1"`
- null redirection: `*> $null`
- statement chaining with `;`

Prefer:

```toml
run_windows = "& \"$env:USERPROFILE\\.config\\scripts\\tool.ps1\" validate"
```

Avoid mixing cmd syntax such as `%USERPROFILE%` into a PowerShell task body.

### If the task shell is bash

Use bash syntax consistently:

- env vars: `$HOME`
- quoting and escaping as bash, not PowerShell
- avoid raw PowerShell fragments unless you intentionally launch PowerShell as a subprocess

If you must call PowerShell from bash, treat it as a separate process boundary and quote accordingly.

## Prefer Relative Repository Paths in Project-Local Tasks

For repository-owned `mise.toml`, prefer repo-relative paths when possible:

```toml
run_windows = "& \"./scripts/apm-workspace.ps1\" validate"
```

This is usually more portable than embedding user-specific absolute paths.

Use an absolute path only when the task is intentionally user-global.

## Avoid Mixed Expansion Models

Common bad patterns:

- `%USERPROFILE%` inside a PowerShell task body
- `$env:USERPROFILE` inside a bash task body
- PowerShell redirection syntax in a shell that is actually bash

When debugging, reduce the task to a minimal probe that prints:

- the chosen shell
- the current working directory
- one expanded env var
- the exact script path being invoked

## Generated Files Need Source-of-Truth Discipline

Some repositories regenerate `mise.toml` or validate generated artifacts byte-for-byte.

In those repositories:

- update the template or generator, not only the generated `mise.toml`
- do not patch generated files in isolation if a refresh step will overwrite them
- check whether validation compares exact bytes, including trailing newlines or serialization shape

## Keep Generic Formatters Away from Exact Generated Outputs

If a repository validates generated files exactly, generic formatter tasks can create false failures.

Typical fixes:

- exclude generated directories or files from broad `format:*` tasks
- normalize those generated files through the repository's own generation or staging command instead
- keep exact-output validation and generic formatting responsibilities separate

## Review Checklist

1. Confirm which shell mise actually runs.
2. Confirm `run_windows` syntax matches that shell.
3. Check env var syntax and quoting.
4. Check whether the edited file is generated.
5. Check whether generic formatters touch generated outputs.
6. Re-run the repository's real verification path, not only ad hoc commands.
