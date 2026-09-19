<div align="center">

**Language / 语言 / 語言 / 言語 / 언어**

[**English**](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](docs/zh-TW/README.md) | [日本語](docs/ja-JP/README.md) | [한국어](docs/ko-KR/README.md)

</div>

---

# Claude Code Task Notify

> ChatGPT-style desktop toasts for **Claude Code on Windows** — ✅ task complete / ❓ needs your input / ⏳ waiting for your answer or approval. Wait reminders stay on screen until you come back, and **auto-close the moment you answer or approve**. Pure system PowerShell + WPF — **no third-party modules required**.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Windows](https://img.shields.io/badge/Windows-10%2F11-0078D4?logo=windows&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1-5391FE?logo=powershell&logoColor=white)
![Claude Code](https://img.shields.io/badge/Claude%20Code-v2.x-D97757?logo=claude&logoColor=white)
[![Stars](https://img.shields.io/github/stars/yyyyolo7a79-sketch/claude-task-notify?style=flat)](https://github.com/yyyyolo7a79-sketch/claude-task-notify/stargazers)
[![Downloads](https://img.shields.io/github/downloads/yyyyolo7a79-sketch/claude-task-notify/total?style=flat)](https://github.com/yyyyolo7a79-sketch/claude-task-notify/releases)

---

## ✨ Why

- **Always fires** — triggered by Claude Code hooks (harness level, configured in `~/.claude/settings.json`): the toast appears every time Claude stops responding. No model cooperation needed.
- **Smart detection** — replies ending with a question mark or a request phrase ("please provide…") show **❓ Needs your input**; otherwise **✅ Task complete** (auto-dismisses after 8 s).
- **Reply summary** — the first paragraph of the reply (180 chars, cleaned of code blocks / HTML / entities / URLs) right in the card, so you know what Claude said without switching back to the terminal.
- **Project name** — shown next to the title; instantly tells apart multiple projects running at once.
- **Wait reminders** — when Claude asks a question (`AskUserQuestion`) or requests permission, a **❓ Waiting for your answer** / **⏳ Waiting for your approval** card appears (with the question / command summary). Never miss a stall while you are coding in another window.
- **Persistent, then auto-closes** — wait cards stay on screen until: you answer/approve (**auto-close**), you click ✕, or a 30-minute safety timeout fires. `/notify_AskUserQuestion_persistence false` switches back to an 8-second auto-dismiss.
- **Auto-close signal channel** — listens to PostToolUse / PostToolUseFailure / PermissionDenied from **every tool** (WebFetch, WebSearch, Skill, MCP tools — anything that can trigger a permission prompt), through a lightweight `notify-close-check.cmd` pre-filter: **≈30 ms early-exit when nothing is waiting** (no PowerShell cold start), full pipeline (~0.2 s) only while a popup is actually waiting. Matching is dual-channel (tool-call ID + tool-input content fingerprint — `PermissionRequest` carries no `tool_use_id` by design); a `waiting-*` handshake file is written only while a popup is alive, so idle runs produce zero signal files.
- **Dedup & noise filter** — identical events within 2 s collapse into one toast; `AskUserQuestion`'s own permission noise is skipped.
- **Global for all projects** — lives in user-level `~/.claude/settings.json`.
- **Zero dependencies** — only the built-in PowerShell 5.1 + WPF (DirectWrite rendering, as crisp as the browser).
- **Never steals focus** — shown with `ShowActivated=false` + `WS_EX_NOACTIVATE`.
- **Non-blocking** — the hook entry returns in <500 ms; the toast UI runs in its own process.
- **Privacy-minded** — masked log at `%TEMP%\claude-code-notify\notify.log` (200 KB rolling); only timestamps, session prefixes and results — never full text.

### Preview

```
┌────────────────────────────────┐
│ ✅  Task complete               │
│ All changes applied — 3 files  │
│ touched, tests pass.           │
└────────────────────────────────┘
   ↑ bottom-right · white card · rounded
     auto-dismiss 8 s · click / ✕ to close
```

## 🔧 How it works

```
Claude Code events (~/.claude/settings.json, timeout 5s)
        │  stdin JSON
        ├─ Stop (main reply finished) ──────────────┐
        ├─ PreToolUse(AskUserQuestion) (Claude asks, waiting) ─┤
        ├─ PermissionRequest (waiting for approval) ──────────┤
        └─ PostToolUse / PostToolUseFailure / PermissionDenied (all tools)
           → notify-close-check.cmd pre-filter (early-exit if nothing waits)
           → PowerShell entry writes close flags → exit ───────┘
        ▼
notify-complete.ps1  (entry, returns within 500 ms)
        │  ① filter event type (skip AskUserQuestion's own permission noise)
        │  ② summarize locally (code blocks/HTML/entities/URLs → first 180 chars)
        │  ③ dedupe: SHA-256(session + content), 2-second window
        │  ④ write temp payload (persist / toolUseId / contentKey)
        │     → spawn show-popup.ps1 as an independent process
        ▼
show-popup.ps1  (own process, -STA)
        │  reads payload, deletes it, writes waiting handshake
        │  → WPF (DirectWrite) renders the card
        ▼
Bottom-right card: no focus steal · rounded + shadow · click / ✕ closes
  · Stop: auto-fades after 8 s
  · Wait types (question / permission, persist=true): stays until
    answered/approved (dual-channel close signal) · manual ✕ · 30-min safety timeout
```

## 🚀 Quick Start

> Requirements: Windows 10/11 · Claude Code v2.x · PowerShell 5.1 (built in)

### Install with Claude Code (recommended)

Paste the following text together with this repo's link into your Claude Code — it will install everything and self-test:

> Install the `claude-task-notify` repo `https://github.com/yyyyolo7a79-sketch/claude-task-notify` into my global config (Windows):
> 1. Copy `scripts\notify-complete.ps1`, `scripts\show-popup.ps1` and `scripts\notify-close-check.cmd` into `~\.claude\scripts\`
> 2. In `~\.claude\settings.json` add these hook entries at the top level (keep any existing entries; append, do not overwrite): `Stop` (matcher empty) · `PreToolUse` (matcher `AskUserQuestion`) · `PermissionRequest` (matcher empty) · `PostToolUse` / `PostToolUseFailure` / `PermissionDenied` (matcher `*`, all tools);
>    popup-type commands use the absolute interpreter path with `-WindowStyle Hidden`: `"\"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe\" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"C:\Users\<your-username>\.claude\scripts\notify-complete.ps1\""`; close-signal commands point at the pre-filter: `"\"C:\Users\<your-username>\.claude\scripts\notify-close-check.cmd\""`; all with `"timeout": 5`
> 3. Copy `skills\claude-task-notify\` into `~\.claude\skills\` and `commands\notify_AskUserQuestion_persistence.md` into `~\.claude\commands\`
> 4. Append the "task-notify" section to `~\.claude\CLAUDE.md` (see manual install step 4)
> 5. Self-test (set `$OutputEncoding` to UTF-8 first — PS 5.1 pipes would otherwise downgrade non-ASCII to "?"): `$OutputEncoding = [Text.Encoding]::UTF8; $evt = @{session_id="test"; cwd=(Get-Location).Path; hook_event_name="Stop"; stop_hook_active=$false; last_assistant_message="Toast works"} | ConvertTo-Json; $evt | & "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "$HOME\.claude\scripts\notify-complete.ps1"`

### Manual install

**Step 1** — copy the scripts:

```powershell
# Three files go to the user-level scripts directory
Copy-Item scripts\notify-complete.ps1 "$HOME\.claude\scripts\"
Copy-Item scripts\show-popup.ps1 "$HOME\.claude\scripts\"
Copy-Item scripts\notify-close-check.cmd "$HOME\.claude\scripts\"
```

**Step 2** — configure the global hooks. Edit `~/.claude/settings.json`, add a `hooks` key at the top level (keep your existing settings):

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

> `<CMD>` is the popup-type command: `"\"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe\" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"C:\\Users\\<your-username>\\.claude\\scripts\\notify-complete.ps1\""`. If you already have `PostToolUse` entries (e.g. other hooks), **append** rather than overwrite.
>
> 💡 `<CMD2>` = `"\"C:\\Users\\<your-username>\\.claude\\scripts\\notify-close-check.cmd\""` is the close-signal channel (matcher `*`): it costs **≈30 ms per tool completion when nothing waits** (the pre-filter early-exits without starting PowerShell) and ~0.2 s only while a popup is waiting. Remove these three entries to degrade wait popups to manual close / 30-min safety timeout.

> ⚠️ Replace `<your-username>` with your actual path. No restart needed — effective from the next task. The UI process is spawned automatically (its `-STA` flag is built in).
>
> 💡 Always use the absolute interpreter path + `-WindowStyle Hidden`: a `powershell` from PATH can be hijacked, and without `Hidden` a console window flashes on every Stop.

**Step 3** (optional) — install the behavior skill:

```powershell
Copy-Item skills\claude-task-notify "$HOME\.claude\skills\" -Recurse
```

The skill teaches Claude to end replies with `✅ Done: …` / `❓ Need from you: …` markers, which improves the toast's smart detection.

**Step 4** (optional) — declare the capability in `~/.claude/CLAUDE.md` so new sessions know about it:

```markdown
# Task completion toast (global)
> Hook configured: a bottom-right toast fires on every task end (✅ complete / ❓ needs input).
> Test: see the repo README "Test it" section — feed a Stop-event JSON into notify-complete.ps1's stdin.
```

### Test it

```powershell
# Feed a Stop-event JSON to the entry via stdin; a toast should pop quickly
# ⚠️ PS 5.1's $OutputEncoding defaults to ASCII — set UTF-8 or non-ASCII degrades to "?"
$OutputEncoding = [Text.Encoding]::UTF8
$evt = @{ session_id="test"; cwd=(Get-Location).Path; hook_event_name="Stop";
          stop_hook_active=$false; last_assistant_message="Toast works" } | ConvertTo-Json
$evt | & "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "$HOME\.claude\scripts\notify-complete.ps1"
```

Check the log at `%TEMP%\claude-code-notify\notify.log` (`OK` = notified, `DEDUPE` = collapsed, `SKIP` = filtered).

## ⚙️ Configuration

Open `弹窗参数调整器.html` (the visual tuner) in a browser, drag the sliders with a live preview, then paste the generated constants back into the top of `show-popup.ps1` (`$W` / `$H` / `$F_TITLE` / `$F_BODY`, …).

> The preview is auto-calibrated for your system scale (150% default, adjustable on the page) × browser zoom — it matches the real toast's physical size regardless of browser window zoom.

| Setting | Default | Description |
|---|---|---|
| `$W` / `$H` | 400 / 200 | Card width / height (px at 100% DPI, scaled automatically) |
| `$PAD_X` / `$PAD_TOP` | 20 / 15 | Title left / top padding |
| `$BODY_TOP` / `$BODY_H` | 52 / 80 | Body top offset / body area height |
| `$F_TITLE` / `$F_BODY` | 12 / 10 (×1.3333 in script) | Title / body font size (pt; WPF uses DIP px, pt→px ×4/3) |
| `$MAX_CHARS` | 180 | Summary truncation length — top of `notify-complete.ps1` |
| `$MARGIN` | 20 | Margin from the screen's bottom-right corner |
| `$PERSIST_MAX_MS` | 30 min | Safety timeout for persistent popups — top of `show-popup.ps1` |

Persistence toggle: `/notify_AskUserQuestion_persistence true|false` (default `true` = wait popups stay; `false` = 8-second auto-dismiss).

## ❓ FAQ

| Symptom | Fix |
|---|---|
| No toast at all | Check `%TEMP%\claude-code-notify\notify.log`: `SKIP` = filtered (subagent / permission noise / recursion), `DEDUPE` = duplicate within 2 s, `ERR` = input or spawn failure |
| Mojibake (garbled non-ASCII) | Both `.ps1` files must be **UTF-8 with BOM** (PS 5.1 reads BOM-less UTF-8 as ANSI). The repo files ship with BOM; re-save with BOM if you edited them |
| Blurry text | Rendering is WPF (DirectWrite) — as crisp as the browser. If still blurry, check your display scaling settings |
| Duplicate toasts (with system notification) | Disable Claude Code's built-in notification in `/config` (hooks and system notifications don't suppress each other) |
| Card content truncated | Use the tuner to raise `$BODY_H` / `$H` or lower font sizes |
| Wait popup never disappears | By design it persists (you are being reminded) — click ✕, or answer/approve to auto-close (30-min safety timeout); `/notify_AskUserQuestion_persistence false` reverts to 8 s |
| Permission popup didn't auto-close after approval | Fixed (two generations: ① `PermissionRequest` has no `tool_use_id` → content-fingerprint channel; ② a fixed matcher list missed WebFetch/Skill etc. → all-tool mount + cmd pre-filter). In the rare case of a denied tool with no follow-up event it degrades to manual ✕ / 30-min safety timeout |
| Occasional `ERR invalid-json` in manual tests | Intermittent PS 5.1 pipe issue (test path only; real hooks write UTF-8 stdin from Node, unaffected) — just re-run |
| Two cards when asking a question | Old-version issue (AskUserQuestion permission noise) — update `notify-complete.ps1` |

## 📝 Changelog

### 2026-09-19 — All-tool close-signal coverage

- Root cause: the close-signal hooks used a fixed matcher list (`Bash|Edit|Write|MultiEdit|NotebookEdit`); permission prompts from tools outside the list (WebFetch, Skill, MCP, …) never fired the "tool finished" hook, so their popups stayed on screen forever.
- Fix: matcher `*` on PostToolUse / PostToolUseFailure / PermissionDenied + new `notify-close-check.cmd` pre-filter (≈30 ms early-exit when nothing waits; no PowerShell cold start).

### 2026-09-18 — Wait-popup auto-close fixed

- Root cause: `PermissionRequest` carries **no `tool_use_id`** (by design) — permission popups could never match a close signal.
- Fix: dual-channel close signals (tool-call ID + content fingerprint `SHA256(tool_name+tool_input)[:16]`), `waiting-*` handshake files (zero files when nothing waits), plus `PermissionDenied` coverage.

### 2026-09-17 — First release: wait reminders & persistent popups

- Four bug fixes (dedupe timezone, 30-DIP positioning offset, question double-toast, docs/pipes).
- New: ❓/⏳ wait reminders on question / permission, persistent by default with auto-close, `/notify_AskUserQuestion_persistence` command.

<details>
<summary>Earlier (2026-08) — initial development</summary>

- Stop-hook toast MVP → full WPF rewrite (DirectWrite), multi-monitor/DPI positioning, non-blocking spawn architecture, dedupe, masked logging, nine rounds of external review hardening.

</details>

## 🛠 Development

No build step — the scripts are the product.

- `scripts/notify-complete.ps1` — hook entry (filter / summarize / dedupe / spawn).
- `scripts/show-popup.ps1` — the toast UI process.
- `scripts/notify-close-check.cmd` — close-signal pre-filter (must stay **ASCII, no BOM**; cmd chokes on a BOM).
- Both `.ps1` files **must be saved as UTF-8 with BOM** (PS 5.1 reads BOM-less UTF-8 as ANSI).
- After editing, verify syntax: `[System.Management.Automation.Language.Parser]::ParseFile('...', [ref]$null, [ref]$errs)`.
- Test by feeding event JSON to the entry (see "Test it"); watch `%TEMP%\claude-code-notify\notify.log`.

## 🗑 Uninstall

1. Remove the `hooks` entries from `~/.claude/settings.json` (or just the six notify entries, keeping your other hooks).
2. Delete `notify-complete.ps1`, `show-popup.ps1`, `notify-close-check.cmd` and `notify-config.json` from `~/.claude/scripts/`.
3. Delete `~/.claude/skills/claude-task-notify/` and `~/.claude/commands/notify_AskUserQuestion_persistence.md`.
4. Remove the appended section from `~/.claude/CLAUDE.md` (if any).
5. Optional: delete `%TEMP%\claude-code-notify\`.

## 📄 License & Credits

MIT — see [LICENSE](LICENSE).

UX inspired by the ChatGPT desktop app and Codex's completion toast: non-modal, focus-free, bottom-right, auto-dismiss.
