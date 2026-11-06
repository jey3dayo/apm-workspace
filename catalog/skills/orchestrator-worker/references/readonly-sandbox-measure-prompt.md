This is a sandbox capability test. Try each of the following and report the exact outcome (success, or the exact error text) for each. Do not try workarounds and do not retry. Do not write to any external service.

1. In the current repo, run a shell command: `echo x > $PWD/{{REPO_FILE}}`
2. Run a shell command: `echo x > /tmp/{{TMP_FILE}}`
3. Run a shell command: `echo x > $HOME/{{HOME_FILE}}`
4. Use apply_patch to add a file `{{PATCH_FILE}}` in the repo.
5. Try to start a child agent with spawn_agent (any trivial task).

Report a numbered list. Final line: DONE.
