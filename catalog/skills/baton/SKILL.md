---
name: baton
description: Hand the current work to another agmsg agent — write a handoff doc, send its path as one line.
argument-hint: "<recipient agent> [what the next session should focus on]"
disable-model-invocation: true
---

Pass the **baton**: the receiving agent gets a written handoff document plus a one-line pointer to it.

agmsg carries plain text only — never raw context or diffs (`~/.agents/skills/agmsg/README.md`, "What's carried on a handoff"). The doc is the payload; the message is the pointer.

## 1. Resolve the relay

Run `~/.agents/skills/agmsg/scripts/whoami.sh "$(pwd)" claude-code`. Each repository is registered in exactly one team, so `teams=` normally holds a single name — take it and do not ask. Ask which to use only when it returns more than one, which means the repository is double-registered and the roster needs fixing.

Run `~/.agents/skills/agmsg/scripts/team.sh <team>` and confirm the recipient appears in the roster. Agent names carry their runtime (`-cc`, `-codex`) because `send.sh` addresses by name alone, so picking the wrong suffix reaches the wrong runtime. A recipient absent from the roster means either a typo or an agent that has not run `join.sh` — resolve which with the user before sending.

Done when TEAM, FROM, and TO are all known-good roster names.

## 2. Write the doc

Follow the handoff message format in `agmsg-delegation`（「引き継ぎ（handoff）メッセージ」section）with one override: save to `<repo root>/tmp/baton/<topic>.md`, not the OS temp directory. That format assumes a same-user pickup; a baton crosses agents, so the doc lives where the peer can reach it.

Treat this skill's arguments as the next session's focus.

Done when the file exists and its "suggested skills" section names skills the recipient can actually invoke.

## 3. Send the pointer

```
~/.agents/skills/agmsg/scripts/send.sh <team> <from> <to> "<one-line summary> — <absolute path>"
```

The path must be absolute: the recipient's working directory is its own.

Done when send.sh exits zero.

## 4. Report

Give the user the document path and the send result.
