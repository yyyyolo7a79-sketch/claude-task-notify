<div align="center">

**Language / 语言 / 語言 / 言語 / 언어**

[**English**](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](docs/zh-TW/README.md) | [日本語](docs/ja-JP/README.md) | [한국어](docs/ko-KR/README.md)

</div>

---

# Claude Code 任务完成弹窗（claude-task-notify）

> Claude Code 在 Windows 上的 ChatGPT 风格桌面卡片——✅ 任务完成 / ❓ 需要用户提供相关信息 / ⏳ 在等你回答或批准。等待类弹窗持久显示、**作答或批准后自动关闭**。纯系统 PowerShell + WPF，**零第三方依赖**。
>
> 📄 此文件为精简翻译版；完整内容以 [English README](README.md) 为准。

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Windows](https://img.shields.io/badge/Windows-10%2F11-0078D4?logo=windows&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1-5391FE?logo=powershell&logoColor=white)
![Claude Code](https://img.shields.io/badge/Claude%20Code-v2.x-D97757?logo=claude&logoColor=white)
[![Stars](https://img.shields.io/github/stars/yyyyolo7a79-sketch/claude-task-notify?style=flat)](https://github.com/yyyyolo7a79-sketch/claude-task-notify/stargazers)
[![Downloads](https://img.shields.io/github/downloads/yyyyolo7a79-sketch/claude-task-notify/total?style=flat)](https://github.com/yyyyolo7a79-sketch/claude-task-notify/releases)

---

## ✨ 功能

- **强制生效**——由 Claude Code 的 hook 触发（harness 层执行，配置在 `~/.claude/settings.json`），每次 Claude 停止响应必然弹窗，不依赖模型自觉。
- **智能反馈**——回复以问号结尾或含请求词（"请提供…"）→ **❓ 需要用户提供相关信息**；否则 → **✅ 任务完成**（8 秒自动消失）。
- **回复摘要**——卡片正文显示本次回复首段（截断 180 字，自动清洗代码块/HTML/实体/URL），不切回终端也知道 Claude 说了什么。
- **项目名**——标题旁显示当前项目目录名，多项目同时运行一眼区分。
- **等待提醒**——Claude **提问**（AskUserQuestion）或**权限确认**时弹「❓ 在等你回答」「⏳ 在等你批准操作」卡片（附问题/命令摘要）——你在别的窗口写代码也不会错过等待。
- **持久弹窗，作答即关**——等待类卡片一直显示，直到：你作答/批准（**自动关闭**）、手动点 ✕、或 30 分钟安全阀到期。`/notify_AskUserQuestion_persistence false` 可切回 8 秒自动消失。
- **自动关闭信号通道**——监听**所有工具**的 PostToolUse / PostToolUseFailure / PermissionDenied（覆盖 WebFetch、WebSearch、Skill、MCP 工具等一切可能弹权限的工具），经轻量前置过滤器 `notify-close-check.cmd`：**无等待弹窗时约 +30ms 秒退**（不启动 PowerShell），有弹窗等待时才走完整链路。双通道匹配（工具调用 ID + 工具参数内容指纹——权限请求事件官方设计不带 ID）；弹窗存活期间以 `waiting-*` 握手文件登记，无等待者不产生任何信号文件。
- **去重与过滤**——同一会话 2 秒内重复事件只弹一次；AskUserQuestion 自身的权限噪音自动跳过。
- **全局生效**——配置在用户级 `~/.claude/settings.json`，对所有项目生效。
- **零第三方依赖**——仅用系统自带的 PowerShell 5.1 + WPF（DirectWrite 渲染，文字与浏览器同源清晰）。
- **不抢焦点**——`ShowActivated=false` + `WS_EX_NOACTIVATE`，绝不打断你正在进行的输入。
- **非阻塞**——hook 入口 500ms 内返回，弹窗 UI 由独立进程管理。
- **脱敏日志**——`%TEMP%\claude-code-notify\notify.log`（200KB 滚动），只记时间/会话前 8 位/结果，不落全文。

### 弹窗效果

```
┌────────────────────────────────┐
│ ✅  任务完成                    │
│ 已完成所有修改，共改动 3 个文    │
│ 件，测试全部通过。              │
└────────────────────────────────┘
   ↑ 右下角 · 白底圆角 · 淡入淡出
     8 秒自动消失 · 点击/✕ 立即关闭
```

## 🔧 工作原理

```
Claude Code 事件（~/.claude/settings.json 全局配置，timeout 5s）
        │  stdin JSON
        ├─ Stop（主回复结束）──────────────────┐
        ├─ PreToolUse(AskUserQuestion)（提问，等你回答）─┤
        ├─ PermissionRequest（权限确认，等你批准）───────┤
        └─ PostToolUse / PostToolUseFailure / PermissionDenied（全部工具）
           → notify-close-check.cmd 前置过滤（无 waiting 秒退）
           → 有 waiting 才启动 PS 写关闭标志 → exit ─────┘
        ▼
notify-complete.ps1（入口，500ms 内返回）
        │  ① 过滤事件类型（跳过 AskUserQuestion 自身的权限噪音）
        │  ② 本地确定性摘要（代码块/HTML/实体/URL → 首段 180 字）
        │  ③ 去重：SHA-256(session+内容)，2 秒窗口
        │  ④ 写临时 payload（persist/toolUseId/contentKey）→ 派生独立 UI 进程
        ▼
show-popup.ps1（独立进程，-STA）
        │  读取 payload 后删除 → 写 waiting 握手 → WPF(DirectWrite) 渲染
        ▼
右下角非模态卡片：不抢焦点 · 圆角+阴影 · 点击/✕ 关闭
  · Stop：8 秒自动淡出
  · 等待类（提问/权限确认）：作答/批准后自动关闭（双通道信号）· 手动 ✕ · 30 分钟安全阀
```

## 🚀 快速开始

> 环境要求：Windows 10/11 · Claude Code v2.x · PowerShell 5.1（系统自带）

### 用 Claude Code 安装（推荐）

把下面这段话连同本仓库链接一起发给你的 Claude Code，它会自动完成全部安装并自测：

> 请把仓库 `https://github.com/yyyyolo7a79-sketch/claude-task-notify` 安装到我的全局配置（Windows）：
> 1. 将 `scripts\` 下的 `notify-complete.ps1`、`show-popup.ps1`、`notify-close-check.cmd` 复制到 `~\.claude\scripts\`
> 2. 在 `~\.claude\settings.json` 顶层添加 hook（已有其他条目保留追加、不要覆盖）：`Stop`（matcher 空）· `PreToolUse`（matcher `AskUserQuestion`）· `PermissionRequest`（matcher 空）· `PostToolUse` / `PostToolUseFailure` / `PermissionDenied`（matcher `*` 全工具）；弹窗类 command 用绝对解释器路径 + `-WindowStyle Hidden`（`"\"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe\" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"C:\Users\<你的用户名>\.claude\scripts\notify-complete.ps1\""`），关闭信号类 command 指向前置过滤器（`"\"C:\Users\<你的用户名>\.claude\scripts\notify-close-check.cmd\""`）；`"timeout": 5`
> 3. 将 `skills\claude-task-notify\` 复制到 `~\.claude\skills\`；将 `commands\notify_AskUserQuestion_persistence.md` 复制到 `~\.claude\commands\`
> 4. 在 `~\.claude\CLAUDE.md` 末尾追加「任务完成弹窗」小节（见手动安装第 4 步）
> 5. 自测（先设 `$OutputEncoding = [Text.Encoding]::UTF8`）：`$OutputEncoding = [Text.Encoding]::UTF8; $evt = @{session_id="test"; cwd=(Get-Location).Path; hook_event_name="Stop"; stop_hook_active=$false; last_assistant_message="弹窗工作正常"} | ConvertTo-Json; $evt | & "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "$HOME\.claude\scripts\notify-complete.ps1"`

### 手动安装

**第 1 步**——拷贝脚本：

```powershell
# 三个文件复制到用户级脚本目录
Copy-Item scripts\notify-complete.ps1 "$HOME\.claude\scripts\"
Copy-Item scripts\show-popup.ps1 "$HOME\.claude\scripts\"
Copy-Item scripts\notify-close-check.cmd "$HOME\.claude\scripts\"
```

**第 2 步**——配置全局 hook。编辑 `~/.claude/settings.json`，在顶层新增 `hooks` 键（保留原有配置）：

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

> `<CMD>` 即：`"\"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe\" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"C:\\Users\\<你的用户名>\\.claude\\scripts\\notify-complete.ps1\""`。若 `PostToolUse` 等键下已有其他条目，**追加**而非覆盖。
>
> 💡 `<CMD2>` = `"\"C:\\Users\\<你的用户名>\\.claude\\scripts\\notify-close-check.cmd\""` 是「等待弹窗自动关闭」的信号通道（matcher `*`）：**无等待弹窗时每次工具完成约 +30ms**（前置过滤器秒退、不启动 PowerShell），等待中约 +0.2 秒。删除这三个条目则等待弹窗退化为手动关闭 / 30 分钟安全阀。

> ⚠️ 把 `<你的用户名>` 替换为实际路径；配置后无需重启，下一次任务即生效。UI 进程由入口自动派生（`-STA` 已内置）。
>
> 💡 解释器必须用绝对路径 + `-WindowStyle Hidden`：PATH 里的 `powershell` 可被劫持，且不加 `Hidden` 每次 Stop 会闪现控制台窗口。

**第 3 步**（可选）——行为规范 skill：

```powershell
Copy-Item skills\claude-task-notify "$HOME\.claude\skills\" -Recurse
```

该 skill 让 Claude 收尾时用 `✅ 已完成：…` / `❓ 需要你提供：…` 格式结束回复，提高弹窗判断准确率。

**第 4 步**（可选）——`~/.claude/CLAUDE.md` 末尾追加声明（便于新会话知晓该能力）：

```markdown
# 任务完成弹窗（全局强制）
> hook 已配置：每次任务结束右下角自动弹窗（✅任务完成 / ❓需要用户提供相关信息）。
> 测试：向 notify-complete.ps1 的 stdin 喂 Stop 事件 JSON 即可触发弹窗。
```

### 测试

```powershell
# 直接测入口（stdin 喂 Stop 事件 JSON，应快速返回并弹出卡片）
# ⚠️ PS 5.1 的 $OutputEncoding 默认 ASCII——不设 UTF-8 时管道中文会降级为 "?"
$OutputEncoding = [Text.Encoding]::UTF8
$evt = @{ session_id="test"; cwd=(Get-Location).Path; hook_event_name="Stop";
          stop_hook_active=$false; last_assistant_message="弹窗工作正常" } | ConvertTo-Json
$evt | & "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "$HOME\.claude\scripts\notify-complete.ps1"
```

测试结果见日志 `%TEMP%\claude-code-notify\notify.log`（`OK` = 已通知，`DEDUPE` = 去重，`SKIP` = 被过滤）。

## ⚙️ 参数调整

浏览器打开 `弹窗参数调整器.html`，拖动滑块实时预览卡片效果，调好后把页面生成的参数代码发回，替换 `show-popup.ps1` 顶部常量区即可。

> 预览已按「系统缩放（默认 150%，可在页面调整）× 浏览器缩放」自动校准，所见即真实弹窗的物理大小。

| 参数 | 默认值 | 说明 |
|---|---|---|
| `$W` / `$H` | 400 / 200 | 卡片宽度 / 高度（px，100% DPI 基准，自动按系统缩放） |
| `$PAD_X` / `$PAD_TOP` | 20 / 15 | 标题左边距 / 上边距 |
| `$BODY_TOP` / `$BODY_H` | 52 / 80 | 正文上边距 / 正文区域高度 |
| `$F_TITLE` / `$F_BODY` | 12 / 10（脚本内 `* 1.3333`） | 标题 / 正文字号（pt；WPF 单位是 DIP px，pt→px ×4/3） |
| `$MAX_CHARS` | 180 | 摘要截断长度——在 `notify-complete.ps1` 顶部 |
| `$MARGIN` | 20 | 弹窗距屏幕右下角边距 |
| `$PERSIST_MAX_MS` | 30 分钟 | 持久弹窗安全阀——在 `show-popup.ps1` 顶部 |

持久化开关：`/notify_AskUserQuestion_persistence true|false`（默认 `true` = 等待类弹窗持久；`false` = 8 秒消失）。

## ❓ 常见问题

| 现象 | 处理 |
|---|---|
| 弹窗不出现 | 看日志 `%TEMP%\claude-code-notify\notify.log`：`SKIP` = 被过滤（子代理/权限噪音/递归）、`DEDUPE` = 2 秒内重复、`ERR` = 输入或派生失败 |
| 中文乱码 | 两个 `.ps1` 必须是 **UTF-8 with BOM**（PS 5.1 对无 BOM 的 UTF-8 按 ANSI 解释）。仓库文件已带 BOM，编辑过请重新保存为 UTF-8 with BOM |
| 文字模糊 | 已用 WPF（DirectWrite）渲染，与浏览器同源清晰；如仍模糊请检查显示器缩放设置 |
| 与系统通知双弹 | `/config` 中关闭 Claude Code 内置通知 |
| 弹窗内容被截断 | 用调整器调大 `$BODY_H` / `$H` 或减小字号 |
| 等待弹窗一直不消失 | 持久模式的设计（你在等待被提醒）——点 ✕ 关闭，或作答后自动关（安全阀 30 分钟）；`/notify_AskUserQuestion_persistence false` 可切回 8 秒 |
| 权限弹窗批准后没自动消失 | 已修复（两代问题：① 权限请求事件无 ID → 内容指纹通道；② 固定 matcher 列表漏 WebFetch/Skill 等工具 → 全工具挂载 + cmd 前置过滤）；仅在极罕见场景（工具被拒后无后续事件）退化为手动 ✕ / 30 分钟安全阀 |
| 测试命令偶发 `ERR invalid-json` | PS 5.1 管道传输的间歇问题（仅测试链路；真实 hook 由 Node 写 stdin 不受影响）——重跑一次即可 |
| 提问时弹出两张卡片 | 旧版已知问题（AskUserQuestion 权限噪音）——更新 `notify-complete.ps1` 到最新版即可 |

## 📝 更新日志

### 2026-09-19 — 全工具关闭信号覆盖

- 根因：关闭信号 hook 用了固定 matcher 列表（`Bash|Edit|Write|MultiEdit|NotebookEdit`）——列表外工具（WebFetch、Skill、MCP 等）的权限弹窗永远不会收到"工具完成"信号，一直滞留。
- 修复：三个关闭信号事件 matcher 改 `*` 全工具 + 新增 `notify-close-check.cmd` 前置过滤器（无等待时约 30ms 秒退，不启动 PowerShell）。

### 2026-09-18 — 等待弹窗自动关修复

- 根因：权限请求事件（PermissionRequest）官方设计**没有 `tool_use_id`**——权限弹窗无法匹配关闭信号。
- 修复：双通道关闭信号（调用 ID + 内容指纹 `SHA256(tool_name+tool_input)[:16]`）、`waiting-*` 握手文件（无等待者零文件）、补 `PermissionDenied` 事件。

### 2026-09-17 — 首个版本：等待提醒与持久弹窗

- 4 个 bug 修复（去重时区、定位偏移 30 DIP、提问双弹窗、文档/管道）。
- 新增：提问/权限确认时的 ❓/⏳ 等待提醒，默认持久 + 作答自动关，`/notify_AskUserQuestion_persistence` 命令。

> 📖 完整历史（含更早的初始开发阶段）见 [English README](README.md#-changelog)。

## 📄 许可证与致谢

MIT——见 [LICENSE](LICENSE)。

交互灵感来自 ChatGPT 桌面端与 Codex 的任务完成弹窗：非模态、不抢焦点、右下角、自动消失。
