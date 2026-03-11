#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const os = require("os");
const { execSync } = require("child_process");

const MARKER = "# ccstatusline";
const HOME = os.homedir();
const CLAUDE_DIR = path.join(HOME, ".claude");
const STATUSLINE_PATH = path.join(CLAUDE_DIR, "statusline.sh");
const BACKUP_PATH = path.join(CLAUDE_DIR, "statusline.sh.backup");
const SETTINGS_PATH = path.join(CLAUDE_DIR, "settings.json");
const CONFIG_PATH = path.join(CLAUDE_DIR, "ccstatusline.config.json");
const TMPDIR = "/tmp/claude";

const STATUSLINE_COMMAND = 'bash "$HOME/.claude/statusline.sh"';

// ── Colors ──────────────────────────────────────────────
const c = {
  reset: "\x1b[0m",
  bold: "\x1b[1m",
  dim: "\x1b[2m",
  green: "\x1b[32m",
  yellow: "\x1b[33m",
  red: "\x1b[31m",
  cyan: "\x1b[36m",
  blue: "\x1b[34m",
  magenta: "\x1b[35m",
};

const log = (msg) => console.log(msg);
const ok = (msg) => log(`  ${c.green}✓${c.reset} ${msg}`);
const warn = (msg) => log(`  ${c.yellow}!${c.reset} ${msg}`);
const err = (msg) => log(`  ${c.red}✗${c.reset} ${msg}`);
const info = (msg) => log(`  ${c.dim}→${c.reset} ${msg}`);

// ── Helpers ─────────────────────────────────────────────
function commandExists(cmd) {
  try {
    execSync(`command -v ${cmd}`, { stdio: "ignore" });
    return true;
  } catch {
    return false;
  }
}

function isMacOS() {
  return os.platform() === "darwin";
}

function readJSON(filepath) {
  try {
    return JSON.parse(fs.readFileSync(filepath, "utf8"));
  } catch {
    return null;
  }
}

function writeJSON(filepath, data) {
  fs.writeFileSync(filepath, JSON.stringify(data, null, 2) + "\n", "utf8");
}

function isOurScript(filepath) {
  try {
    const content = fs.readFileSync(filepath, "utf8");
    return content.includes(MARKER);
  } catch {
    return false;
  }
}

// ── Default config ──────────────────────────────────────
const DEFAULT_CONFIG = {
  sections: {
    context: true,
    git: true,
    session: true,
    thinking: true,
    rate_limits: true,
    cost_tracking: false,
  },
  cache_ttl: {
    usage: 60,
    cost: 300,
    token: 300,
  },
};

// ── Install ─────────────────────────────────────────────
function install() {
  log("");
  log(
    `  ${c.bold}${c.blue}ccstatusline${c.reset} ${c.dim}— installing...${c.reset}`
  );
  log("");

  // 1. Check dependencies
  const deps = [
    { cmd: "jq", required: true, desc: "JSON processor" },
    { cmd: "curl", required: true, desc: "HTTP client" },
    { cmd: "git", required: true, desc: "version control" },
    { cmd: "ccusage", required: false, desc: "cost tracking (optional)" },
  ];

  let missing = false;
  for (const dep of deps) {
    if (commandExists(dep.cmd)) {
      ok(`${dep.cmd} ${c.dim}— ${dep.desc}${c.reset}`);
    } else if (dep.required) {
      err(
        `${dep.cmd} ${c.dim}— ${dep.desc}${c.reset} ${c.red}(required)${c.reset}`
      );
      if (isMacOS()) {
        info(`Install: ${c.cyan}brew install ${dep.cmd}${c.reset}`);
      } else {
        info(`Install: ${c.cyan}sudo apt install ${dep.cmd}${c.reset}`);
      }
      missing = true;
    } else {
      warn(
        `${dep.cmd} ${c.dim}— ${dep.desc}${c.reset}`
      );
      info(
        `Enables cost tracking. Install: ${c.cyan}npm i -g ccusage${c.reset}`
      );
    }
  }

  if (missing) {
    log("");
    err("Missing required dependencies. Install them and retry.");
    process.exit(1);
  }

  log("");

  // 2. Create ~/.claude/ if missing
  if (!fs.existsSync(CLAUDE_DIR)) {
    fs.mkdirSync(CLAUDE_DIR, { recursive: true });
    ok("Created ~/.claude/");
  }

  // 3. Backup existing statusline if it isn't ours
  if (fs.existsSync(STATUSLINE_PATH)) {
    if (isOurScript(STATUSLINE_PATH)) {
      info("Existing ccstatusline detected — overwriting");
    } else {
      fs.copyFileSync(STATUSLINE_PATH, BACKUP_PATH);
      ok(`Backed up existing statusline to ${c.dim}statusline.sh.backup${c.reset}`);
    }
  }

  // 4. Copy statusline.sh
  const srcScript = path.join(__dirname, "statusline.sh");
  fs.copyFileSync(srcScript, STATUSLINE_PATH);
  fs.chmodSync(STATUSLINE_PATH, 0o755);
  ok("Installed statusline.sh");

  // 5. Update settings.json
  let settings = readJSON(SETTINGS_PATH) || {};
  settings.statusLine = {
    type: "command",
    command: STATUSLINE_COMMAND,
  };
  writeJSON(SETTINGS_PATH, settings);
  ok("Updated settings.json");

  // 6. Write default config if missing
  if (!fs.existsSync(CONFIG_PATH)) {
    writeJSON(CONFIG_PATH, DEFAULT_CONFIG);
    ok("Created ccstatusline.config.json");
  } else {
    info("Config file already exists — keeping current settings");
  }

  log("");
  log(
    `  ${c.green}${c.bold}Done!${c.reset} Restart Claude Code to activate.`
  );
  log(
    `  ${c.dim}Config: ~/.claude/ccstatusline.config.json${c.reset}`
  );
  log("");
}

// ── Uninstall ───────────────────────────────────────────
function uninstall() {
  log("");
  log(
    `  ${c.bold}${c.blue}ccstatusline${c.reset} ${c.dim}— uninstalling...${c.reset}`
  );
  log("");

  // 1. Remove statusline.sh
  if (fs.existsSync(STATUSLINE_PATH)) {
    fs.unlinkSync(STATUSLINE_PATH);
    ok("Removed statusline.sh");
  }

  // 2. Restore backup or clean settings
  if (fs.existsSync(BACKUP_PATH)) {
    fs.renameSync(BACKUP_PATH, STATUSLINE_PATH);
    ok("Restored previous statusline from backup");
  } else {
    // Remove statusLine from settings.json
    if (fs.existsSync(SETTINGS_PATH)) {
      const settings = readJSON(SETTINGS_PATH);
      if (settings && settings.statusLine) {
        delete settings.statusLine;
        writeJSON(SETTINGS_PATH, settings);
        ok("Removed statusLine from settings.json");
      }
    }
  }

  // 3. Remove config
  if (fs.existsSync(CONFIG_PATH)) {
    fs.unlinkSync(CONFIG_PATH);
    ok("Removed ccstatusline.config.json");
  }

  // 4. Clean cache files
  const cachePatterns = [
    "statusline-usage-cache.json",
    "statusline-cost-cache.json",
    "statusline-token.cache",
    "session-start",
  ];
  const lockPatterns = ["usage-refresh.lock", "cost-refresh.lock"];

  for (const file of cachePatterns) {
    const fp = path.join(TMPDIR, file);
    try {
      fs.unlinkSync(fp);
    } catch {}
  }
  for (const dir of lockPatterns) {
    const dp = path.join(TMPDIR, dir);
    try {
      fs.rmSync(dp, { recursive: true });
    } catch {}
  }
  ok("Cleaned cache files");

  log("");
  log(
    `  ${c.green}${c.bold}Done!${c.reset} Restart Claude Code to deactivate.`
  );
  log("");
}

// ── Main ────────────────────────────────────────────────
const args = process.argv.slice(2);

if (args.includes("--uninstall") || args.includes("-u")) {
  uninstall();
} else if (args.includes("--help") || args.includes("-h")) {
  log("");
  log(`  ${c.bold}ccstatusline${c.reset} — status line for Claude Code`);
  log("");
  log(`  ${c.bold}Usage:${c.reset}`);
  log(`    npx ccstatusline            Install / update`);
  log(`    npx ccstatusline --uninstall Remove completely`);
  log("");
  log(`  ${c.dim}https://github.com/nezdemkovski/ccstatusline${c.reset}`);
  log("");
} else {
  install();
}
