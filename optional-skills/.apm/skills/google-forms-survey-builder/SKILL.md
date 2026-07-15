---
name: google-forms-survey-builder
description: Use when creating, rebuilding, or updating a Google Forms survey from a Markdown survey spec such as SURVEY_QUESTIONS.md, especially when the form should stay synchronized with question text, required flags, Google Forms item types, scale labels, and removed-question notes.
---

# Google Forms Survey Builder

## Overview

Build the form from the Markdown spec, not from memory. Keep `SURVEY_QUESTIONS.md` and the Google Form synchronized, then verify the live form structure after every rebuild.

Use `references/SURVEY_QUESTIONS.md` as the initialization sample when creating a new spec from scratch. Use `references/survey-questions-format.md` when the Markdown spec is missing fields, uses an unfamiliar shape, or needs a new question type.

Before editing scripts or forms, check whether the required inputs are available. If they are not, ask for the missing input explicitly and stop at the highest safe preparation step.

Required inputs:

- A local Markdown survey spec, normally `SURVEY_QUESTIONS.md`.
- A Google Forms edit URL or form id when rebuilding an existing form.
- Authorization to run Apps Script when the current account has not granted it yet.

If the survey spec is missing, do not invent questions. Tell the user that the spec is required, mention the expected local filename, and ask them to add or provide the Markdown content.

If the Google Forms edit URL or form id is missing, do not claim the form was created or updated. You may inspect or improve the Markdown spec and prepare a rebuild script template, then ask the user for the edit URL or form id before live rebuild and verification.

## Workflow

### Phase 0: Readiness Check

1. Confirm the local workspace contains the requested survey spec. Normalize obvious filename typos in the user's request, such as `SURVER_QUESTIONS.md`, by looking for `SURVEY_QUESTIONS.md` in the current workspace.
2. If no survey spec exists, stop before Apps Script work and ask the user for one of:
   - initialize `SURVEY_QUESTIONS.md` from `references/SURVEY_QUESTIONS.md` after they confirm the survey purpose
   - add `SURVEY_QUESTIONS.md` to the workspace
   - paste the survey Markdown content
   - provide the correct path if the file is elsewhere
3. Confirm whether the user provided a Google Forms edit URL or form id.
4. If the form URL or id is missing, explain that live form rebuild and verification require it. Continue only with spec review or script preparation if useful.
5. If both the spec and the form target are available, proceed through the full rebuild workflow.

### Phase 1: Markdown Spec

1. Read the survey spec found in Phase 0 and identify:
   - form title and description
   - assumptions / target audience
   - all questions, in order
   - each question's format, required flag, help text, choices, and scale labels
   - deleted-question notes and judgment notes
2. When creating a new survey spec, start from `references/SURVEY_QUESTIONS.md` and replace the event-specific title, assumptions, description, questions, removed-question notes, and judgment notes.
3. Update the Markdown spec first when the requested change affects survey design. Treat the spec as the source of truth.
4. If the spec is missing fields, uses an unfamiliar shape, or needs a new question type, read `references/survey-questions-format.md`.

### Phase 2: Apps Script Rebuild

1. Use the Google Forms edit URL or form id confirmed in Phase 0 to identify the form id.
2. Generate or update an idempotent `rebuildSurveyForm()` Apps Script from the Markdown spec.
3. Keep the Apps Script question calls in the exact Markdown order.
4. For small surveys, read `references/apps-script-patterns.md` and use the compact helper pattern.
5. Save the script, run `rebuildSurveyForm()`, and wait for execution completion.
6. If Apps Script authorization is required, stop after preparing the script and ask the user to authorize before running it.

### Phase 3: Browser Verification

1. Reload the Google Forms edit page after the Apps Script run completes.
2. Verify the live form by reading the form structure, not just by trusting the editor UI.
3. Confirm item count, item-type counts, question order, scale bounds, scale labels, and required flags when accessible.
4. Compare the live form against `SURVEY_QUESTIONS.md`; if they differ, fix the script or spec and rerun Phase 2.
5. Report the final question count, item-type counts, and any forms settings that could not be verified.

## Markdown Mapping

Map the spec to Google Forms as follows:

| Spec format        | Google Forms item                 |
| ------------------ | --------------------------------- |
| `均等目盛`         | `FormApp.addScaleItem()`          |
| `ラジオボタン`     | `FormApp.addMultipleChoiceItem()` |
| `チェックボックス` | `FormApp.addCheckboxItem()`       |
| `段落`             | `FormApp.addParagraphTextItem()`  |
| `記述式`           | `FormApp.addTextItem()`           |

For scale questions:

- Use `目盛: 1 から N` as `setBounds(1, N)`.
- Use `目盛: 0 から N` as `setBounds(0, N)` only when the scale represents a ratio, share, or "0 means none" measurement.
- Use `左ラベル` and `右ラベル` as `setLabels(left, right)`.
- Do not invent a 0-based scale for sentiment, difficulty, satisfaction, confidence, or similar ratings.
- Prefer 1-5 for sentiment, difficulty, satisfaction, confidence, and similar ratings unless the spec explicitly asks for 1-10.
- Use 1-10 only when the user is asking for a ratio-like or high-resolution comparison and the labels make the endpoints clear.

For optional free text:

- Use paragraph items.
- Keep them optional unless the spec says `必須: はい`.
- Preserve user wording even when it is casual; survey phrasing is part of the design.

## Google Forms Rebuild

When using Apps Script, generate a single idempotent rebuild function:

```js
function rebuildSurveyForm() {
  const f = FormApp.openById("<form id>");
  f.setTitle("<title>");
  f.setDescription("<description>");
  f.getItems()
    .reverse()
    .forEach((item) => f.deleteItem(item));

  const M = (t, c, r = true, h = "") => {
    const i = f
      .addMultipleChoiceItem()
      .setTitle(t)
      .setChoiceValues(c)
      .setRequired(r);
    if (h) i.setHelpText(h);
    return i;
  };
  const C = (t, c, r = false, h = "") => {
    const i = f.addCheckboxItem().setTitle(t).setChoiceValues(c).setRequired(r);
    if (h) i.setHelpText(h);
    return i;
  };
  const S = (t, low, high, l, rr, r = true, h = "") => {
    const i = f
      .addScaleItem()
      .setTitle(t)
      .setBounds(low, high)
      .setLabels(l, rr)
      .setRequired(r);
    if (h) i.setHelpText(h);
    return i;
  };
  const P = (t, r = false, h = "") => {
    const i = f.addParagraphTextItem().setTitle(t).setRequired(r);
    if (h) i.setHelpText(h);
    return i;
  };
  const T = (t, r = false, h = "") => {
    const i = f.addTextItem().setTitle(t).setRequired(r);
    if (h) i.setHelpText(h);
    return i;
  };

  // Add items here in Markdown order.
}
```

Keep helper names short but readable. Remove unused helpers before finalizing the script if the form does not need that item type.

For small surveys, read `references/apps-script-patterns.md` and use the compact helper pattern so the script stays reviewable in Apps Script.

## Live Verification

After running the rebuild function:

1. Reload the Google Forms edit page.
2. Check that every question appears in the Markdown order.
3. Use `FB_LOAD_DATA_` or the visible DOM to verify:
   - item count
   - item-type counts
   - question titles
   - scale lower and upper bounds and labels
   - required vs optional status when accessible
4. If using `FB_LOAD_DATA_`, type values commonly include:
   - `1`: paragraph text
   - `2`: multiple choice
   - `4`: checkbox
   - `5`: scale
5. Report the exact verification result in the final answer.

## Design Checks

Before updating the form, sanity-check the survey:

- Remove questions that duplicate information already collected by a scale or free-text field.
- Prefer one clear comparison scale over separate usage-presence questions when the audience already uses the tools.
- Replace broad multiple-choice "impressions" questions with `よかったところ` and `分かりにくかったところ` free text when answer load matters.
- Keep the target question count explicit in the spec and update it when questions are added or removed.
- Keep deleted-question notes so future edits do not accidentally reintroduce dropped questions.

## Failure Handling

- If `SURVEY_QUESTIONS.md` or an equivalent local spec is missing, stop before script or form changes and ask the user to provide the spec path or content.
- If no Google Forms edit URL or form id is available, stop before live rebuild. Ask the user for the edit URL or form id, and clearly state that only local spec review or script preparation can happen until then.
- If the Google Form is not editable, update only the Markdown spec and report that the live form was not changed.
- If Apps Script authorization is required, stop after preparing the script and ask the user to authorize before running it.
- If the UI and script disagree, trust the live form verification and rerun the rebuild after fixing the script.
- Do not leave the Markdown spec saying "reflected in Google Forms" unless the live form was actually updated and verified.
