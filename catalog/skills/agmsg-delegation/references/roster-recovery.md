# agmsg roster recovery

`~/.agents/skills/agmsg/{db,teams}` が symlink を失ったときの診断と復旧手順。save/restore の実装契約（`mise run apply` がどう save/restore を回すか）は `~/.apm/AGENTS.md` の「agmsg State」が正本で、ここでは扱わない。

## 症状

- `team.sh` が `Team not found` を返す
- `identities.sh` が空を返す

## 原因

`db` / `teams` は `${XDG_STATE_HOME:-~/.local/state}/agmsg/` への symlink であるべきだが、`apm install -g` の素の実行や `mise run refresh` は upstream CLI 経路を通るため `cmd_apply` の save/restore を経由せず、link を張り直さずに完了する。state root 側の実体（roster・履歴）は消えない。

## 診断

`~/.apm` で `mise run doctor` を実行し、agmsg 判定を読む。`db` / `teams` それぞれの状態（symlink 正常 / missing / dangling / wrong-target / plain path）を集約した結果を見る。`ls -l` の目視だけで二分しない。

## 復旧の判断

- plain path が1つでもある（`db` または `teams` が symlink ではなく実体のディレクトリ/ファイル）→ `mise run agmsg:state:restore` を実行しない。断線中に書かれた roster 更新を保持している可能性があり、restore は state root 側を優先してマージし plain 側を削除するため、その更新を discard しうる。先に plain path の中身を `${XDG_STATE_HOME:-~/.local/state}/agmsg/<name>` と手動で突き合わせ、必要な差分を反映してから relink する
- missing / dangling / wrong-target のみで plain path が無い → 失うものが無いので `~/.apm` で `mise run agmsg:state:restore` をそのまま実行してよい
- どちらの場合も手で `ln -s` を張らない

## `team.sh` の 0 member は喪失と断定しない

`team.sh` が 0 member を返しても、それだけでは roster 喪失と判定しない。projection の反映漏れ（race）で一時的に空を返すことがあるため、`config.json` と `roster.jsonl` の実体を確認してから判断する。
