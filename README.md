# Run Two Claude Accounts at the Same Time on Mac

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Run **two Claude accounts simultaneously on macOS** — personal and work — with no logging out and no conflicts. `claude-clone.sh` clones Claude Desktop into a second, fully independent app with its own **name**, **Dock icon**, **notifications**, and **isolated config directory**. Both apps run at the same time, each signed into a different Anthropic account.

> 📖 Full write-up and every gotcha explained:
> **[Two Claude Accounts on One Mac — melkon.tech](https://melkon.tech/blog/two-claude-accounts-mac)**

---

## The problem

Claude Desktop has no account switcher. Claude Code (the CLI) keeps all of its state — auth tokens, session history, memory files, MCP configs, permissions — in a single `~/.claude` directory. Switching accounts means running `/login`, which wipes the previous session. Most guides stop at an environment-variable alias and never solve the desktop app problem.

## The solution

A macOS `.app` is just a folder. Its identity lives in `Contents/Info.plist`. Duplicate Claude, give the copy a unique `CFBundleIdentifier` (the step every other guide misses — without it macOS merges both apps into one Dock slot and routes logins to whichever opened last), wrap its executable so `--user-data-dir` is injected on every open, re-sign ad-hoc, and you have two fully independent Claude installs.

---

## Requirements

- macOS 12 Monterey or later
- [Claude Desktop](https://claude.ai/download) installed at `/Applications/Claude.app`
- Xcode Command Line Tools (`xcode-select --install`) — needed for `codesign`
- Two Anthropic accounts

---

## Quick start

```bash
git clone https://github.com/MelkonTech/two-claude-accounts-mac.git
cd two-claude-accounts-mac
chmod +x claude-clone.sh

# Create a branded, isolated "Claude Work" app
./claude-clone.sh --name "Claude Work"
```

After the script finishes, open the new app from Finder, Spotlight, or the Dock — `--user-data-dir` is embedded in the launcher wrapper so you never need to pass it manually:

```bash
open "/Applications/Claude Work.app"
```

Optional: add a custom icon:

```bash
./claude-clone.sh --name "Claude Work" --icon ~/Pictures/work-icon.icns
```

Prefer the terminal only? Add a `CLAUDE_CONFIG_DIR` alias instead:

```bash
./claude-clone.sh --cli claude-work
# Open a new terminal → run `claude-work` → /login with the other account
```

---

## What the script does

1. Copies `/Applications/Claude.app` → `/Applications/<name>.app`
2. Rewrites `CFBundleName`, `CFBundleDisplayName`, `CFBundleIdentifier` in `Info.plist`
3. Swaps in your `.icns` icon (optional; handles the asset-catalog edge case)
4. **Wraps the executable** — replaces the real binary with a shell script that always passes `--user-data-dir` on launch (this is what makes Finder/Dock/Spotlight work without flags; the original binary is preserved as `<exe>.real`)
5. Re-signs the bundle ad-hoc (`codesign --force --deep --sign -`)
6. Refreshes the Launch Services and icon caches, restarts Dock and Finder

---

## Options

| Flag | Default | Description |
|------|---------|-------------|
| `--name NAME` | — | Name of the new app, e.g. `"Claude Work"` (**required**) |
| `--icon PATH` | none | Custom `.icns` icon |
| `--data-dir PATH` | `~/Library/Application Support/<Name>` | Config directory for the new app |
| `--source PATH` | `/Applications/Claude.app` | Source app to clone from |
| `--update` | off | Replace an existing copy (use after each Claude release) |
| `--no-wrap` | off | Skip the launcher wrapper; print the `open --args` command instead |
| `--cli ALIAS` | — | Add a `CLAUDE_CONFIG_DIR` shell alias only (no app cloning) |
| `--list` | — | List all cloned Claude apps in `/Applications` |
| `--remove NAME` | — | Remove a cloned app by name (prompts for confirmation) |
| `-h, --help` | — | Show usage |

---

## Shell aliases for the terminal (Claude Code)

Each alias points to a separate `CLAUDE_CONFIG_DIR` so credentials, history, and memory files stay completely separate:

```zsh
alias claude-personal='CLAUDE_CONFIG_DIR=~/.claude-personal claude'
alias claude-work='CLAUDE_CONFIG_DIR=~/.claude-work claude'
```

Add them to `~/.zshrc` (or `~/.bashrc`), then reload:

```bash
source ~/.zshrc
```

The first time you run `claude-work`, type `/login` to authenticate with the work account. After that, both aliases run in parallel in separate terminal tabs.

---

## Checking which account is active

Run `/status` inside the CLI — it shows the logged-in email and plan. Or read it directly without opening Claude:

```bash
# Personal (default)
python3 -c "import json,os; print(json.load(open(os.path.expanduser('~/.claude/.claude.json')))['oauthAccount']['emailAddress'])"

# Work alias
python3 -c "import json,os; print(json.load(open(os.path.expanduser('~/.claude-work/.claude.json')))['oauthAccount']['emailAddress'])"
```

If the config directory exists but the email is empty, that account has not run `/login` yet.

---

## Billing gotcha: ANTHROPIC_API_KEY overrides everything

`CLAUDE_CONFIG_DIR` isolates which subscription you log into. But one environment variable can silently bypass it: `ANTHROPIC_API_KEY`.

If `ANTHROPIC_API_KEY` (or `ANTHROPIC_AUTH_TOKEN`, or Bedrock/Vertex equivalents) is set in your shell, the CLI bills against that API key and ignores your subscription login entirely. You can be logged in to a Max account and still be charged per-token without noticing.

Check before you start:

```bash
echo "API key set? ${ANTHROPIC_API_KEY:+YES}"
```

If it prints `YES` and you want subscription billing, unset it for the session:

```bash
unset ANTHROPIC_API_KEY
```

Confirm the active billing mode by checking `billingType` in the config JSON. A value of `stripe_subscription` means the subscription is active.

---

## What stays separate

Each app and CLI alias keeps its own:

- Auth tokens and account session
- History and memory files
- Project notes and CLAUDE.md files
- MCP server configurations
- Claude Code permissions, tasks, and hooks

The only shared resource is the Claude Code **binary** (`~/.local/bin/claude`). Both accounts use the same version of the tool; only the data directories differ.

---

## Gotchas

**Code signing** — If the renamed app refuses to open or Gatekeeper blocks it, you either skipped or ran the `codesign` step before the wrapper was in place. Run it again after every edit to the bundle.

**Icon won't change** — Newer Electron builds reference the icon via an asset catalog (`Assets.car`) using the `CFBundleIconName` key, not a loose `.icns`. The script forces the loose-file path and deletes `CFBundleIconName`. If the icon still won't change, flush the icon cache manually:

```bash
sudo find /private/var/folders -name "com.apple.iconservices" -exec rm -rf {} + 2>/dev/null; killall Dock
```

**Auto-updates don't apply to the clone** — Claude's built-in updater only patches the original `/Applications/Claude.app`. Re-run the script with `--update` after each Claude release:

```bash
./claude-clone.sh --name "Claude Work" --update
```

**Login lands in the wrong window** — Claude authenticates via `claude://` deep links. With two instances open, macOS can route the login callback to whichever app registered last. Fix: fully quit the other Claude (`Cmd+Q`) while signing in to a fresh install.

**Wrapper and the update cycle** — `--update` removes the old app and re-copies. This destroys the wrapper. The script recreates it automatically on every run, so this is handled for you.

---

## FAQ

**Can I run more than two accounts?**
Yes — run the script again with a different `--name` for each additional account.

**Does it work on Apple Silicon (M1/M2/M3/M4)?**
Yes. Ad-hoc re-signing (`codesign --sign -`) works on both Apple Silicon and Intel.

**Will this break after a Claude Desktop update?**
The cloned app does not auto-update. Re-run `./claude-clone.sh --name "Claude Work" --update` after each Claude update.

**Is this against Anthropic's terms of service?**
This tool edits a copy of your own locally installed software. It does not modify the original app and does not redistribute any Anthropic software. It is a personal-use convenience tool.

**What about Claude Code (CLI) — does this work for the terminal too?**
Yes — use `--cli alias` to add a shell alias pointing to its own `CLAUDE_CONFIG_DIR`. Each alias gets isolated auth tokens, memory, and settings.

---

## Manual steps (without the script)

If you prefer to do it by hand, the blog post walks through every step:
<https://melkon.tech/blog/two-claude-accounts-mac>

The short version:

```bash
# 1. Copy
cp -R "/Applications/Claude.app" "/Applications/Claude Work.app"
plist="/Applications/Claude Work.app/Contents/Info.plist"

# 2. Set identity
/usr/libexec/PlistBuddy -c "Set :CFBundleName 'Claude Work'" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName 'Claude Work'" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier 'com.anthropic.claude.work'" "$plist"

# 3. Wrap executable
exe="/Applications/Claude Work.app/Contents/MacOS/Claude"
mv "$exe" "${exe}.real"
printf '%s\n' '#!/bin/bash' \
  'APP_DIR="$(cd "$(dirname "$0")" && pwd)"' \
  'exec "$APP_DIR/Claude.real" --user-data-dir="$HOME/Library/Application Support/Claude-Work" "$@"' \
  > "$exe"
chmod +x "$exe"

# 4. Sign + refresh
codesign --force --deep --sign - "/Applications/Claude Work.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "/Applications/Claude Work.app"
killall Dock Finder
```

---

## Notes

This edits a **copy** of your own Claude install. It does not modify the original app, touch Anthropic's servers, or redistribute any Anthropic software. Personal-use convenience tool.

## License

MIT — see [LICENSE](LICENSE). Built by [Melkon Hovhannisyan](https://melkon.tech).
