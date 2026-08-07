# Claude Code 任务完成弹窗（claude-task-notify）

> 让 Claude Code **每次完成任务**时，在 Windows 右下角弹出 ChatGPT 桌面端风格的反馈卡片——✅ 任务完成 / ❓ 需要用户提供相关信息，附带本次回复摘要。

## ✨ 功能

- **强制生效**：由 Claude Code 的 `Stop` hook 触发（harness 层执行），每次 Claude 停止响应必然弹窗，不依赖模型自觉
- **智能反馈**：自动分析本次回复——以问号结尾或包含请求词（"请提供…""需要你…"）→ ❓「需要用户提供相关信息」；否则 → ✅「任务完成」
- **回复摘要**：正文显示本次回复首句（默认截断 50 字），不切回终端也能知道 Claude 说了什么
- **全局生效**：配置在用户级 `~/.claude/settings.json`，对所有项目生效
- **零第三方依赖**：仅用系统自带的 PowerShell 5.1 + WinForms，无需安装任何模块
- **不抢焦点**：弹窗以 SW_SHOWNA 方式显示，不会抢占你正在进行的输入

### 弹窗效果

```
┌────────────────────────────────┐
│ ✅  任务完成                     │
│ 已完成所有修改，共改动 3 个文    │
│ 件，测试全部通过。后续如需部署…  │
└────────────────────────────────┘
   ↑ 右下角 · 白底黑字 · 圆角 · 淡入淡出
     5 秒自动消失 · 点击/Esc 立即关闭
```

## 🔧 工作原理

```
Claude Code 停止响应
        │
        ▼
Stop hook（~/.claude/settings.json 全局配置）
        │  stdin JSON（含 last_assistant_message 字段）
        ▼
task-notify.ps1（PowerShell 5.1）
        │  启发式判断 + 摘要提取
        ▼
WinForms 卡片弹窗（右下角，5 秒淡出）
```

- `Stop` hook 在每次 assistant 响应结束后触发，stdin 负载直接包含 `last_assistant_message`（本次回复全文），无需解析 transcript
- hook 返回空（无 stdout 输出）= 不干预 Claude 的停止行为，无副作用
- 与 `/config` 内置系统通知互不抑制；若同时开启会双弹，关闭内置通知即可

## 📁 目录结构

```
claude-task-notify/
├── README.md                        # 本文件
├── 需求.md                          # 原始需求
├── 弹窗参数调整器.html              # 可视化参数调整工具（浏览器打开）
├── scripts/
│   └── task-notify.ps1              # 弹窗脚本（核心）
└── skills/
    └── claude-task-notify/
        └── SKILL.md                 # 行为规范 skill（可选安装）
```

## 📦 安装

> 环境要求：Windows 10/11，Claude Code v2.x，PowerShell 5.1（系统自带）

**第 1 步**：拷贝脚本

```powershell
# 把 scripts/task-notify.ps1 复制到用户级脚本目录
Copy-Item scripts\task-notify.ps1 "$HOME\.claude\scripts\"
```

**第 2 步**：配置全局 hook

编辑 `~/.claude/settings.json`，在顶层新增 `hooks` 键（保留原有配置）：

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"C:\\Users\\<你的用户名>\\.claude\\scripts\\task-notify.ps1\"",
            "timeout": 60
          }
        ]
      }
    ]
  }
}
```

> ⚠️ 把 `<你的用户名>` 替换为实际路径；配置后无需重启，下一次任务结束即生效。

**第 3 步**（可选）：安装行为规范 skill

```powershell
Copy-Item skills\claude-task-notify "$HOME\.claude\skills\" -Recurse
```

该 skill 让 Claude 收尾时用 `✅ 已完成：…` / `❓ 需要你提供：…` 格式结束回复，与弹窗判断互相印证，提高识别准确率。

**第 4 步**（可选）：`~/.claude/CLAUDE.md` 末尾追加声明（便于新会话知晓该能力）：

```markdown
# 任务完成弹窗（全局强制）
> hook 已配置：每次任务结束右下角自动弹窗（✅任务完成 / ❓需要用户提供相关信息）。
> 测试：powershell -NoProfile -ExecutionPolicy Bypass -File "$HOME\.claude\scripts\task-notify.ps1" -Title "测试" -Message "正常" -Type done
```

## 🎨 参数调整

打开 `弹窗参数调整器.html`（浏览器），拖动滑块实时预览卡片效果，调好后把页面右下角生成的参数代码发回，替换 `task-notify.ps1` 中的对应值即可：

| 参数 | 默认值 | 说明 |
|---|---|---|
| `$W` / `$H` | 380 / 150 | 卡片宽度 / 高度（px，100% DPI 基准，自动按系统缩放） |
| `$PAD_X` / `$PAD_TOP` | 20 / 14 | 标题左边距 / 上边距 |
| `$BODY_TOP` / `$BODY_H` | 34 / 60 | 正文上边距 / 正文区域高度 |
| `$F_TITLE` / `$F_BODY` | 8 / 7 | 标题 / 正文字号（pt） |
| `$MAX_CHARS` | 50 | 摘要截断长度（字） |
| `$MARGIN` | 20 | 弹窗距屏幕右下角边距 |

## 🧪 手动测试

```powershell
# ✅ 任务完成
powershell -NoProfile -ExecutionPolicy Bypass -File "$HOME\.claude\scripts\task-notify.ps1" -Title "测试" -Message "弹窗工作正常" -Type done

# ❓ 需要用户提供相关信息
powershell -NoProfile -ExecutionPolicy Bypass -File "$HOME\.claude\scripts\task-notify.ps1" -Title "测试" -Message "请提供报错日志" -Type need_info
```

## ❓ 常见问题

| 现象 | 处理 |
|---|---|
| 弹窗不出现 | 确认 `settings.json` 含 `hooks` 键且 JSON 合法；用上方测试命令确认脚本可用 |
| 中文乱码 | `task-notify.ps1` 必须是 **UTF-8 with BOM**（PowerShell 5.1 对无 BOM 的 UTF-8 按 ANSI/GBK 解释）。本仓库文件已带 BOM，若编辑过请重新保存为 UTF-8 with BOM |
| 文字模糊 | 脚本已声明 DPI aware（`SetProcessDPIAware`），高分屏（125%/150% 缩放）自动清晰 |
| 与系统通知双弹 | `/config` 中关闭 Claude Code 内置通知（hooks 弹窗与系统通知互不抑制） |
| 弹窗内容被截断 | 用 `弹窗参数调整器.html` 调大 `$BODY_H` / `$H` 或减小字号 |

## 🗑 卸载

1. 删除 `~/.claude/settings.json` 中的 `hooks` 键
2. 删除 `~/.claude/scripts/task-notify.ps1`
3. 删除 `~/.claude/skills/claude-task-notify/` 目录
4. 删除 `~/.claude/CLAUDE.md` 中追加的小节（若有）

## 📄 许可证

MIT
