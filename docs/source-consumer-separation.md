# authoring source と consumer の global state を分ける（第 1 段階の検証）

- Status: 検証だけ（2026-11-09、APM 0.35.0）。本番の `apm.yml`・`apm.lock.yaml`・`catalog/`・配布の手順は変えていない。分離の実施（第 2 段階。自作の writer の撤去や改名）は承認されていない
- テスト: `tests/apm-source-consumer-separation.bats`。`mise run test:sh` に含まれ、CI と、対象のファイルを変えた push の pre-push でも走る。テストは APM 0.35.0 であることを確かめ、別のバージョンでは止まる（APM を上げるときは、この文書の内容を確かめ直してからテストの期待値を上げる）。fixture は既定で bats の一時ディレクトリに作り、`APM_SEPARATION_FIXTURE_ROOT` を指定するとその下に作る。どちらの場合も、その場所が呼び出し元の HOME そのもの・その祖先、または HOME の `.apm`・`.claude`・`.codex`・`.cursor`・`.agents`・`.config`・`.cache`・`.local`・`Library` の中なら、何も作らずに止まる（HOME の中の作業用ディレクトリは使える）

## 何と何を分けるのか

- authoring source: APM package を書いて commit する git repo。今は `~/.apm` の `catalog/` と `manual-skills/`
- consumer の global state: APM が user scope で読み書きする `~/.apm/apm.yml`・`~/.apm/apm.lock.yaml`・`~/.apm/apm_modules/` と、配布先の `~/.claude`・`~/.codex`・`~/.cursor`・`~/.agents/skills`

今は両方が同じ `~/.apm` の checkout にある。分けられるかどうかは、APM が user scope の場所を何で決めているかで決まる。

## APM 0.35.0 の仕組み（ソース）

- `core/scope.py`: user scope の manifest と metadata は `Path.home() / ".apm"`、配布先は `Path.home()` に置く（`get_source_root`・`get_apm_dir`・`get_deploy_root`）。HOME だけで決まり、cwd は使わない
- `install/package_resolution.py`: user scope では相対パスの local 依存を拒否し、絶対パスは受け付ける
- `install/phases/local_content.py`: user scope の source root は HOME なので、`~/.apm/` 自体が project の `.apm/` として読まれる。その直下の `skills`・`instructions`・`chatmodes`・`agents`・`prompts`・`hooks`・`commands`・`extensions` に置いたファイルは、依存と別に local content として配られる
- `utils/version_checker.py`: `~/.cache/apm/last_version_check` が 1 日以内に更新されていれば、新しいリリースを GitHub に問い合わせない

## テストで確かめたこと

テストは合成した authoring repo（`catalog`・`manual-skills`・`unguarded` の 3 package、v1 と v2 の commit、未 commit の v3 の編集）と、使い捨ての consumer HOME で実 APM を動かす。

- consumer は authoring repo の package を SHA で pin して `apm install -g` できる。lock の `resolved_commit` は pin と一致し、authoring repo には lock も `apm_modules` も作られず、`git status` も変わらない
- 3 つの tool への配布: Claude には skills・agent・rule、Codex には `~/.agents/skills` の skills と `~/.codex/AGENTS.md`、Cursor には agent と `~/.cursor/AGENTS.md` が届く。配布先のファイル一覧が期待と完全に一致する
- `apm install -g` は root を書かない。`apm compile -g --clean` が Codex と Cursor の root を書き、目印の無い手書きの `~/.claude/CLAUDE.md` は残す
- install と compile をもう一度実行しても、HOME の中のファイルと symlink（パスと内容、リンク先）は変わらない。比べないのは `.cache`・`Library`・`.apm/deployment-receipts`・`.apm/apm_modules` と、空のディレクトリやパーミッション。新しい別の HOME で同じ manifest から入れても、lock は byte 単位で同じになる
- authoring repo に commit を足しても、作業ツリーを編集しても、pin を動かすまで consumer には届かない。pin を v2 に動かすと v2 の内容が届き、未 commit の v3 は届かない
- APM の持ち物ではないファイル（private skill のコピーと symlink、Herdr が置く skill、`~/.codex/config.toml`、`~/.claude/settings.json`、手書きの `CLAUDE.md`）は、install・再実行・pin の更新のあとも変わらない
- package の `targets` から codex を外すと（`catalog/apm.yml` と同じ形）、制限付きの agent は Codex に配られない。外さないと APM は `~/.codex/agents/*.toml` を書き、`disallowedTools` は落ちる。外す理由は `docs/package-decisions.md` の Codex 変換の却下
- consumer の `~/.apm/skills/` に置いた skill は配られる。cwd を authoring repo にしても、authoring repo の `.apm/` は読まれない
- この checkout（本番では `~/.apm` を兼ねる）の最上位には、上の 8 つの名前のディレクトリが無い

## 分離するときの最小の manifest と lock

consumer の manifest は authoring repo の外（consumer の `~/.apm/apm.yml`）に置き、authoring source を commit SHA で pin する。

```yaml
name: <consumer>
version: 1.0.0
targets:
  - claude
  - codex
  - cursor
  - agent-skills
dependencies:
  apm:
    - git: https://github.com/<owner>/<authoring-repo>.git
      path: catalog
      ref: <commit SHA>
    - git: https://github.com/<owner>/<authoring-repo>.git
      path: manual-skills
      ref: <commit SHA>
```

- 再現性は「pin が commit SHA で、lock の `resolved_commit` がそれと一致する」ことで取る。`validate:workspace` が外部依存の pin に課している条件と同じ
- 今の `catalog#main` と `manual-skills#main` が浮動の ref なのは、manifest が authoring repo の中にあり、自分の commit の SHA を自分に書くと循環するため。manifest を外に置けば、この循環は無くなる
- `targets` は明示する。書かないと、APM が検出した tool（たとえば `~/.config/opencode` があれば OpenCode）にも配る（2026-11-08 の実測）
- Codex を外す `targets` は consumer ではなく package 側（`catalog/apm.yml`）に置く。consumer の `targets` は skills と root のために codex を含む
- 絶対パスの local 依存は lock に commit が残らず（`source: local` と `local_path`）、作業ツリーの中身をそのまま配る。再現性の根拠には使わない
- consumer の `~/.apm` には metadata（manifest・lock・`apm_modules`）だけを置く。上の 8 つの名前のディレクトリを作ると、その中身が global に配られる
- install のあとに `apm compile -g --clean` が要る。目印は生成物の編集を守らないので、編集された Codex・Cursor の root で compile を止める今のガード（`compile_user_root_contexts`）は分離後も要る

## 隔離と保証の範囲

テストの apm は、次の条件で動く。

- `env -i` で起動し、渡す環境変数は `HOME`・`TMPDIR`・`PATH`・`LANG`・`PYTHONUTF8`・`GIT_CONFIG_GLOBAL`・`GIT_CONFIG_NOSYSTEM` だけ。呼び出し側が token・proxy・askpass・SSH agent・`XDG_CONFIG_HOME` を export していても届かないことをテストで確かめる
- git が読む設定は fixture の global config と authoring repo の `.git/config` だけで、system の設定は読まない。credential・include・`http.*`・askpass・`core.sshCommand` の項目が無いこともテストで確かめる。利用者の global git config は読みも書きもしない
- 依存の host は解決できない `fixture.invalid` で、fixture の git config の `insteadOf` がローカルの repo に向ける。これは通信を不可能にするものではなく、通信先を持たせないための設定である
- HOME と `TMPDIR` は fixture root の中に置く。HOME は物理パスに直してから比べ、fixture の `homes/` の直下でない（`..` や symlink で外を指す場合を含む）か呼び出し元の HOME なら、何も起動しない。この拒否もテストで確かめる
- macOS（`sandbox-exec` がある）: profile が通信と fixture root の外への書込みを拒否する。開始前に外への書込みが失敗することを確かめ、成功したら全テストを止める。通信は、sandbox の外では応答する loopback のサーバーに、sandbox の中からは接続できないことで確かめる。外部ホストへの接続は試していない
- Linux（CI）など `sandbox-exec` が無い環境: 通信も書込みも強制的には止めない。保証できるのは、上の環境変数と git 設定の隔離、HOME のガード、外へ向かう設定や認証情報を持たないことまで。通信のテストは skip になる

確かめていないこと:

- 実際の GitHub からの取得。APM が token のある環境で git 設定を自前の隔離設定に切り替える経路（`core/auth.py`）も通っていない
- sandbox の無い環境（CI）で、APM が更新確認のほかに外へ通信しないこと
- APM が持つ skill ディレクトリの中に置いた runtime のリンク（agmsg の `db`・`teams`）。今の apply の save/restore が要るまま
- Claude Code が rule を実際に読み込むか。Windows での動作

## 第 2 段階（未承認）

consumer の manifest を repo の外へ移し、自作の skills writer を APM の install に置き換える作業。`todo.txt` に残してあり、実施には利用者の承認が要る。
