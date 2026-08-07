---
name: claude-task-notify
description: 任务完成弹窗 — Claude Code 每次完成任务时右下角自动弹出 ChatGPT 风格反馈卡片（✅任务完成 / ❓需要用户提供相关信息，附回复摘要）。由全局 Stop hook 强制触发（harness 层执行，无需模型自觉），本 skill 定义 Claude 收尾行为规范、测试入口与卸载方法。触发词：弹窗、通知、任务完成、反馈、task-notify、toast、右下角
---

# Claude Task Notify — 任务完成右下角弹窗

## 能力说明

Claude Code 每次停止响应（任务回合结束）时，Windows 右下角自动弹出白色反馈卡片：

- ✅ **任务完成** — 若本次回复以问号结尾或包含请求词（"请提供…""需要你…"），则显示 ❓ **需要用户提供相关信息**
- 正文附本次回复的摘要（首句，截断 50 字，自动换行）
- 白色圆角卡片（黑字）、淡入淡出、5 秒自动消失、点击或按 Esc 立即关闭

**触发机制**：全局 `~/.claude/settings.json` 的 `Stop` hook → `~/.claude/scripts/task-notify.ps1`。这是 **harness 层强制执行**，对**所有项目**生效，与模型行为无关——不需要本 skill 被触发，弹窗也照常出现。

## Claude 收尾行为规范（与弹窗判断配合）

任务结束时，最后一句用简短反馈收尾，格式与弹窗标题呼应：

- 已完成 → `✅ 已完成：<一句话总结>`
- 需要用户输入 → `❓ 需要你提供：<具体缺失信息>`

**Why:** hook 的启发式判断（问号结尾 / 请求词）能据此准确识别"需要用户提供相关信息"，弹窗反馈更准确、不误报。
**How to apply:** 每次回复的收尾句遵循上述格式即可，无需额外操作。

## 测试入口

用户说「测试弹窗」时执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\PC\.claude\scripts\task-notify.ps1" -Title "测试" -Message "弹窗工作正常" -Type done
```

- `-Type done` → ✅ 任务完成；`-Type need_info` → ❓ 需要用户提供相关信息

## 诊断速查

| 现象 | 处理 |
|---|---|
| 弹窗不出现 | 检查 `~/.claude/settings.json` 是否含 `hooks` 键；用上方测试命令确认脚本本身可用 |
| 中文乱码 | `task-notify.ps1` 必须是 **UTF-8 with BOM**（PS 5.1 对无 BOM 的 UTF-8 按 ANSI/GBK 解释） |
| 与系统通知重复弹 | 在 `/config` 中关闭 Claude Code 内置通知（hooks 弹窗与系统通知互不抑制） |

## 卸载

1. 删除 `~/.claude/settings.json` 中的 `hooks` 键（备份在 `settings.json.bak`）
2. 删除 `~/.claude/scripts/task-notify.ps1`
3. 删除本 skill 目录与 `CLAUDE.md` 中「任务完成弹窗（全局强制）」小节
