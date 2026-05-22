# Apps Script Patterns

Use these patterns when rebuilding a Google Form from `SURVEY_QUESTIONS.md`.

## Compact Helper Pattern

For small surveys, prefer compact helper functions. They are easy to review in Apps Script and keep the form definition close to the Markdown order.

```js
function rebuildSurveyForm() {
  const f = FormApp.openById("<form id>");
  f.setTitle("<form title>");
  f.setDescription("<form description>");
  f.getItems()
    .reverse()
    .forEach((item) => f.deleteItem(item));

  const S = (title, max, left, right, required = true, help = "") => {
    const item = f
      .addScaleItem()
      .setTitle(title)
      .setBounds(1, max)
      .setLabels(left, right)
      .setRequired(required);
    if (help) item.setHelpText(help);
    return item;
  };
  const P = (title, required = false, help = "") => {
    const item = f.addParagraphTextItem().setTitle(title).setRequired(required);
    if (help) item.setHelpText(help);
    return item;
  };
  const T = (title, required = false, help = "") => {
    const item = f.addTextItem().setTitle(title).setRequired(required);
    if (help) item.setHelpText(help);
    return item;
  };

  S(
    "直近1ヶ月の開発で、Claude Code と Codex の利用割合はどれくらいですか",
    10,
    "Claude Code 10割",
    "Codex 10割",
    true,
    "1 は Claude Code 寄り、10 は Codex 寄りとして答えてください。",
  );
  S("今日のハンズオンの難易度はどうでしたか", 5, "難しすぎた", "簡単すぎた");
  P("特によかったところがあれば教えてください");
}
```

Before running:

- Make every helper return the created item so help text can be chained or set inside the helper.
- Keep the item calls in the exact `SURVEY_QUESTIONS.md` order.
- Remove unused helper definitions such as checkbox or radio helpers when the final survey does not use them.
- Keep help text synchronized with the Markdown spec; do not silently drop clarifying notes.

## Full Helper Pattern

Use the broader helper set when the survey mixes scale, radio, checkbox, and free-text questions.

```js
const M = (title, choices, required = true, help = "") => {
  const item = f
    .addMultipleChoiceItem()
    .setTitle(title)
    .setChoiceValues(choices)
    .setRequired(required);
  if (help) item.setHelpText(help);
  return item;
};
const C = (title, choices, required = false, help = "") => {
  const item = f
    .addCheckboxItem()
    .setTitle(title)
    .setChoiceValues(choices)
    .setRequired(required);
  if (help) item.setHelpText(help);
  return item;
};
const S = (title, max, left, right, required = true, help = "") => {
  const item = f
    .addScaleItem()
    .setTitle(title)
    .setBounds(1, max)
    .setLabels(left, right)
    .setRequired(required);
  if (help) item.setHelpText(help);
  return item;
};
const P = (title, required = false, help = "") => {
  const item = f.addParagraphTextItem().setTitle(title).setRequired(required);
  if (help) item.setHelpText(help);
  return item;
};
const T = (title, required = false, help = "") => {
  const item = f.addTextItem().setTitle(title).setRequired(required);
  if (help) item.setHelpText(help);
  return item;
};
```
