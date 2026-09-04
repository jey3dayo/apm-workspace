# 初回利用前の smoke

runtime（Claude / Codex）ごとに、実際に次の5点を確認してから常用する。

1. review は対象 project への write が拒否される
2. implement は対象 project 内の edit が成功し project 外の write が拒否される
3. `send-report.sh` による READY send 成功
4. DONE / REVIEW send 成功
5. 全手順が承認画面・MCP 確認画面なしで完了する
