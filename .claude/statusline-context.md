# コンテクスト残量をステータスラインに常時表示する

## 前提: 右下の「⚪︎」は別モノ

Claude Code アプリ（web / デスクトップ）の入力欄まわりに出ている円形ゲージは
**プラン利用量**（5時間セッション枠 / 週次枠）のインジケータで、
そのチャットのコンテクストウィンドウ残量ではない。
これを「チャットごとのコンテクスト」に切り替える設定は現時点で存在しない。
内訳は `/usage` で確認できる。

## そのチャットのコンテクスト残量を見る

- `/context` … 現在のコンテクスト使用量をカラーグリッドで表示（都度確認）
- ステータスライン … 常時表示（本スクリプト）

## インストール

`~/.claude/settings.json`（ユーザー設定）に追記する:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline-context.sh"
  }
}
```

`statusLine` は信頼が必要な設定キーなので、プロジェクト設定ではなく
ユーザー設定（`~/.claude/settings.json`）に置くこと。
スクリプト本体も `~/.claude/statusline-context.sh` にコピーして
`chmod +x` しておく。

## 仕組み

Claude Code はステータスラインコマンドの stdin に JSON を渡す。
その中の `context_window` がセッション単位（= このチャット）の値:

```json
{
  "context_window": {
    "total_input_tokens": 0,
    "total_output_tokens": 0,
    "context_window_size": 200000,
    "current_usage": 136000,
    "used_percentage": 68,
    "remaining_percentage": 32
  }
}
```

出力例:

```
~/myrepo | Opus 5 | ctx ███████░░░ 68% (136.0k/200.0k)
```

60% 未満は緑、85% 未満は黄、それ以上は赤。
`jq` があれば `jq`、無ければ `python3` で JSON を読む。
両方無い場合は `ctx n/a` を出して失敗しない。
