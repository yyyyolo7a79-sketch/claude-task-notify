---
name: claude-task-notify
description: 任务完成弹窗 — Claude Code 每次完成任务时右下角自动弹出 ChatGPT 风格反馈卡片（✅任务完成 / ❓需要用户提供相关信息，附回复摘要）。由全局 Stop hook 强制触发（harness 层执行，无需模型自觉），本 skill 定义 Claude 收尾行为规范、测试入口与卸载方法。触发词：弹窗、通知、任务完成、反馈、task-notify、toast、右下角
---

# Claude Task Notify — 任务完成右下角弹窗

## 能力说明

Claude Code 的关键「等待/完成」时刻，Windows 右下角自动弹出白色反馈卡片：

- ✅ **任务完成**（Stop）— 若本次回复以问号结尾或包含请求词（"请提供…""需要你…"），则显示 ❓ **需要用户提供相关信息**；8 秒自动消失
- ❓ **Claude 在等你回答**（提问时，PreToolUse:AskUserQuestion）— 正文附问题内容；**持久显示**，作答后自动关闭 / 手动关闭（安全阀 30 分钟）
- ⏳ **Claude 在等你批准操作**（权限确认时，PermissionRequest）— 正文附工具名与命令摘要；持久显示，**批准后自动关闭** / 手动关闭（安全阀 30 分钟）
- 正文自动清洗（截断 180 字、自动换行）；白色圆角卡片（黑字）、淡入淡出、点击卡片或右上角 ✕ 立即关闭（无 Esc——无焦点窗口收不到键盘事件）
- 持久化开关：`/notify_AskUserQuestion_persistence true|false`（默认 true = 持久）

**触发机制**：全局 `~/.claude/settings.json` 的 6 类 hook（弹窗：`Stop` / `PreToolUse:AskUserQuestion` / `PermissionRequest`；关闭信号：`PostToolUse` / `PostToolUseFailure` / `PermissionDenied`）→ `~/.claude/scripts/notify-complete.ps1`（hook 命令必须是绝对解释器路径 + `-WindowStyle Hidden`，否则每次 Stop 闪现控制台窗口）。等待类弹窗的自动关闭为双通道匹配（工具调用 ID + 工具参数内容指纹——PermissionRequest 官方设计不含 ID，指纹是权限弹窗的唯一关联键），且仅在弹窗存活（waiting 握手存在）时写信号。这是 **harness 层强制执行**，对**所有项目**生效，与模型行为无关——不需要本 skill 被触发，弹窗也照常出现。

## Claude 收尾行为规范（与弹窗判断配合）

任务结束时，最后一句用简短反馈收尾，格式与弹窗标题呼应：

- 已完成 → `✅ 已完成：<一句话总结>`
- 需要用户输入 → `❓ 需要你提供：<具体缺失信息>`

**Why:** hook 的启发式判断（问号结尾 / 请求词）能据此准确识别"需要用户提供相关信息"，弹窗反馈更准确、不误报。
**How to apply:** 每次回复的收尾句遵循上述格式即可，无需额外操作。

## 测试入口

用户说「测试弹窗」时执行（stdin 喂 Stop 事件 JSON）：

```powershell
# $OutputEncoding 必须设 UTF-8：PS 5.1 默认 ASCII，管道中文会降级为 "?"
$OutputEncoding = [Text.Encoding]::UTF8
$evt = @{ session_id="test"; cwd=(Get-Location).Path; hook_event_name="Stop";
          stop_hook_active=$false; last_assistant_message="弹窗工作正常" } | ConvertTo-Json
$evt | & "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "$HOME\.claude\scripts\notify-complete.ps1"
```

- 结尾带「请提供…」→ ❓ 需要用户提供相关信息；正常结尾 → ✅ 任务完成
- 测试结果见日志：`%TEMP%\claude-code-notify\notify.log`

## 诊断速查

| 现象 | 处理 |
|---|---|
| 弹窗不出现 | 看日志 `%TEMP%\claude-code-notify\notify.log`：`SKIP`=被过滤（子代理/权限/递归）、`DEDUPE`=2秒内重复、`ERR`=输入/派生失败 |
| 中文乱码 | `notify-complete.ps1` / `show-popup.ps1` 必须是 **UTF-8 with BOM**（PS 5.1 对无 BOM 的 UTF-8 按 ANSI/GBK 解释） |
| 与系统通知重复弹 | 在 `/config` 中关闭 Claude Code 内置通知（hooks 弹窗与系统通知互不抑制） |
| 等待弹窗没自动关 | 看 `%TEMP%\claude-code-notify\`：`waiting-*.flag` 在 = 弹窗还活着等信号；日志 `ch=` 空 = 无等待者（正常）、`ch=id/ck`（写了关闭信号）后应紧跟 `persist-close-by-answer`；工具被拒绝的极罕见场景退化为手动关 |
| 想临时关闭 | 删除 `settings.json` 中 `hooks` 键即可（脚本可保留） |

## 卸载

1. 删除 `~/.claude/settings.json` 中的 `hooks` 键（备份在 `settings.json.bak`）
2. 删除 `~/.claude/scripts/notify-complete.ps1` 与 `~/.claude/scripts/show-popup.ps1`
3. 删除本 skill 目录与 `CLAUDE.md` 中「任务完成弹窗（全局强制）」小节
4. 可选：删除临时目录 `%TEMP%\claude-code-notify\`
