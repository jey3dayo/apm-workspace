---
name: slack-app-management
description: Slack app management knowledge for app settings, manifests, OAuth installs, scopes, bot users, Marketplace settings, App Home, display names, sender names, mrkdwn message formatting, and safe workspace-visible changes. Use when diagnosing or changing a Slack app, installed app, bot user, app label, DM header, chat sender, message text decoration, Slack links, block quotes, app approval/install state, token impact, Slack API app settings, Slack Marketplace settings, or stale Slack app name propagation.
---

# Slack App Management

Use this skill when Slack app behavior depends on multiple admin surfaces:
Slack API app settings, app manifests, workspace installation, Slack
Marketplace settings, Slack Web/Desktop UI, bot users, scopes, and tokens. Start
with read-only checks, identify the owner of the symptom, then change the
narrowest safe setting.

## Triage First

Map the user's symptom to the likely Slack owner before acting.

| Symptom or task                               | First place to inspect                                |
| --------------------------------------------- | ----------------------------------------------------- |
| App card/title/description is wrong           | Slack API `Basic Information` or app manifest         |
| Message sender icon / app avatar is wrong     | Slack API `Basic Information` -> `App icon & Preview` |
| App Home title or bot display name is wrong   | Slack API `App Home` / manifest `features.bot_user`   |
| DM header or message sender shows an old name | Slack Marketplace app page `Settings` -> Bot User     |
| App is installed in the wrong workspace       | Slack API app selector and `Install App` page         |
| Scopes, approvals, or permissions look wrong  | Slack API `OAuth & Permissions` and workspace admin   |
| Token may rotate or install state may change  | `Install App`, reinstall, uninstall, OAuth flow       |
| Message identity needs a one-off override     | `chat.postMessage` plus `chat:write.customize`        |
| Message text has bold, link, or quote styling | Slack `mrkdwn` message formatting                     |
| Slack UI and API settings disagree            | Verify both Slack Web message UI and API settings     |

## Message Formatting

Slack message text decoration is usually `mrkdwn`, not generic Markdown. Use
this when the visible Slack message has inline styling such as bold labels,
links, inline code, or a left vertical quote bar.

Common `mrkdwn` patterns:

- Bold label or heading: `*申請者*`
- Clickable text link: `<https://example.com|申請詳細>`
- Inline code or literal value: `` `production` ``
- Quote block with vertical bar: `> 申請内容を確認...`

For compact notification text, prefer `mrkdwn` in the message body. Use plain
line breaks and spacing for label/value rows, but do not rely on Slack to align
columns perfectly across clients or fonts.

`mrkdwn` is only text formatting. Use Block Kit when the request needs
structured sections, fields, buttons, dividers, or other interactive Slack UI.

## Name Surfaces

Slack exposes several related names. Identify which one is wrong before editing.

| Visible problem                         | Likely owner                                                     |
| --------------------------------------- | ---------------------------------------------------------------- |
| Marketplace/app detail title is wrong   | Slack app `Basic Information` app name or manifest name          |
| App Home title or app details are wrong | `App Home` Display Name / Bot Name or manifest `bot_user` name   |
| DM header or message sender is wrong    | Installed workspace bot user name in Slack Marketplace settings  |
| `@handle` is wrong                      | Bot username/handle; may be separate from display name           |
| One message needs a temporary name      | `chat.postMessage` `username` override, not the app profile name |

## Display Surface Checklist

Slack app identity commonly has three separate admin surfaces. Check all three
before concluding a change did not propagate.

1. Slack API `Basic Information`
   - URL pattern: `https://api.slack.com/apps/<APP_ID>/general`.
   - `Display Information` owns the app card name, short description,
     background color, and `App icon & Preview`.
   - The small icon shown beside app/bot messages can come from this app icon.
2. Slack API `App Home`
   - URL pattern: `https://api.slack.com/apps/<APP_ID>/app-home`.
   - `Edit` owns the app home display name and username/handle fields.
   - This surface does not expose the app icon upload field.
3. Slack Marketplace app page `Settings`
   - URL pattern:
     `https://<workspace>.slack.com/marketplace/<APP_ID>-<slug>?tab=settings`.
   - `Settings` -> `Edit` may expose the installed workspace bot user name.
   - This can control the sender name visible to workspace members even when
     the Slack API app name already looks correct.

For a message like `CA Connect` with an app badge and a stale sender icon, open
`Basic Information` first and inspect `App icon & Preview`. If the name is the
problem, also inspect `App Home` and the Marketplace `Settings` tab.

## Rename Workflow

1. Confirm the symptom in Slack:
   - Open the DM or channel message where the stale name appears.
   - Compare the DM header, message sender, app details dialog, and Overview tab.
   - If app details show the new app name but the DM header/sender shows the old
     name, treat it as an installed bot user name problem.
2. Verify app-level settings before changing the workspace bot user:
   - In Slack API app settings, check `Basic Information` -> app name.
   - If the message icon/avatar is wrong, check `Basic Information` ->
     `Display Information` -> `App icon & Preview`.
   - Check `App Home` -> Display Name / Bot Name.
   - If using a manifest, check `display_information.name` and
     `features.bot_user.display_name`.
3. Inspect the installed app in the workspace:
   - Open Slack Marketplace for the app, usually
     `https://<workspace>.slack.com/marketplace/<APP_ID>-<slug>`.
   - Open the `Settings` tab.
   - Look for `Bot User` / `ボットユーザー`.
   - If it shows the stale name, use `Edit` / `編集` there. This is the setting
     that controls the bot name shown to workspace members.
4. Save only after confirming blast radius:
   - The edit dialog may say the name is visible to all workspace members.
   - Treat `Save changes` as a workspace-visible modification and confirm with
     the user immediately before clicking it unless the user explicitly approved
     that exact save action.
5. Verify with a fresh view:
   - Reload Slack Web or restart Slack Desktop if necessary.
   - Send or trigger a low-risk smoke notification when available.
   - Check the newest message sender and the DM header, not only the app detail
     modal.

## Install And Token Safety

- Treat app creation, OAuth authorization, reinstall, uninstall, approval
  requests, token rotation, and scope changes as workspace/account impacting
  operations.
- Before reinstalling, check whether the current bot token prefix remains the
  same after prior installs, but do not print full tokens.
- Explain that app registration/approval permissions and app installation
  permissions can be different in Slack Enterprise environments.
- Prefer UI inspection and non-mutating API calls before reinstalling.
- If a reinstall is necessary, confirm immediately before the OAuth approval
  button or any action that can alter token/install state.

## Tool Use

- Prefer Chrome for authenticated Slack API, Slack Marketplace, and Slack Web
  pages because it has the user's profile and session.
- Use Computer Use when Slack Desktop state matters or when Chrome automation
  cannot expose native UI.
- Keep initial navigation and inspection read-only. Do not click uninstall,
  delete, remove app, permission changes, OAuth approvals, or token creation
  controls without action-time confirmation.
- Do not inspect or print OAuth tokens, cookies, local storage, or secrets. If a
  token value must be compared, compare masked prefixes or presence only.

## Research Hints

When live behavior is unclear, verify against current official Slack docs first,
then community reports for propagation quirks. Useful terms:

- `Slack App Home display name bot user`
- `Slack Marketplace bot user edit`
- `Slack app installed bot user name`
- `Slack chat.postMessage username chat:write.customize`
- `Slack users.profile.set bot user display_name`
- `Slack app reinstall token rotate`

## Escalation

Try these only when the Marketplace bot user edit is unavailable or does not
propagate:

- Re-save the app icon or related app metadata as a low-risk propagation nudge,
  but avoid uploading new assets without explicit approval.
- Use `users.profile.set` only with an appropriately scoped user token and a
  clear user/admin approval path. Do not request, print, or store the token in
  chat. This can target the bot user id when permissions allow it.
- Consider reinstall only after explaining token and approval risk. Reinstall or
  uninstall may affect install state, bot token validity, app approvals, and
  workspace access. It is not the first fix for a stale display name.
- Treat `chat:write.customize` and per-message `username` overrides as message
  presentation workarounds. They do not fix the installed app profile or DM
  header.

## Useful Observations

- The Slack app management page can show scopes like `chat:write` as
  `@New App Name` while the actual Slack DM sender still shows the old bot user
  name. Verify in the message UI.
- Slack Web's app details dialog may show the correct app name while the
  conversation title remains stale. That points to a bot user/profile setting,
  not a Basic Information problem.
- The installed app management profile page is useful for permissions and
  approval state, but the bot user edit may live under the Marketplace app page
  `Settings` tab.
