@echo off
rem =============================================================
rem notify-close-check.cmd - Claude Code close-signal hook pre-filter
rem
rem Purpose: mounted on PostToolUse / PostToolUseFailure / PermissionDenied
rem with matcher "*" (ALL tools - covers WebFetch, WebSearch, Skill,
rem Task, MCP tools, ... which the old fixed matcher list missed).
rem
rem It only spawns the PowerShell entry when a waiting popup exists
rem (waiting-*.flag). Tools completing with no popup waiting (the common
rem case) pay only a ~20-40ms cmd start, NOT a ~150-250ms PowerShell
rem cold start. The hit path (popup waiting) runs the full entry:
rem content-key + tool_use_id dual-channel close-flag writing.
rem =============================================================
if exist "%TEMP%\claude-code-notify\waiting-*.flag" (
  "%WINDIR%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%USERPROFILE%\.claude\scripts\notify-complete.ps1"
)
exit /b 0
