# チャットごとのコンテクスト残量を表示する

Claude Code 2.1.252 のバンドルを実際に読んで確認した内容と、それに基づくスクリプト。

## 1. 右下の「⚪︎」はコンテクストではない

入力欄まわりの円形ゲージは**プラン利用量**のインジケータ。内部では
レートリミット種別が以下のように分岐している:

| 内部の種別 | 表示 |
|---|---|
| `five_hour` | session limit（5時間枠） |
| `seven_day` | weekly limit（週次枠） |
| `seven_day_opus` | Opus limit |

**これをそのチャットのコンテクスト残量に切り替える設定は存在しない。**
`showContext` / `contextIndicator` / `usageIndicator` といった設定キーは
バンドル内に一つも無く、`/config` の選択肢にも該当項目は無い。

プラン利用量の内訳を見たいときは `/usage`（"Show plan usage limits"）。

## 2. コンテクスト残量を見る手段

### `/context` — どこでも使える

スラッシュコマンドが2種類登録されていて、実行モードで自動的に切り替わる:

- 対話モード（ターミナル / デスクトップ）
  → `type: "local-jsx"` / "Visualize current context usage as a colored grid"
- 非対話モード（SDK・web セッションなど）
  → `type: "local"` / `supportsNonInteractive: true` / "Show current context usage"

つまり **web 版でも `/context` は使える**（テキスト出力になる）。

### ステータスライン — 常時表示（ただしターミナル / デスクトップ限定）

本リポジトリの `statusline-context.sh`。

> **注意**: ステータスラインは Ink（TUI）コンポーネント内でのみ描画される。
> 生成された文字列はアプリ状態の `statusLineText` に入るだけで、リモート／SDK
> 側へ流す `status_line` フィールドは存在しない（`status_line_mount` は
> テレメトリイベント名）。**web 版の画面には出ない。**
> web で常時見たい、という要件は現状のクライアントでは満たせないので、
> web では `/context` を都度叩くのが唯一の方法。

### 自動コンパクト直前の警告

コンテクストが減ると入力欄の下に自動で出る:

```
Context left until auto-compact: 12%
Context low (8% remaining)
```

これは常時表示ではなく、残量が少なくなったときだけ出る。

## 3. インストール

```sh
./.claude/install-statusline.sh
```

やること:

1. `statusline-context.sh` を `~/.claude/` にコピーして `chmod +x`
2. `~/.claude/settings.json` の `statusLine` キーだけを差し替え
   （他の設定は保持。実行前にタイムスタンプ付きバックアップを作成）
3. サンプル入力でプレビューを表示

反映には Claude Code の再起動（または新セッション）が必要。

手動でやる場合は `~/.claude/settings.json` に:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline-context.sh",
    "padding": 0
  }
}
```

- `statusLine` は `apiKeyHelper` などと同じ**信頼が必要な設定キー**なので、
  プロジェクト設定ではなく**ユーザー設定**（`~/.claude/settings.json`）に置く。
- `padding` は左端の余白（デフォルト 0）。`1` にすると1文字分下げる。
- **落とし穴**: `disableAllHooks: true` にしているとステータスラインも
  動かない。CLI 側も "Status line is configured but disableAllHooks is true"
  と警告を出す。インストーラも同じ条件で警告する。

外すとき:

```sh
./.claude/install-statusline.sh --uninstall
```

## 4. 仕組み

Claude Code はステータスラインコマンドの **stdin に JSON** を渡す。
その中の `context_window` がセッション単位（= このチャット）の値:

```json
{
  "session_id": "...",
  "model": { "id": "claude-opus-5", "display_name": "Opus 5" },
  "workspace": { "current_dir": "...", "project_dir": "..." },
  "cost": { "total_cost_usd": 0.0, "total_duration_ms": 0 },
  "context_window": {
    "total_input_tokens": 0,
    "total_output_tokens": 0,
    "context_window_size": 200000,
    "current_usage": 136000,
    "used_percentage": 68,
    "remaining_percentage": 32
  },
  "exceeds_200k_tokens": false
}
```

出力例:

```
~/myrepo | Opus 5 | ctx ███████░░░ 68% (136k/200k)
```

- 60% 未満は緑、85% 未満は黄、それ以上は赤
- 1M コンテクストのモデルでは `(432.1k/1M)` のように表示
- JSON のパースは `jq` → `python3` → `node` の順にフォールバック
- パーサが無い / ペイロードが壊れている / 古いビルドで `context_window` が
  無い場合も、`ctx n/a` を出して**必ず exit 0**（ステータスラインが
  壊れるとプロンプト行が毎回それに置き換わってしまうため）
