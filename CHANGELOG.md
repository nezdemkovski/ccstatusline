# Changelog

## 1.0.0 (2026-03-11)

Initial release.

- Real-time context window, git branch, session timer, and thinking mode display
- 5-hour and 7-day rate limit bars with remaining % and reset countdown
- Extra usage tracking (dollars spent / monthly limit)
- Optional cost tracking via [ccusage](https://github.com/ryoppippi/ccusage) (session, today, yesterday, 30-day)
- Background refresh with lock deduplication — no render blocking
- Cached OAuth token retrieval (Keychain + credentials file)
- Configurable sections, bar width, and cache TTLs via `~/.claude/ccstatusline.config.json`
- One-command install (`npx ccstatusline`) and uninstall (`npx ccstatusline --uninstall`)
- Idempotent installs with automatic backup of existing statusline scripts
