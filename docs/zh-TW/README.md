<div align="center">

**Language / 语言 / 語言 / 言語 / 언어**

[**English**](../../README.md) | [简体中文](../../README.zh-CN.md) | [繁體中文](README.md) | [日本語](../ja-JP/README.md) | [한국어](../ko-KR/README.md)

</div>

---

# Claude Code 任務完成彈窗（claude-task-notify）

> Claude Code 在 Windows 上的 ChatGPT 風格桌面卡片——✅ 任務完成 / ❓ 需要使用者提供相關資訊 / ⏳ 正在等你回答或核准。等待類彈窗會持續顯示、**回答或核准後自動關閉**。純系統 PowerShell + WPF，**零第三方相依**。
>
> 📄 此檔案為精簡翻譯版；完整內容以 [English README](../../README.md) 為準。

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](../../LICENSE)
![Windows](https://img.shields.io/badge/Windows-10%2F11-0078D4?logo=windows&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1-5391FE?logo=powershell&logoColor=white)
![Claude Code](https://img.shields.io/badge/Claude%20Code-v2.x-D97757?logo=claude&logoColor=white)
[![Stars](https://img.shields.io/github/stars/yyyyolo7a79-sketch/claude-task-notify?style=flat)](https://github.com/yyyyolo7a79-sketch/claude-task-notify/stargazers)
[![Downloads](https://img.shields.io/github/downloads/yyyyolo7a79-sketch/claude-task-notify/total?style=flat)](https://github.com/yyyyolo7a79-sketch/claude-task-notify/releases)

---

## ✨ 功能

- **強制生效**——由 Claude Code 的 hook 觸發（harness 層執行，設定於 `~/.claude/settings.json`），每次 Claude 停止回應必然彈窗，不依賴模型自覺。
- **智慧判斷**——回覆以問號結尾或含請求詞（「請提供…」）→ **❓ 需要使用者提供相關資訊**；否則 → **✅ 任務完成**（8 秒自動消失）。
- **回覆摘要**——卡片內文顯示本次回覆首段（截斷 180 字，自動清理程式碼區塊/HTML/實體/URL），不切回終端機也知道 Claude 說了什麼。
- **專案名稱**——標題旁顯示目前專案目錄名稱，多專案同時執行一眼區分。
- **等待提醒**——Claude **提問**（AskUserQuestion）或**權限確認**時彈出「❓ 正在等你回答」「⏳ 正在等你核准操作」卡片（附問題/命令摘要）——你在別的視窗寫程式也不會錯過等待。
- **持久彈窗，回答即關**——等待類卡片持續顯示，直到：你回答/核准（**自動關閉**）、手動點 ✕、或 30 分鐘安全閥到期。`/notify_AskUserQuestion_persistence false` 可切回 8 秒自動消失。
- **自動關閉訊號通道**——監聽**所有工具**的 PostToolUse / PostToolUseFailure / PermissionDenied（涵蓋 WebFetch、WebSearch、Skill、MCP 工具等一切可能觸發權限的工具），經輕量前置過濾器 `notify-close-check.cmd`：**無等待彈窗時約 +30ms 秒退**（不啟動 PowerShell），有彈窗等待時才走完整鏈路。雙通道比對（工具呼叫 ID + 工具參數內容指紋——權限請求事件官方設計不帶 ID）；彈窗存續期間以 `waiting-*` 握手檔案登記，無等待者不產生任何訊號檔案。
- **去重與過濾**——同一工作階段 2 秒內重複事件只彈一次；AskUserQuestion 自身的權限雜訊自動略過。
- **全域生效**——設定於使用者層級 `~/.claude/settings.json`，對所有專案生效。
- **零第三方相依**——僅用系統內建的 PowerShell 5.1 + WPF（DirectWrite 渲染，文字與瀏覽器同源清晰）。
- **不搶焦點**——`ShowActivated=false` + `WS_EX_NOACTIVATE`，絕不打断你正在進行的輸入。
- **非阻塞**——hook 入口 500ms 內返回，彈窗 UI 由獨立處理程序管理。
- **去識別化日誌**——`%TEMP%\claude-code-notify\notify.log`（200KB 滾動），只記時間/工作階段前 8 碼/結果，不落全文。

### 彈窗效果

```
┌────────────────────────────────┐
│ ✅  任務完成                     │
│ 已完成所有修改，共改動 3 個檔    │
│ 案，測試全部通過。               │
└────────────────────────────────┘
   ↑ 右下角 · 白底圓角 · 淡入淡出
     8 秒自動消失 · 點擊/✕ 立即關閉
```

## 🔧 運作原理

```
Claude Code 事件（~/.claude/settings.json 全域設定，timeout 5s）
        │  stdin JSON
        ├─ Stop（主回覆結束）──────────────────┐
        ├─ PreToolUse(AskUserQuestion)（提問，等你回答）─┤
        ├─ PermissionRequest（權限確認，等你核准）───────┤
        └─ PostToolUse / PostToolUseFailure / PermissionDenied（全部工具）
           → notify-close-check.cmd 前置過濾（無 waiting 秒退）
           → 有 waiting 才啟動 PS 寫關閉旗標 → exit ─────┘
        ▼
notify-complete.ps1（入口，500ms 內返回）
        │  ① 過濾事件類型（略過 AskUserQuestion 自身的權限雜訊）
        │  ② 本機確定性摘要（程式碼區塊/HTML/實體/URL → 首段 180 字）
        │  ③ 去重：SHA-256(session+內容)，2 秒視窗
        │  ④ 寫暫存 payload（persist/toolUseId/contentKey）→ 派生獨立 UI 處理程序
        ▼
show-popup.ps1（獨立處理程序，-STA）
        │  讀取 payload 後刪除 → 寫 waiting 握手 → WPF(DirectWrite) 渲染
        ▼
右下角非模態卡片：不搶焦點 · 圓角+陰影 · 點擊/✕ 關閉
  · Stop：8 秒自動淡出
  · 等待類（提問/權限確認）：回答/核准後自動關閉（雙通道訊號）· 手動 ✕ · 30 分鐘安全閥
```

## 🚀 快速開始

> 環境需求：Windows 10/11 · Claude Code v2.x · PowerShell 5.1（系統內建）

### 用 Claude Code 安裝（推薦）

把下面這段話連同本倉庫連結一起發給你的 Claude Code，它會自動完成全部安裝並自我測試：

> 請把倉庫 `https://github.com/yyyyolo7a79-sketch/claude-task-notify` 安裝到我的全域設定（Windows）：
> 1. 將 `scripts\` 下的 `notify-complete.ps1`、`show-popup.ps1`、`notify-close-check.cmd` 複製到 `~\.claude\scripts\`
> 2. 在 `~\.claude\settings.json` 頂層加入 hook（已有其他條目保留追加、不要覆蓋）：`Stop`（matcher 空）· `PreToolUse`（matcher `AskUserQuestion`）· `PermissionRequest`（matcher 空）· `PostToolUse` / `PostToolUseFailure` / `PermissionDenied`（matcher `*` 全工具）；彈窗類 command 用絕對解譯器路徑 + `-WindowStyle Hidden`（`"\"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe\" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"C:\Users\<你的使用者名稱>\.claude\scripts\notify-complete.ps1\""`），關閉訊號類 command 指向前置過濾器（`"\"C:\Users\<你的使用者名稱>\.claude\scripts\notify-close-check.cmd\""`）；`"timeout": 5`
> 3. 將 `skills\claude-task-notify\` 複製到 `~\.claude\skills\`；將 `commands\notify_AskUserQuestion_persistence.md` 複製到 `~\.claude\commands\`
> 4. 在 `~\.claude\CLAUDE.md` 末尾追加「任務完成彈窗」小節
> 5. 自我測試（先設 `$OutputEncoding = [Text.Encoding]::UTF8`）：`$OutputEncoding = [Text.Encoding]::UTF8; $evt = @{session_id="test"; cwd=(Get-Location).Path; hook_event_name="Stop"; stop_hook_active=$false; last_assistant_message="彈窗運作正常"} | ConvertTo-Json; $evt | & "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "$HOME\.claude\scripts\notify-complete.ps1"`

### 手動安裝

**第 1 步**——複製腳本：

```powershell
# 三個檔案複製到使用者層級腳本目錄
Copy-Item scripts\notify-complete.ps1 "$HOME\.claude\scripts\"
Copy-Item scripts\show-popup.ps1 "$HOME\.claude\scripts\"
Copy-Item scripts\notify-close-check.cmd "$HOME\.claude\scripts\"
```

**第 2 步**——設定全域 hook。編輯 `~/.claude/settings.json`，在頂層新增 `hooks` 鍵（保留原有設定）：

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

> `<CMD>` 即：`"\"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe\" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"C:\\Users\\<你的使用者名稱>\\.claude\\scripts\\notify-complete.ps1\""`。若 `PostToolUse` 等鍵下已有其他條目，**追加**而非覆蓋。
>
> 💡 `<CMD2>` = `"\"C:\\Users\\<你的使用者名稱>\\.claude\\scripts\\notify-close-check.cmd\""` 是「等待彈窗自動關閉」的訊號通道（matcher `*`）：**無等待彈窗時每次工具完成約 +30ms**（前置過濾器秒退、不啟動 PowerShell），等待中約 +0.2 秒。刪除這三個條目則等待彈窗退化為手動關閉 / 30 分鐘安全閥。

> ⚠️ 把 `<你的使用者名稱>` 替換為實際路徑；設定後無需重啟，下一次任務即生效。
>
> 💡 解譯器必須用絕對路徑 + `-WindowStyle Hidden`：PATH 裡的 `powershell` 可被劫持，且不加 `Hidden` 每次 Stop 會閃現主控台視窗。

**第 3 步**（選用）——行為規範 skill：

```powershell
Copy-Item skills\claude-task-notify "$HOME\.claude\skills\" -Recurse
```

**第 4 步**（選用）——`~/.claude/CLAUDE.md` 末尾追加宣告。

### 測試

```powershell
# 直接測入口（stdin 餵 Stop 事件 JSON，應快速返回並彈出卡片）
# ⚠️ PS 5.1 的 $OutputEncoding 預設 ASCII——不設 UTF-8 時管道中文會降級為 "?"
$OutputEncoding = [Text.Encoding]::UTF8
$evt = @{ session_id="test"; cwd=(Get-Location).Path; hook_event_name="Stop";
          stop_hook_active=$false; last_assistant_message="彈窗運作正常" } | ConvertTo-Json
$evt | & "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "$HOME\.claude\scripts\notify-complete.ps1"
```

測試結果見日誌 `%TEMP%\claude-code-notify\notify.log`（`OK` = 已通知，`DEDUPE` = 去重，`SKIP` = 被過濾）。

## ⚙️ 參數調整

用瀏覽器開啟 `弹窗参数调整器.html`，拖動滑桿即時預覽卡片效果，調好後把頁面生成的參數代碼發回，替換 `show-popup.ps1` 頂部常數區即可。

| 參數 | 預設值 | 說明 |
|---|---|---|
| `$W` / `$H` | 400 / 200 | 卡片寬度 / 高度（px，100% DPI 基準，自動依系統縮放） |
| `$PAD_X` / `$PAD_TOP` | 20 / 15 | 標題左邊距 / 上邊距 |
| `$BODY_TOP` / `$BODY_H` | 52 / 80 | 內文上邊距 / 內文區域高度 |
| `$F_TITLE` / `$F_BODY` | 12 / 10（腳本內 `* 1.3333`） | 標題 / 內文字級（pt；WPF 單位是 DIP px，pt→px ×4/3） |
| `$MAX_CHARS` | 180 | 摘要截斷長度——在 `notify-complete.ps1` 頂部 |
| `$MARGIN` | 20 | 彈窗距螢幕右下角邊距 |
| `$PERSIST_MAX_MS` | 30 分鐘 | 持久彈窗安全閥——在 `show-popup.ps1` 頂部 |

持久化開關：`/notify_AskUserQuestion_persistence true|false`（預設 `true` = 等待類彈窗持久；`false` = 8 秒消失）。

## ❓ 常見問題

| 現象 | 處理 |
|---|---|
| 彈窗不出現 | 看日誌 `%TEMP%\claude-code-notify\notify.log`：`SKIP` = 被過濾、`DEDUPE` = 2 秒內重複、`ERR` = 輸入或派生失敗 |
| 中文亂碼 | 兩個 `.ps1` 必須是 **UTF-8 with BOM**（PS 5.1 對無 BOM 的 UTF-8 按 ANSI 解讀）。倉庫檔案已帶 BOM，編輯過請重新儲存為 UTF-8 with BOM |
| 文字模糊 | 已用 WPF（DirectWrite）渲染，與瀏覽器同源清晰；如仍模糊請檢查顯示器縮放設定 |
| 與系統通知雙彈 | `/config` 中關閉 Claude Code 內建通知 |
| 彈窗內容被截斷 | 用調整器調大 `$BODY_H` / `$H` 或減小字級 |
| 等待彈窗一直不消失 | 持久模式的設計——點 ✕ 關閉，或回答後自動關（安全閥 30 分鐘）；`/notify_AskUserQuestion_persistence false` 可切回 8 秒 |
| 權限彈窗核准後沒自動消失 | 已修復（兩代問題：① 權限請求事件無 ID → 內容指紋通道；② 固定 matcher 清單漏 WebFetch/Skill 等工具 → 全工具掛載 + cmd 前置過濾）；僅在極罕見情境（工具被拒後無後續事件）退化為手動 ✕ / 30 分鐘安全閥 |
| 測試命令偶發 `ERR invalid-json` | PS 5.1 管道傳輸的間歇問題（僅測試鏈路；真實 hook 由 Node 寫 stdin 不受影響）——重跑一次即可 |
| 提問時彈出兩張卡片 | 舊版已知問題（AskUserQuestion 權限雜訊）——更新 `notify-complete.ps1` 到最新版即可 |

## 📝 更新日誌

### 2026-09-19 — 全工具關閉訊號覆蓋

- 根因：關閉訊號 hook 用了固定 matcher 清單（`Bash|Edit|Write|MultiEdit|NotebookEdit`）——清單外工具（WebFetch、Skill、MCP 等）的權限彈窗永遠收不到「工具完成」訊號，持續滯留。
- 修復：三個關閉訊號事件 matcher 改 `*` 全工具 + 新增 `notify-close-check.cmd` 前置過濾器（無等待時約 30ms 秒退，不啟動 PowerShell）。

### 2026-09-18 — 等待彈窗自動關修復

- 根因：權限請求事件（PermissionRequest）官方設計**沒有 `tool_use_id`**——權限彈窗無法比對關閉訊號。
- 修復：雙通道關閉訊號（呼叫 ID + 內容指紋 `SHA256(tool_name+tool_input)[:16]`）、`waiting-*` 握手檔案（無等待者零檔案）、補 `PermissionDenied` 事件。

### 2026-09-17 — 首個版本：等待提醒與持久彈窗

- 4 個 bug 修復（去重時區、定位偏移 30 DIP、提問雙彈窗、檔案/管道）。
- 新增：提問/權限確認時的 ❓/⏳ 等待提醒，預設持久 + 回答自動關，`/notify_AskUserQuestion_persistence` 命令。

> 📖 完整歷史（含更早的初始開發階段）見 [English README](../../README.md#-changelog)。

## 📄 授權與致謝

MIT——見 [LICENSE](../../LICENSE)。

互動靈感來自 ChatGPT 桌面端與 Codex 的任務完成彈窗：非模態、不搶焦點、右下角、自動消失。
