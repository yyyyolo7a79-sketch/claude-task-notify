<div align="center">

**Language / 语言 / 語言 / 言語 / 언어**

[**English**](../../README.md) | [简体中文](../../README.zh-CN.md) | [繁體中文](../zh-TW/README.md) | [日本語](README.md) | [한국어](../ko-KR/README.md)

</div>

---

# Claude Code タスク完了通知（claude-task-notify）

> Windows 上の Claude Code 向け ChatGPT 風デスクトップカード——✅ タスク完了 / ❓ ユーザーの入力待ち / ⏳ 回答・承認待ち。待機系ポップアップは表示され続け、**回答または承認した瞬間に自動で閉じます**。純粋なシステム PowerShell + WPF、**サードパーティ依存ゼロ**。
>
> 📄 このファイルは簡易翻訳版です。完全な内容は [English README](../../README.md) を参照してください。

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](../../LICENSE)
![Windows](https://img.shields.io/badge/Windows-10%2F11-0078D4?logo=windows&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1-5391FE?logo=powershell&logoColor=white)
![Claude Code](https://img.shields.io/badge/Claude%20Code-v2.x-D97757?logo=claude&logoColor=white)
[![Stars](https://img.shields.io/github/stars/yyyyolo7a79-sketch/claude-task-notify?style=flat)](https://github.com/yyyyolo7a79-sketch/claude-task-notify/stargazers)
[![Downloads](https://img.shields.io/github/downloads/yyyyolo7a79-sketch/claude-task-notify/total?style=flat)](https://github.com/yyyyolo7a79-sketch/claude-task-notify/releases)

---

## ✨ 機能

- **必ず発火**——Claude Code の hook（harness 層、`~/.claude/settings.json` に設定）で起動。Claude が応答を止めるたびに必ず通知が出ます。モデルの協力は不要。
- **スマート判定**——返信が疑問符で終わる、または依頼表現（「〜を提供してください」）を含む → **❓ ユーザーの入力待ち**、それ以外 → **✅ タスク完了**（8 秒で自動消滅）。
- **返信の要約**——カード本文に返信の冒頭段落（180 文字で切り詰め、コードブロック/HTML/実体参照/URL を除去）を表示。ターミナルに戻らなくても内容が分かります。
- **プロジェクト名**——タイトル横に現在のプロジェクトディレクトリ名を表示。複数プロジェクト同時実行でも一目で区別。
- **待機リマインダー**——Claude が**質問**（AskUserQuestion）または**権限確認**を行うと「❓ 回答待ち」「⏳ 承認待ち」カードを表示（質問/コマンドの要約付き）。別ウィンドウでコーディング中でも待ち状態を見逃しません。
- **永続表示・回答で自動クローズ**——待機系カードは表示され続け、①回答/承認（**自動クローズ**）②✕ で手動クローズ ③30 分の安全タイムアウトのいずれかで終了。`/notify_AskUserQuestion_persistence false` で 8 秒自動消滅に戻せます。
- **自動クローズ信号チャネル**——**すべてのツール**の PostToolUse / PostToolUseFailure / PermissionDenied を監視（WebFetch、WebSearch、Skill、MCP ツールなど、権限プロンプトを出し得るものすべて）。軽量プレフィルター `notify-close-check.cmd` 経由：**待機中のポップアップがなければ約 +30ms で早期終了**（PowerShell を起動しない）、待機中のみ完全パイプライン（約 0.2 秒）。照合はデュアルチャネル（ツール呼び出し ID + ツール引数の内容フィンガープリント——権限リクエストイベントは仕様上 `tool_use_id` を持たないため）。ポップアップ存命中のみ `waiting-*` ハンドシェイクファイルを作成し、待機者がいなければ信号ファイルはゼロ。
- **重複排除とノイズ除去**——同一セッションで 2 秒以内の重複イベントは 1 回だけ表示。AskUserQuestion 自身の権限ノイズはスキップ。
- **全プロジェクトで有効**——ユーザーレベル `~/.claude/settings.json` に設定。
- **依存ゼロ**——システム標準の PowerShell 5.1 + WPF（DirectWrite レンダリング、ブラウザーと同等に鮮明）。
- **フォーカスを奪わない**——`ShowActivated=false` + `WS_EX_NOACTIVATE`。
- **ノンブロッキング**——hook エントリは 500ms 以内に戻り、UI は独立プロセスで動作。
- **プライバシー配慮**——`%TEMP%\claude-code-notify\notify.log`（200KB ローリング）に、時刻/セッション先頭 8 文字/結果のみ記録。全文は残しません。

### 表示イメージ

```
┌────────────────────────────────┐
│ ✅  タスク完了                   │
│ すべての変更を適用しました。     │
│ 3 ファイル更新、テスト合格。     │
└────────────────────────────────┘
   ↑ 右下 · 白いカード · フェードイン/アウト
     8 秒で自動消滅 · クリック/✕ で閉じる
```

## 🔧 仕組み

```
Claude Code イベント（~/.claude/settings.json グローバル設定、timeout 5s）
        │  stdin JSON
        ├─ Stop（メイン返信の終了）──────────────┐
        ├─ PreToolUse(AskUserQuestion)（質問、回答待ち）─┤
        ├─ PermissionRequest（権限確認、承認待ち）───────┤
        └─ PostToolUse / PostToolUseFailure / PermissionDenied（全ツール）
           → notify-close-check.cmd プレフィルター（waiting なしなら即終了）
           → waiting がある場合のみ PS を起動しクローズフラグを書く → exit ─┘
        ▼
notify-complete.ps1（エントリ、500ms 以内に戻る）
        │  ① イベント種別でフィルタ（AskUserQuestion 自身の権限ノイズをスキップ）
        │  ② ローカルで要約（コードブロック/HTML/実体参照/URL → 先頭 180 文字）
        │  ③ 重複排除：SHA-256(session+内容)、2 秒ウィンドウ
        │  ④ 一時 payload（persist/toolUseId/contentKey）を書き → 独立 UI プロセスを起動
        ▼
show-popup.ps1（独立プロセス、-STA）
        │  payload を読んで削除 → waiting ハンドシェイクを書く → WPF(DirectWrite) 描画
        ▼
右下の非モーダルカード：フォーカスを奪わない · 角丸+影 · クリック/✕ で閉じる
  · Stop：8 秒で自動フェードアウト
  · 待機系（質問/権限確認）：回答/承認で自動クローズ（デュアルチャネル信号）· 手動 ✕ · 30 分の安全タイムアウト
```

## 🚀 クイックスタート

> 動作環境：Windows 10/11 · Claude Code v2.x · PowerShell 5.1（システム標準）

### Claude Code でインストール（推奨）

以下の文章を本リポジトリのリンクと一緒に Claude Code に貼り付けると、インストールとセルフテストを自動で行います：

> リポジトリ `https://github.com/yyyyolo7a79-sketch/claude-task-notify` をグローバル設定（Windows）にインストールしてください：
> 1. `scripts\` の `notify-complete.ps1`、`show-popup.ps1`、`notify-close-check.cmd` を `~\.claude\scripts\` にコピー
> 2. `~\.claude\settings.json` のトップレベルに hook を追加（既存エントリは保持し追記。上書き禁止）：`Stop`（matcher 空）· `PreToolUse`（matcher `AskUserQuestion`）· `PermissionRequest`（matcher 空）· `PostToolUse` / `PostToolUseFailure` / `PermissionDenied`（matcher `*` 全ツール）。ポップアップ系 command は絶対インタープリターパス + `-WindowStyle Hidden`、クローズ信号系 command はプレフィルター（`"\"C:\Users\<ユーザー名>\.claude\scripts\notify-close-check.cmd\""`）を指定。`"timeout": 5`
> 3. `skills\claude-task-notify\` を `~\.claude\skills\` へ、`commands\notify_AskUserQuestion_persistence.md` を `~\.claude\commands\` へコピー
> 4. `~\.claude\CLAUDE.md` の末尾に「タスク完了通知」セクションを追記
> 5. セルフテスト（先に `$OutputEncoding = [Text.Encoding]::UTF8` を設定）：`$OutputEncoding = [Text.Encoding]::UTF8; $evt = @{session_id="test"; cwd=(Get-Location).Path; hook_event_name="Stop"; stop_hook_active=$false; last_assistant_message="ポップアップは正常に動作しています"} | ConvertTo-Json; $evt | & "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "$HOME\.claude\scripts\notify-complete.ps1"`

### 手動インストール

**ステップ 1**——スクリプトをコピー：

```powershell
# 3 ファイルをユーザーレベルのスクリプトディレクトリへ
Copy-Item scripts\notify-complete.ps1 "$HOME\.claude\scripts\"
Copy-Item scripts\show-popup.ps1 "$HOME\.claude\scripts\"
Copy-Item scripts\notify-close-check.cmd "$HOME\.claude\scripts\"
```

**ステップ 2**——グローバル hook を設定。`~/.claude/settings.json` を編集し、トップレベルに `hooks` キーを追加（既存設定は保持）：

```json
{
  "hooks": {
    "Stop": [{ "matcher": "", "hooks": [{ "type": "command", "command": "<CMD>", "timeout": 5 }] }],
    "PreToolUse": [{ "matcher": "AskUserQuestion", "hooks": [{ "type": "command", "command": "<CMD>", "timeout": 5 }] }],
    "PermissionRequest": [{ "matcher": "", "hooks": [{ "type": "command", "command": "<CMD>", "timeout": 5 }] }],
    "PostToolUse": [
      { "matcher": "*", "hooks": [{ "type": "command", "command": "<CMD2>", "timeout": 5 }] }
    ],
    "PostToolUseFailure": [
      { "matcher": "*", "hooks": [{ "type": "command", "command": "<CMD2>", "timeout": 5 }] }
    ],
    "PermissionDenied": [
      { "matcher": "*", "hooks": [{ "type": "command", "command": "<CMD2>", "timeout": 5 }] }
    ]
  }
}
```

> `<CMD>` = `"\"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe\" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"C:\\Users\\<ユーザー名>\\.claude\\scripts\\notify-complete.ps1\""`。`PostToolUse` などに既存エントリがある場合は**追記**してください。
>
> 💡 `<CMD2>` = `"\"C:\\Users\\<ユーザー名>\\.claude\\scripts\\notify-close-check.cmd\""` は「待機ポップアップの自動クローズ」信号チャネル（matcher `*`）：**待機なしならツール完了ごとに約 +30ms**（プレフィルターが即終了、PowerShell を起動しない）、待機中は約 +0.2 秒。この 3 エントリを削除すると手動クローズ / 30 分の安全タイムアウトに格下げされます。

> ⚠️ `<ユーザー名>` を実際のパスに置き換えてください。再起動不要——次のタスクから有効です。
>
> 💡 インタープリターは必ず絶対パス + `-WindowStyle Hidden` で：PATH の `powershell` はハイジャックされ得るうえ、`Hidden` なしだと Stop のたびにコンソールウィンドウが一瞬表示されます。

**ステップ 3**（任意）——行動規範 skill：

```powershell
Copy-Item skills\claude-task-notify "$HOME\.claude\skills\" -Recurse
```

**ステップ 4**（任意）——`~/.claude/CLAUDE.md` 末尾に宣言を追記。

### テスト

```powershell
# エントリを直接テスト（stdin に Stop イベント JSON を渡すとカードが表示されるはず）
# ⚠️ PS 5.1 の $OutputEncoding は既定で ASCII——UTF-8 を設定しないとパイプ経由の非 ASCII が「?」に降格します
$OutputEncoding = [Text.Encoding]::UTF8
$evt = @{ session_id="test"; cwd=(Get-Location).Path; hook_event_name="Stop";
          stop_hook_active=$false; last_assistant_message="ポップアップは正常に動作しています" } | ConvertTo-Json
$evt | & "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "$HOME\.claude\scripts\notify-complete.ps1"
```

結果はログ `%TEMP%\claude-code-notify\notify.log` で確認（`OK` = 通知済み、`DEDUPE` = 重複排除、`SKIP` = フィルタ済み）。

## ⚙️ 設定

ブラウザーで `弹窗参数调整器.html` を開き、スライダーをドラッグしてリアルタイムにプレビュー。調整後に生成されるパラメーターコードを `show-popup.ps1` 冒頭の定数ブロックに貼り付けてください。

| パラメーター | 既定値 | 説明 |
|---|---|---|
| `$W` / `$H` | 400 / 200 | カード幅 / 高さ（px、100% DPI 基準、システムスケールに自動追従） |
| `$PAD_X` / `$PAD_TOP` | 20 / 15 | タイトルの左 / 上パディング |
| `$BODY_TOP` / `$BODY_H` | 52 / 80 | 本文の上オフセット / 本文領域の高さ |
| `$F_TITLE` / `$F_BODY` | 12 / 10（スクリプト内 `* 1.3333`） | タイトル / 本文のフォントサイズ（pt；WPF は DIP px、pt→px ×4/3） |
| `$MAX_CHARS` | 180 | 要約の切り詰め長——`notify-complete.ps1` 冒頭 |
| `$MARGIN` | 20 | 画面右下からの余白 |
| `$PERSIST_MAX_MS` | 30 分 | 永続ポップアップの安全タイムアウト——`show-popup.ps1` 冒頭 |

永続化切り替え：`/notify_AskUserQuestion_persistence true|false`（既定 `true` = 待機系は永続；`false` = 8 秒で消滅）。

## ❓ FAQ

| 症状 | 対処 |
|---|---|
| ポップアップが出ない | ログ `%TEMP%\claude-code-notify\notify.log` を確認：`SKIP` = フィルタ済み、`DEDUPE` = 2 秒以内の重複、`ERR` = 入力または起動失敗 |
| 文字化け | 2 つの `.ps1` は **UTF-8 with BOM** 必須（PS 5.1 は BOM なし UTF-8 を ANSI として読む）。リポジトリのファイルは BOM 付きです。編集した場合は UTF-8 with BOM で再保存してください |
| 文字がぼやける | WPF（DirectWrite）レンダリング済みでブラウザーと同等に鮮明です。それでもぼやける場合はディスプレイのスケーリング設定を確認 |
| システム通知と二重に表示 | `/config` で Claude Code 内蔵通知をオフに |
| カードの内容が切れる | 調整ツールで `$BODY_H` / `$H` を大きく、またはフォントサイズを小さく |
| 待機ポップアップが消えない | 永続モードの仕様です——✕ で閉じるか、回答すると自動で閉じます（30 分の安全タイムアウト）。`/notify_AskUserQuestion_persistence false` で 8 秒に戻せます |
| 権限ポップアップが承認後に自動で閉じなかった | 修正済み（2 世代の問題：① 権限リクエストイベントに ID がない → 内容フィンガープリントチャネル；② 固定 matcher リストが WebFetch/Skill 等を漏らす → 全ツール + cmd プレフィルター）。ごく稀にツールが拒否され後続イベントがない場合のみ手動 ✕ / 30 分の安全タイムアウトに降格 |
| テストで時々 `ERR invalid-json` | PS 5.1 パイプの断続的問題（テスト経路のみ。実 hook は Node が UTF-8 stdin を書くため影響なし）——再実行してください |
| 質問時にカードが 2 枚出る | 旧版の既知問題（AskUserQuestion の権限ノイズ）——`notify-complete.ps1` を最新版に更新してください |

## 📝 変更履歴

### 2026-09-19 — 全ツールのクローズ信号カバレッジ

- 根因：クローズ信号 hook が固定 matcher リスト（`Bash|Edit|Write|MultiEdit|NotebookEdit`）を使用——リスト外のツール（WebFetch、Skill、MCP など）の権限ポップアップは「ツール完了」信号を永遠に受け取れず滞留。
- 修正：3 つのクローズ信号イベントの matcher を `*` 全ツールに変更 + `notify-close-check.cmd` プレフィルターを追加（待機なしなら約 30ms で即終了、PowerShell を起動しない）。

### 2026-09-18 — 待機ポップアップの自動クローズ修正

- 根因：権限リクエストイベント（PermissionRequest）は仕様上 **`tool_use_id` を持たない**——権限ポップアップはクローズ信号と照合できなかった。
- 修正：デュアルチャネル信号（呼び出し ID + 内容フィンガープリント `SHA256(tool_name+tool_input)[:16]`）、`waiting-*` ハンドシェイクファイル（待機者ゼロならファイルもゼロ）、`PermissionDenied` イベントを追加。

### 2026-09-17 — 初版：待機リマインダーと永続ポップアップ

- 4 つのバグ修正（重複排除のタイムゾーン、30 DIP の位置ずれ、質問時の二重カード、ドキュメント/パイプ）。
- 新機能：質問/権限確認時の ❓/⏳ 待機リマインダー、既定で永続 + 回答で自動クローズ、`/notify_AskUserQuestion_persistence` コマンド。

> 📖 完全な履歴（初期開発段階を含む）は [English README](../../README.md#-changelog) を参照。

## 📄 ライセンスとクレジット

MIT——[LICENSE](../../LICENSE) を参照。

UI の着想は ChatGPT デスクトップアプリと Codex のタスク完了トースト：非モーダル、フォーカスを奪わない、右下、自動消滅。
