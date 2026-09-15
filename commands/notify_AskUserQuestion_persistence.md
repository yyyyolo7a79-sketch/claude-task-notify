---
description: 开关「等待类弹窗」持久化——提问/权限确认弹窗是否一直显示到手动关闭或作答后自动关闭（默认 true）
allowed-tools: Read, Write
---

用户输入了斜杠命令，参数为：$ARGUMENTS

任务：维护配置文件 `~/.claude/scripts/notify-config.json`（即 `C:\Users\<你的用户名>\.claude\scripts\notify-config.json`）中的 `askUserQuestionPersistence` 字段（控制「等待类弹窗」（Claude 提问 / 权限确认）是否持久显示）。

规则：
- 参数为 `true` / `false`（不区分大小写）→ 更新该字段为对应布尔值
- 参数为空 → 只读取现值并报告，不修改
- 参数为其他内容 → 提示用法：`/notify_AskUserQuestion_persistence true|false`
- 配置文件不存在 → 先创建（初始值 `true`），再按参数处理
- 修改时保持 JSON 格式（可保留其他字段）

完成后用一行中文回报：
- 持久开启：`✅ 等待类弹窗持久化 = true —— 提问/权限确认弹窗会一直显示，直到你手动关闭或作答后自动关闭（安全阀：最长 30 分钟）`
- 持久关闭：`✅ 等待类弹窗持久化 = false —— 提问/权限确认弹窗 8 秒后自动消失`
