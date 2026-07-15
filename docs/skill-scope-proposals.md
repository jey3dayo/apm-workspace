# Skill Scope Proposals

最終更新: 2026-07-15  
対象: `~/.apm` のグローバルスキル運用者  
タグ: category/operations, category/skills, audience/maintainer

## 目的

グローバル APM に常時配布する必要がないスキルを、利用するリポジトリの
`apm.yml` へ移す候補を整理する。

この資料は移管の提案であり、ここに記載した候補を直ちに削除・移動するものではない。
実際の移管時は、対象リポジトリを一つ選び、repo-local の `apm.yml` で導入できることを
確認してから root `~/.apm/apm.yml` から外す。

## 判断基準

- 特定のフレームワーク、ランタイム、サービス、UIワークフローに強く依存する
- 使わないリポジトリでも毎回グローバル候補として読み込まれる
- upstream パッケージをそのまま repo-local に追加できる
- 認証情報、ブラウザセッション、ローカルアプリ、生成物などの境界を
  プロジェクト側へ閉じ込めた方が安全である
- 単に過去監査で未発火だっただけでは移管を確定しない。未発火データは
  補助根拠として扱い、スキルの適用範囲と対象リポジトリの実態を優先する

## 移管候補

### 優先度 A: 最初に対象リポジトリを決めて移管を検討

| 候補                                                                                                                              | 適用範囲                                       | 推奨配置                                      | 判断理由                                                                                             |
| --------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------- | --------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `agentation`, `agentation-self-driving`                                                                                           | Agentation を導入した Next.js / Web リポジトリ | 対象リポジトリの `apm.yml`                    | Agentation toolbar と実行中ブラウザが必須。未導入プロジェクトでは不要                                |
| `browser-harness`, `agent-browser`                                                                                                | ブラウザ自動化・Web UI 検証を行うリポジトリ    | 対象リポジトリの `apm.yml` または on-demand   | ブラウザセッションやプロジェクト固有のログイン状態と結び付く。二つを同時に残す場合は役割を明記する   |
| `react-doctor`, `vercel-composition-patterns`, `vercel-react-best-practices`                                                      | React / Next.js リポジトリ                     | 対象リポジトリの `apm.yml`                    | React 実装に限定され、非 React リポジトリには価値がない                                              |
| `baseline-ui`, `fixing-accessibility`, `fixing-metadata`, `fixing-motion-performance`, `web-design-guidelines`, `transitions-dev` | Web UI を実装・監査するリポジトリ              | 対象リポジトリの `apm.yml`                    | UI、HTML metadata、CSS motion など Web 固有の作業に限定される                                        |
| `slack-app-management`                                                                                                            | Slack App を実装・運用するリポジトリ           | `jey3dayo/apm-workspace/optional-skills#main` | workspace-owned skill。Slack App を持たないリポジトリへ配布する必要がないため、optional 化を実施する |

### 優先度 B: UI プロジェクト単位でまとめて移管を検討

| 候補                                                                        | 適用範囲                                                | 推奨配置                                                                                 | 判断理由                                                                                                                     |
| --------------------------------------------------------------------------- | ------------------------------------------------------- | ---------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `brand`, `design`, `design-system`, `slides`, `ui-styling`, `ui-ux-pro-max` | デザインシステム、UI 実装、スライド制作を持つリポジトリ | `nextlevelbuilder/ui-ux-pro-max-skill` の必要な `skills:` サブセットを repo-local に追加 | 同じ upstream バンドルにまとまっており、一括で global から外しやすい。`ui-ux-pro-max` は有用性が高いため、利用先確認後に移す |
| `frontend-design`, `design-md-workflow`, `design-system-review`             | UI / デザインレビューを持つリポジトリ                   | 対象リポジトリの `apm.yml`                                                               | デザイン作業のあるリポジトリにだけ意味がある。通常の backend / infra リポジトリでは不要                                      |
| `understand`, `understand-dashboard`                                        | 特定リポジトリのコード理解・可視化を行うとき            | 対象リポジトリの `apm.yml` または on-demand                                              | 解析対象のコードベースに結び付く。説明トークンは小さいため、削減効果よりスコープ分離を優先する候補                           |

### 優先度 B: 社内サービス・運用リポジトリへ移管を検討

| 候補                                 | 適用範囲                            | 推奨配置                   | 判断理由                                                       |
| ------------------------------------ | ----------------------------------- | -------------------------- | -------------------------------------------------------------- |
| `ca-pass`                            | CA PASS / OIDC 連携を持つリポジトリ | 対象リポジトリの `apm.yml` | サービス固有の認証・設定知識で、全リポジトリ共通ではない       |
| `mdb-api`, `notica-api`, `telma-api` | それぞれの社内 API を呼ぶリポジトリ | 対象リポジトリの `apm.yml` | API、VPN、環境変数、認証境界を利用側リポジトリへ閉じ込められる |

## 直ちに移管しないもの

次のスキルは、複数リポジトリで使う基盤・運用知識、または作業全般に横断的な
ガードレールなので、現時点ではグローバル維持を推奨する。

- APM 所有権・配布: `apm-usage`, `docs-entrypoint-review`, `docs-manager`
- 作業の安全性・検証: `systematic-debugging`, `verification-before-completion`,
  `test-driven-development`, `code-review`, `git-worktree`, `writing-plans`
- 横断的な調査・環境: `jina-web-research`, `cross-research`, `mcp-tools`, `mise`,
  `headroom`, `pc-ops`, `macos-troubleshooting`
- 個人環境・認証運用: `1password-item-ops`, `perman-aws-vault`
- ワークスペース運用: `caad-skill-deployer`, `work-log-maintenance`,
  `japanese-tech-writing`, `humanizer-ja`

`perman-aws-vault` は AWS リポジトリに限定できる面もあるが、複数の AWS リポジトリで
同じ認証導線を使う場合は global のままでもよい。移管するなら、対象リポジトリ側で
profile・credential 境界を明記してから行う。

## 移管手順

### upstream スキル

対象リポジトリで必要なスキルだけを追加する。

```bash
cd <target-repository>
apm install <package-ref> --skill <skill-id>
```

例えば UI バンドルから `banner-design` だけを使う場合は、次のようにする。

```bash
apm install nextlevelbuilder/ui-ux-pro-max-skill --skill banner-design
```

対象リポジトリで導入・検証できた後、`~/.apm/apm.yml` から重複する global ref または
skill subset を外し、`mise run check` と `mise run deploy` を実行する。

### workspace-owned スキル

この workspace が正本を持つスキルは、`catalog/skills/<id>/` から
`optional-skills/.apm/skills/<id>/` へ移し、optional package を利用側リポジトリから選択する。

```bash
cd <target-repository>
apm install jey3dayo/apm-workspace/optional-skills#main \
  --skill <skill-id>
```

### 実施単位

候補を一度に全て外さず、次の順で一つずつ確認する。

1. 対象リポジトリと実際の利用者を決める
2. repo-local `apm.yml` で install / check / 実作業を検証する
3. global root manifest から外す
4. `mise run deploy` 後に `~/.agents/skills` と `~/.claude/skills` の残存を確認する
5. この資料を更新し、移管済みの判断を `docs/package-decisions.md` に記録する

## 現時点の結論

最初の移管候補は、`agentation` 系、ブラウザ系、React/UI の検証系とする。
UI デザインバンドル全体と社内 API 系は、対象リポジトリを確定できた段階で次に進める。
横断的な安全性・APM・環境運用スキルは、今回の候補から外す。
