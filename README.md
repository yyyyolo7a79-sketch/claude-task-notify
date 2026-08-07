# Claude Code 任务完成弹窗（claude-task-notify）

> 让 Claude Code **每次完成任务**时，在 Windows 右下角弹出 ChatGPT 桌面端风格的反馈卡片——✅ 任务完成 / ❓ 需要用户提供相关信息，附带本次回复摘要。

## ✨ 功能

- **强制生效**：由 Claude Code 的 `Stop` hook 触发（harness 层执行），每次 Claude 停止响应必然弹窗，不依赖模型自觉
- **智能反馈**：自动分析本次回复——以问号结尾或包含请求词（"请提供…""需要你…"）→ ❓「需要用户提供相关信息」；否则 → ✅「任务完成」
- **回复摘要**：正文显示本次回复首句（默认截断 180 字），自动清洗代码块/HTML 标签/实体/emoji/URL，不切回终端也能知道 Claude 说了什么
- **项目名**：标题旁显示当前项目目录名，多项目同时运行时一眼区分
- **全局生效**：配置在用户级 `~/.claude/settings.json`，对所有项目生效
- **零第三方依赖**：仅用系统自带的 PowerShell 5.1 + WPF（DirectWrite 渲染，文字与浏览器同源清晰），无需安装任何模块
- **不抢焦点**：WPF `ShowActivated=false` 显示，不会抢占你正在进行的输入
- **非阻塞架构**：hook 入口 500ms 内返回（过滤/去重/派生），UI 由独立进程管理，绝不阻塞 Claude Code
- **重复抑制**：同一会话 2 秒内重复事件只弹一次；忽略 `SubagentStop` 与权限交互
- **脱敏日志**：`%TEMP%\claude-code-notify\notify.log`（200KB 滚动），只记时间/会话前 8 位/结果，不落全文

### 弹窗效果

```
┌────────────────────────────────┐
│ ✅  任务完成                     │
│ 已完成所有修改，共改动 3 个文    │
│ 件，测试全部通过。后续如需部署…  │
└────────────────────────────────┘
   ↑ 右下角 · 白底黑字 · 圆角 · 淡入淡出
     8 秒自动消失 · 点击/✕ 立即关闭
```

## 🔧 工作原理

```
Claude Code 主 Agent 完成本轮回复
        │
        ▼
Stop hook（~/.claude/settings.json 全局配置，timeout 5s）
        │  stdin JSON（last_assistant_message / cwd / session_id）
        ▼
notify-complete.ps1（入口，500ms 内返回）
        │  ① 过滤：仅 Stop 且 stop_hook_active=false（忽略子代理/权限交互）
        │  ② 摘要：本地确定性清洗（代码块/HTML/实体/emoji/URL → 首段 50 字）
        │  ③ 去重：SHA-256(session+回复)，2 秒窗口内重复只弹一次
        │  ④ 写临时 payload → Start-Process 派生独立 UI 进程
        ▼
show-popup.ps1（独立进程，-STA）
        │  读取 payload 后立即删除 → WPF(DirectWrite) 渲染
        ▼
右下角非模态卡片：不抢焦点 · 圆角+阴影 · 8 秒自动淡出 · 点击/✕ 关闭（无 Esc——无焦点窗口收不到键盘事件）
```

- hook 入口**快速返回**（500ms 内），UI 生命周期由独立进程管理——弹窗显示期间 Claude Code 完全不受影响
- `Stop` 表示主 Agent 每轮回复结束（非会话退出）；`SubagentStop`、权限确认、工具确认一律不通知
- hook 不输出 stdout = 不干预 Claude 的停止行为，任何异常都被捕获并返回 `0`
- 与 `/config` 内置系统通知互不抑制；若同时开启会双弹，关闭内置通知即可

## 📁 目录结构

```
claude-task-notify/
├── README.md                        # 本文件
├── 原理以及文件路径.md              # 技术原理/文件路径/审查记录（供外部审查）
├── 弹窗参数调整器.html              # 可视化参数调整工具（浏览器打开）
├── 需求/                            # 原始需求与规格（不入库）
├── scripts/
│   ├── notify-complete.ps1          # hook 入口：过滤/摘要/去重/派生 UI
│   └── show-popup.ps1               # UI 进程：WPF 卡片弹窗（独立运行）
└── skills/
    └── claude-task-notify/
        └── SKILL.md                 # 行为规范 skill（可选安装）
```

## 📦 安装

> 环境要求：Windows 10/11，Claude Code v2.x，PowerShell 5.1（系统自带）

**第 1 步**：拷贝脚本

```powershell
# 把 scripts/ 下两个脚本复制到用户级脚本目录
Copy-Item scripts\notify-complete.ps1 "$HOME\.claude\scripts\"
Copy-Item scripts\show-popup.ps1 "$HOME\.claude\scripts\"
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
            "command": "\"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe\" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"C:\\Users\\<你的用户名>\\.claude\\scripts\\notify-complete.ps1\"",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

> ⚠️ 把 `<你的用户名>` 替换为实际路径；配置后无需重启，下一次任务结束即生效。UI 进程由入口自动派生（`-STA` 已内置），hook 本身无需 STA。
>
> 💡 解释器必须用绝对路径 + `-WindowStyle Hidden`：PATH 里的 `powershell` 可被劫持，且每次 Stop 都会闪现控制台窗口。

**第 3 步**（可选）：安装行为规范 skill

```powershell
Copy-Item skills\claude-task-notify "$HOME\.claude\skills\" -Recurse
```

该 skill 让 Claude 收尾时用 `✅ 已完成：…` / `❓ 需要你提供：…` 格式结束回复，与弹窗判断互相印证，提高识别准确率。

**第 4 步**（可选）：`~/.claude/CLAUDE.md` 末尾追加声明（便于新会话知晓该能力）：

```markdown
# 任务完成弹窗（全局强制）
> hook 已配置：每次任务结束右下角自动弹窗（✅任务完成 / ❓需要用户提供相关信息）。
> 测试：见下方「🧪 手动测试」，向 notify-complete.ps1 的 stdin 喂 Stop 事件 JSON 即可触发弹窗。
```

## 🎨 参数调整

打开 `弹窗参数调整器.html`（浏览器），拖动滑块实时预览卡片效果，调好后把页面右下角生成的参数代码发回，替换 `show-popup.ps1` 顶部常量区（`$W`/`$H`/`$F_TITLE`/`$F_BODY` 等）即可。

> 预览已按「系统缩放（默认 150%，可在页面调整）× 浏览器缩放」自动校准，所见即真实弹窗的物理大小——与浏览器窗口缩放无关。

| 参数 | 默认值 | 说明 |
|---|---|---|
| `$W` / `$H` | 400 / 200 | 卡片宽度 / 高度（px，100% DPI 基准，自动按系统缩放） |
| `$PAD_X` / `$PAD_TOP` | 20 / 15 | 标题左边距 / 上边距 |
| `$BODY_TOP` / `$BODY_H` | 52 / 80 | 正文上边距 / 正文区域高度 |
| `$F_TITLE` / `$F_BODY` | 12 / 10（脚本内 `* 1.3333`） | 标题 / 正文字号（pt；WPF FontSize 单位是 DIP px，pt→px ×4/3） |
| `$MAX_CHARS` | 180 | 摘要截断长度（字）——在 `notify-complete.ps1` 顶部，不在 show-popup |
| `$MARGIN` | 20 | 弹窗距屏幕右下角边距 |

## 🧪 手动测试

```powershell
# 直接测入口（stdin 喂 Stop 事件 JSON，应快速返回并弹出卡片）
$evt = @{ session_id="test"; cwd=(Get-Location).Path; hook_event_name="Stop";
          stop_hook_active=$false; last_assistant_message="弹窗工作正常" } | ConvertTo-Json
$evt | & "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "$HOME\.claude\scripts\notify-complete.ps1"
```

测试结果可在日志确认：`%TEMP%\claude-code-notify\notify.log`（`OK` = 已通知，`DEDUPE` = 去重，`SKIP` = 被过滤）。

## ❓ 常见问题

| 现象 | 处理 |
|---|---|
| 弹窗不出现 | 看日志 `%TEMP%\claude-code-notify\notify.log`：`SKIP` = 被过滤（子代理/权限/递归），`DEDUPE` = 2 秒内重复，`ERR` = 输入或派生失败 |
| 中文乱码 | 两个脚本必须是 **UTF-8 with BOM**（PowerShell 5.1 对无 BOM 的 UTF-8 按 ANSI/GBK 解释）。本仓库文件已带 BOM，若编辑过请重新保存为 UTF-8 with BOM |
| 文字模糊 | 已用 WPF（DirectWrite）渲染，与浏览器同源清晰；如仍模糊请确认显示器缩放设置正常 |
| 与系统通知双弹 | `/config` 中关闭 Claude Code 内置通知（hooks 弹窗与系统通知互不抑制） |
| 弹窗内容被截断 | 用 `弹窗参数调整器.html` 调大 `$BODY_H` / `$H` 或减小字号 |
| 想关掉弹窗 | 删除 `settings.json` 中 `hooks` 键即可（脚本可保留） |

## 🗑 卸载

1. 删除 `~/.claude/settings.json` 中的 `hooks` 键
2. 删除 `~/.claude/scripts/notify-complete.ps1` 与 `~/.claude/scripts/show-popup.ps1`
3. 删除 `~/.claude/skills/claude-task-notify/` 目录
4. 删除 `~/.claude/CLAUDE.md` 中追加的小节（若有）
5. 可选：删除临时目录 `%TEMP%\claude-code-notify\`

## 📄 许可证

MIT
