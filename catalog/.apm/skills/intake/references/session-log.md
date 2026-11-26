# セッションログの数え方

報告の「このセッションでは X を呼んでいない」「遵守率が低い」を確かめるときの手順。対象は Claude Code のログ `~/.claude/projects/<cwd の / と . を - にした名前>/<セッションID>.jsonl`。サブエージェントのログは `subagents/` の下にある。

## 数える

呼び出しは assistant メッセージの content に入る。通常のツールは `tool_use`、advisor のようにサーバ側で動くものは `server_tool_use` で、どちらも数える。

1 セッションの呼び出しの内訳:

```sh
cd ~/.claude/projects/<dir>
jq -r 'select(.type=="assistant")|.message.content[]?|select(.type=="tool_use" or .type=="server_tool_use")|.name' ./<id>.jsonl | sort | uniq -c | sort -rn
```

ある日付以降の各セッションで、特定のツールを呼んだ回数（子エージェントを除く）:

```sh
cd ~/.claude/projects
find . -maxdepth 2 -name '*.jsonl' -not -path '*subagents*' -newermt 2026-10-29 | while read -r f; do
  n=$(jq -r 'select(.type=="assistant")|.message.content[]?|select(.type=="tool_use" or .type=="server_tool_use")|.name' "$f" | grep -c '^advisor$')
  echo "$n $f"
done
```

MCP のツール名は `mcp__<server>__<tool>` なので `grep voicevox` のように部分一致で数える。Bash の中身は `select(.type=="tool_use" and .name=="Bash")|.input.command` で取れる。使ったモデルは assistant の `.message.model`。

## 落とし穴

- `grep '"name":"advisor"'` は、ツール定義や本文中の言及にも当たる。呼び出しの回数には使わない。content の型を `jq` で絞る。
- プロジェクトのディレクトリ名は `-` で始まる。`jq`・`find`・`ls` に素で渡すと、オプションとして読まれる。`./` を付けるか、`cd` してから `./` で渡す。
- macOS の `ls` に `--time-style` は無い。日付の絞り込みは `find -newermt`。
- 全セッションを `jq` で回すと遅い。バックグラウンドで実行する。
- 遵守率は、分母（例: ツール呼び出し 30 回以上のセッション）を決めて書く。分母を決めない割合は、比べられない。
- 「ルールが守られなかった」と書く前に、ルールが指すツールがそのとき使える状態だったかを確かめる。音声通知の報告は、MCP が global から外された後のログだった。
