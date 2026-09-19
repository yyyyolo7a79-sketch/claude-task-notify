<div align="center">

**Language / 语言 / 語言 / 言語 / 언어**

[**English**](../../README.md) | [简体中文](../../README.zh-CN.md) | [繁體中文](../zh-TW/README.md) | [日本語](../ja-JP/README.md) | [한국어](README.md)

</div>

---

# Claude Code 작업 완료 알림 (claude-task-notify)

> Windows용 Claude Code를 위한 ChatGPT 스타일 데스크톱 카드 — ✅ 작업 완료 / ❓ 사용자 입력 대기 / ⏳ 답변 또는 승인 대기. 대기형 팝업은 계속 표시되며 **답변하거나 승인하는 순간 자동으로 닫힙니다**. 순수 시스템 PowerShell + WPF, **서드파티 의존성 없음**.
>
> 📄 이 파일은 간략 번역판입니다. 전체 내용은 [English README](../../README.md)를 참고하세요.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](../../LICENSE)
![Windows](https://img.shields.io/badge/Windows-10%2F11-0078D4?logo=windows&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1-5391FE?logo=powershell&logoColor=white)
![Claude Code](https://img.shields.io/badge/Claude%20Code-v2.x-D97757?logo=claude&logoColor=white)
[![Stars](https://img.shields.io/github/stars/yyyyolo7a79-sketch/claude-task-notify?style=flat)](https://github.com/yyyyolo7a79-sketch/claude-task-notify/stargazers)
[![Downloads](https://img.shields.io/github/downloads/yyyyolo7a79-sketch/claude-task-notify/total?style=flat)](https://github.com/yyyyolo7a79-sketch/claude-task-notify/releases)

---

## ✨ 기능

- **항상 실행** — Claude Code hook(harness 계층, `~/.claude/settings.json`에 설정)으로 트리거됩니다. Claude가 응답을 멈출 때마다 팝업이 뜨며, 모델의 협조가 필요 없습니다.
- **스마트 판별** — 답변이 물음표로 끝나거나 요청 표현("~을 제공해 주세요")을 포함하면 → **❓ 사용자 입력 대기**, 그 외 → **✅ 작업 완료**(8초 후 자동 사라짐).
- **답변 요약** — 카드 본문에 답변의 첫 문단(180자로 자르고 코드 블록/HTML/엔티티/URL 제거)을 표시합니다. 터미널로 돌아가지 않아도 내용을 알 수 있습니다.
- **프로젝트 이름** — 제목 옆에 현재 프로젝트 디렉터리 이름을 표시하여 여러 프로젝트를 한눈에 구분합니다.
- **대기 알림** — Claude가 **질문**(AskUserQuestion)하거나 **권한 확인**을 요청하면 "❓ 답변 대기 중" / "⏳ 승인 대기 중" 카드가 표시됩니다(질문/명령 요약 포함). 다른 창에서 코딩 중이어도 대기 상태를 놓치지 않습니다.
- **영구 표시 · 답변 시 자동 닫힘** — 대기형 카드는 계속 표시되며 ①답변/승인(**자동 닫힘**) ②✕ 수동 닫기 ③30분 안전 타임아웃 중 하나로 끝납니다. `/notify_AskUserQuestion_persistence false`로 8초 자동 닫기로 되돌릴 수 있습니다.
- **자동 닫힘 신호 채널** — **모든 도구**의 PostToolUse / PostToolUseFailure / PermissionDenied를 감시합니다(WebFetch, WebSearch, Skill, MCP 도구 등 권한 프롬프트를 낼 수 있는 모든 도구). 경량 사전 필터 `notify-close-check.cmd` 경유: **대기 중인 팝업이 없으면 약 +30ms 만에 즉시 종료**(PowerShell을 실행하지 않음), 대기 중일 때만 전체 파이프라인(약 0.2초). 매칭은 이중 채널(도구 호출 ID + 도구 인자의 내용 지문 — 권한 요청 이벤트는 설계상 `tool_use_id`가 없음). 팝업이 살아 있는 동안에만 `waiting-*` 핸드셰이크 파일을 만들므로 대기자가 없으면 신호 파일이 전혀 생기지 않습니다.
- **중복 제거 및 노이즈 필터** — 같은 세션에서 2초 이내 중복 이벤트는 한 번만 표시. AskUserQuestion 자체의 권한 노이즈는 건너뜁니다.
- **모든 프로젝트에 적용** — 사용자 수준 `~/.claude/settings.json`에 설정됩니다.
- **의존성 제로** — 시스템 내장 PowerShell 5.1 + WPF(DirectWrite 렌더링, 브라우저와 동일하게 선명).
- **포커스를 뺏지 않음** — `ShowActivated=false` + `WS_EX_NOACTIVATE`.
- **논블로킹** — hook 진입점은 500ms 이내에 반환되고 UI는 독립 프로세스에서 실행됩니다.
- **프라이버시 배려** — `%TEMP%\claude-code-notify\notify.log`(200KB 롤링)에 시각/세션 앞 8자/결과만 기록하며 전문은 남기지 않습니다.

### 미리보기

```
┌────────────────────────────────┐
│ ✅  작업 완료                    │
│ 모든 변경 사항 적용 완료.        │
│ 파일 3개 수정, 테스트 통과.      │
└────────────────────────────────┘
   ↑ 우측 하단 · 흰 카드 · 페이드 인/아웃
     8초 후 자동 사라짐 · 클릭/✕ 로 닫기
```

## 🔧 작동 원리

```
Claude Code 이벤트 (~/.claude/settings.json 전역 설정, timeout 5s)
        │  stdin JSON
        ├─ Stop (메인 답변 종료) ──────────────┐
        ├─ PreToolUse(AskUserQuestion) (질문, 답변 대기) ─┤
        ├─ PermissionRequest (권한 확인, 승인 대기) ──────┤
        └─ PostToolUse / PostToolUseFailure / PermissionDenied (모든 도구)
           → notify-close-check.cmd 사전 필터 (waiting 없으면 즉시 종료)
           → waiting 있을 때만 PS를 실행해 닫힘 플래그 기록 → exit ─┘
        ▼
notify-complete.ps1 (진입점, 500ms 이내 반환)
        │  ① 이벤트 유형 필터 (AskUserQuestion 자체의 권한 노이즈 건너뜀)
        │  ② 로컬 요약 (코드 블록/HTML/엔티티/URL → 첫 180자)
        │  ③ 중복 제거: SHA-256(session+내용), 2초 윈도
        │  ④ 임시 payload (persist/toolUseId/contentKey) 작성 → 독립 UI 프로세스 생성
        ▼
show-popup.ps1 (독립 프로세스, -STA)
        │  payload 읽고 삭제 → waiting 핸드셰이크 기록 → WPF(DirectWrite) 렌더링
        ▼
우측 하단 비모달 카드: 포커스 안 뺏음 · 둥근 모서리+그림자 · 클릭/✕ 로 닫기
  · Stop: 8초 후 자동 페이드아웃
  · 대기형(질문/권한 확인): 답변/승인 시 자동 닫힘(이중 채널 신호) · 수동 ✕ · 30분 안전 타임아웃
```

## 🚀 빠른 시작

> 요구 환경: Windows 10/11 · Claude Code v2.x · PowerShell 5.1(시스템 내장)

### Claude Code로 설치 (권장)

아래 문장을 이 저장소 링크와 함께 Claude Code에 붙여넣으면 설치와 자가 테스트를 자동으로 수행합니다:

> 저장소 `https://github.com/yyyyolo7a79-sketch/claude-task-notify`를 전역 설정(Windows)에 설치해 주세요:
> 1. `scripts\`의 `notify-complete.ps1`, `show-popup.ps1`, `notify-close-check.cmd`를 `~\.claude\scripts\`로 복사
> 2. `~\.claude\settings.json` 최상위에 hook 추가(기존 항목은 유지·추가, 덮어쓰기 금지): `Stop`(matcher 비움) · `PreToolUse`(matcher `AskUserQuestion`) · `PermissionRequest`(matcher 비움) · `PostToolUse` / `PostToolUseFailure` / `PermissionDenied`(matcher `*` 모든 도구). 팝업형 command는 절대 인터프리터 경로 + `-WindowStyle Hidden`, 닫힘 신호형 command는 사전 필터(`"\"C:\Users\<사용자 이름>\.claude\scripts\notify-close-check.cmd\""`) 지정. `"timeout": 5`
> 3. `skills\claude-task-notify\`를 `~\.claude\skills\`로, `commands\notify_AskUserQuestion_persistence.md`를 `~\.claude\commands\`로 복사
> 4. `~\.claude\CLAUDE.md` 끝에 "작업 완료 알림" 섹션 추가
> 5. 자가 테스트(먼저 `$OutputEncoding = [Text.Encoding]::UTF8` 설정): `$OutputEncoding = [Text.Encoding]::UTF8; $evt = @{session_id="test"; cwd=(Get-Location).Path; hook_event_name="Stop"; stop_hook_active=$false; last_assistant_message="팝업이 정상적으로 작동합니다"} | ConvertTo-Json; $evt | & "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "$HOME\.claude\scripts\notify-complete.ps1"`

### 수동 설치

**1단계** — 스크립트 복사:

```powershell
# 3개 파일을 사용자 수준 스크립트 디렉터리로
Copy-Item scripts\notify-complete.ps1 "$HOME\.claude\scripts\"
Copy-Item scripts\show-popup.ps1 "$HOME\.claude\scripts\"
Copy-Item scripts\notify-close-check.cmd "$HOME\.claude\scripts\"
```

**2단계** — 전역 hook 설정. `~/.claude/settings.json`을 편집하여 최상위에 `hooks` 키 추가(기존 설정 유지):

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

> `<CMD>` = `"\"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe\" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"C:\\Users\\<사용자 이름>\\.claude\\scripts\\notify-complete.ps1\""`. `PostToolUse` 등에 기존 항목이 있으면 **추가**하세요.
>
> 💡 `<CMD2>` = `"\"C:\\Users\\<사용자 이름>\\.claude\\scripts\\notify-close-check.cmd\""`는 "대기 팝업 자동 닫힘" 신호 채널(matcher `*`)입니다: **대기 없으면 도구 완료마다 약 +30ms**(사전 필터가 즉시 종료, PowerShell 미실행), 대기 중엔 약 +0.2초. 이 세 항목을 삭제하면 수동 닫기 / 30분 안전 타임아웃으로 격하됩니다.

> ⚠️ `<사용자 이름>`을 실제 경로로 바꾸세요. 재시작 불필요 — 다음 작업부터 적용됩니다.
>
> 💡 인터프리터는 반드시 절대 경로 + `-WindowStyle Hidden`으로: PATH의 `powershell`은 하이재킹될 수 있고, `Hidden`이 없으면 Stop마다 콘솔 창이 번쩍입니다.

**3단계**(선택) — 행동 규범 skill:

```powershell
Copy-Item skills\claude-task-notify "$HOME\.claude\skills\" -Recurse
```

**4단계**(선택) — `~/.claude/CLAUDE.md` 끝에 선언 추가.

### 테스트

```powershell
# 진입점 직접 테스트 (stdin에 Stop 이벤트 JSON을 넣으면 카드가 떠야 합니다)
# ⚠️ PS 5.1의 $OutputEncoding은 기본 ASCII — UTF-8을 설정하지 않으면 파이프 경유 비ASCII가 "?"로 강등됩니다
$OutputEncoding = [Text.Encoding]::UTF8
$evt = @{ session_id="test"; cwd=(Get-Location).Path; hook_event_name="Stop";
          stop_hook_active=$false; last_assistant_message="팝업이 정상적으로 작동합니다" } | ConvertTo-Json
$evt | & "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "$HOME\.claude\scripts\notify-complete.ps1"
```

결과는 로그 `%TEMP%\claude-code-notify\notify.log`에서 확인(`OK` = 알림 완료, `DEDUPE` = 중복 제거, `SKIP` = 필터됨).

## ⚙️ 설정

브라우저에서 `弹窗参数调整器.html`을 열고 슬라이더를 드래그해 실시간 미리보기. 조정 후 생성된 파라미터 코드를 `show-popup.ps1` 상단 상수 블록에 붙여넣으세요.

| 파라미터 | 기본값 | 설명 |
|---|---|---|
| `$W` / `$H` | 400 / 200 | 카드 너비 / 높이 (px, 100% DPI 기준, 시스템 배율 자동 반영) |
| `$PAD_X` / `$PAD_TOP` | 20 / 15 | 제목 좌 / 상 여백 |
| `$BODY_TOP` / `$BODY_H` | 52 / 80 | 본문 상단 오프셋 / 본문 영역 높이 |
| `$F_TITLE` / `$F_BODY` | 12 / 10 (스크립트 내 `* 1.3333`) | 제목 / 본문 글꼴 크기 (pt; WPF는 DIP px, pt→px ×4/3) |
| `$MAX_CHARS` | 180 | 요약 자르기 길이 — `notify-complete.ps1` 상단 |
| `$MARGIN` | 20 | 화면 우측 하단 여백 |
| `$PERSIST_MAX_MS` | 30분 | 영구 팝업 안전 타임아웃 — `show-popup.ps1` 상단 |

영구화 전환: `/notify_AskUserQuestion_persistence true|false` (기본 `true` = 대기형 영구 표시; `false` = 8초 후 사라짐).

## ❓ FAQ

| 증상 | 해결 |
|---|---|
| 팝업이 안 뜸 | 로그 `%TEMP%\claude-code-notify\notify.log` 확인: `SKIP` = 필터됨, `DEDUPE` = 2초 내 중복, `ERR` = 입력 또는 생성 실패 |
| 글자 깨짐 | 두 `.ps1`은 반드시 **UTF-8 with BOM**(PS 5.1은 BOM 없는 UTF-8을 ANSI로 읽음). 저장소 파일은 BOM 포함. 편집했다면 UTF-8 with BOM으로 다시 저장하세요 |
| 글자가 흐림 | WPF(DirectWrite) 렌더링으로 브라우저와 동일하게 선명합니다. 그래도 흐리면 디스플레이 배율 설정을 확인하세요 |
| 시스템 알림과 이중 표시 | `/config`에서 Claude Code 내장 알림 끄기 |
| 카드 내용이 잘림 | 조정 도구로 `$BODY_H` / `$H`를 키우거나 글꼴 크기를 줄이세요 |
| 대기 팝업이 안 사라짐 | 영구 모드의 설계입니다 — ✕로 닫거나, 답변하면 자동으로 닫힙니다(30분 안전 타임아웃). `/notify_AskUserQuestion_persistence false`로 8초로 되돌릴 수 있습니다 |
| 권한 팝업이 승인 후 자동으로 안 닫힘 | 수정됨(2세대 문제: ① 권한 요청 이벤트에 ID 없음 → 내용 지문 채널; ② 고정 matcher 목록이 WebFetch/Skill 등을 누락 → 전 도구 + cmd 사전 필터). 극히 드물게 도구가 거부되고 후속 이벤트가 없을 때만 수동 ✕ / 30분 안전 타임아웃으로 격하 |
| 테스트에서 간헐적 `ERR invalid-json` | PS 5.1 파이프의 간헐적 문제(테스트 경로만; 실제 hook은 Node가 UTF-8 stdin을 쓰므로 영향 없음) — 다시 실행하세요 |
| 질문 시 카드가 2장 뜸 | 구버전 알려진 문제(AskUserQuestion 권한 노이즈) — `notify-complete.ps1`을 최신 버전으로 업데이트하세요 |

## 📝 변경 이력

### 2026-09-19 — 전 도구 닫힘 신호 커버리지

- 근본 원인: 닫힘 신호 hook이 고정 matcher 목록(`Bash|Edit|Write|MultiEdit|NotebookEdit`)을 사용 — 목록 밖 도구(WebFetch, Skill, MCP 등)의 권한 팝업은 "도구 완료" 신호를 영원히 받지 못해 계속 남아 있었음.
- 수정: 세 닫힘 신호 이벤트의 matcher를 `*` 전 도구로 변경 + `notify-close-check.cmd` 사전 필터 추가(대기 없으면 약 30ms 즉시 종료, PowerShell 미실행).

### 2026-09-18 — 대기 팝업 자동 닫힘 수정

- 근본 원인: 권한 요청 이벤트(PermissionRequest)는 설계상 **`tool_use_id`가 없음** — 권한 팝업이 닫힘 신호와 매칭될 수 없었음.
- 수정: 이중 채널 신호(호출 ID + 내용 지문 `SHA256(tool_name+tool_input)[:16]`), `waiting-*` 핸드셰이크 파일(대기자 없으면 파일도 없음), `PermissionDenied` 이벤트 추가.

### 2026-09-17 — 첫 버전: 대기 알림과 영구 팝업

- 버그 4건 수정(중복 제거 타임존, 30 DIP 위치 어긋남, 질문 시 이중 카드, 문서/파이프).
- 신규: 질문/권한 확인 시 ❓/⏳ 대기 알림, 기본 영구 + 답변 시 자동 닫힘, `/notify_AskUserQuestion_persistence` 명령.

> 📖 전체 이력(초기 개발 단계 포함)은 [English README](../../README.md#-changelog)를 참고하세요.

## 📄 라이선스 및 크레딧

MIT — [LICENSE](../../LICENSE) 참조.

UI 영감은 ChatGPT 데스크톱 앱과 Codex의 작업 완료 토스트에서: 비모달, 포커스 미탈취, 우측 하단, 자동 사라짐.
