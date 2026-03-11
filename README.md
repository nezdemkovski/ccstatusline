# ccstatusline

A fast, configurable status line for [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

<!-- ![demo](.github/assets/demo.png) -->

## Features

- **Model & context** — current model name and context window usage %
- **Git** — branch name with dirty indicator
- **Session timer** — elapsed time since session start
- **Thinking mode** — shows whether extended thinking is on/off
- **Rate limits** — 5-hour and 7-day usage bars with remaining % and reset countdown
- **Extra usage** — dollars spent vs monthly limit (for subscribers with extra usage enabled)
- **Cost tracking** — session, today, yesterday, and 30-day cost + token totals via [ccusage](https://github.com/ryoppippi/ccusage) (opt-in)
- **Configurable** — toggle any section, adjust bar width, tune cache TTLs

## Performance

The statusline renders on every prompt — speed matters:

- **Single jq call** to extract all JSON fields from Claude's input
- **Precomputed bar arrays** — no string building at render time (width=10 fast path)
- **Background refresh** — API calls never block rendering; cached data shown instantly
- **Lock deduplication** — `mkdir`-based atomic locks prevent concurrent fetches
- **Grep over jq** for simple checks (thinking toggle reads settings with grep, not jq)
- **Cached OAuth token** — Keychain/credentials read once, cached for 5 minutes

## Install

```bash
npx ccstatusline
```

Restart Claude Code to activate.

## Requirements

| Dependency | Required | Install |
|------------|----------|---------|
| `jq` | Yes | `brew install jq` / `sudo apt install jq` |
| `curl` | Yes | `brew install curl` / `sudo apt install curl` |
| `git` | Yes | `brew install git` / `sudo apt install git` |
| `ccusage` | No | `npm i -g ccusage` — enables cost tracking section |

## Configuration

After install, edit `~/.claude/ccstatusline.config.json`:

```json
{
  "sections": {
    "context": true,
    "git": true,
    "session": true,
    "thinking": true,
    "rate_limits": true,
    "cost_tracking": false
  },
  "cache_ttl": {
    "usage": 60,
    "cost": 300,
    "token": 300
  }
}
```

| Key | Default | Description |
|-----|---------|-------------|
| `sections.context` | `true` | Context window usage % |
| `sections.git` | `true` | Branch name + dirty indicator |
| `sections.session` | `true` | Session elapsed time |
| `sections.thinking` | `true` | Extended thinking on/off |
| `sections.rate_limits` | `true` | 5-hour, 7-day, and extra usage bars |
| `sections.cost_tracking` | `false` | Cost/token totals (requires ccusage) |
| `cache_ttl.usage` | `60` | Seconds between rate limit API refreshes |
| `cache_ttl.cost` | `300` | Seconds between ccusage refreshes |
| `cache_ttl.token` | `300` | Seconds to cache OAuth token |

## Uninstall

```bash
npx ccstatusline --uninstall
```

Restores your previous statusline if one was backed up.

## License

MIT
