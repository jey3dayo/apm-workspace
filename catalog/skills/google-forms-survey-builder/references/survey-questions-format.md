# Survey Questions Markdown Format

Use this format when creating or repairing a `SURVEY_QUESTIONS.md` source file.

## Required Sections

````md
# <date or event> アンケート設問

Google Forms 反映用の設問メモ。

## 前提

- <audience and design assumptions>
- <what the survey should and should not measure>
- <target question count>

## フォームタイトル

```text
<Google Forms title>
```

## フォーム説明

```text
<Google Forms description>
```

## 設問

### 1. <question title>

- 形式: <均等目盛 | ラジオボタン | チェックボックス | 段落 | 記述式>
- 必須: <はい | いいえ>
- 補足:
  - <help text when needed>
- 目盛: 1 から <N>
- 左ラベル: <left endpoint>
- 右ラベル: <right endpoint>

## 削った設問

- <questions intentionally removed>

## 判断メモ

<why the final structure was chosen>
````

## Question Blocks

Scale:

```md
### 1. <title>

- 形式: 均等目盛
- 必須: はい
- 補足:
  - <optional help text>
- 目盛: 1 から 5
- 左ラベル: <low endpoint>
- 右ラベル: <high endpoint>
```

Multiple choice:

```md
### 2. <title>

- 形式: ラジオボタン
- 必須: はい
- 選択肢:
  - <choice 1>
  - <choice 2>
  - <choice 3>
```

Checkbox:

```md
### 3. <title>

- 形式: チェックボックス
- 必須: いいえ
- 選択肢:
  - <choice 1>
  - <choice 2>
  - その他
```

Paragraph:

```md
### 4. <title>

- 形式: 段落
- 必須: いいえ
```

## Design Heuristics

- Put the most important quantitative questions first.
- Keep follow-up free-text fields optional.
- Use one free-text field per intent; do not split "good points" into multiple near-duplicates.
- Keep wording aligned with the audience's vocabulary.
- Add a judgment note whenever a likely future question is intentionally removed.
