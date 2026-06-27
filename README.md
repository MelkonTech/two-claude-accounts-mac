# Run Two Claude Accounts at the Same Time on Mac

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Run **two Claude accounts simultaneously on macOS** — personal and work — with no logging out and no conflicts. `claude-clone.sh` clones Claude Desktop into a second, fully independent app with its own **name**, **Dock icon**, **notifications**, and **isolated config directory**. Both apps run at the same time, each logged into a different Anthropic account.

> 📖 Full write-up and every gotcha explained:
> **[Two Claude Accounts on One Mac — melkon.tech](https://melkon.tech/blog/two-claude-accounts-mac)**

---

## The problem

Claude Desktop has no account switcher. Claude Code (the CLI) stores all state in a single `~/.claude` directory. Switching accounts means logging out and back in — which wipes your session. Most guides stop at a terminal alias and never solve the desktop app.

## The solution

A macOS app is just a bundle whose identity lives in `Info.plist`. Duplicate Claude, give the copy its own `CFBundleIdentifier` (the step most guides miss — without it macOS merges both apps into one Dock slot and notification stream), swap the icon, re-sign it ad-hoc, and wrap the executable so every normal Finder/Dock launch uses its own `--user-data-dir`. The original Claude app is untouched throughout.

---

## Requirements

- macOS 12 Monterey or later
- [Claude Desktop](https://claude.ai/download) installed at `/Applications/Claude.app`
- Xcode Command Line Tools (`xcode-select --install`) — for `codesign`
- Two Anthropic accounts

---

## Quick start

```bash
git clone https://github.com/MelkonTech/two-claude-accounts-mac.git
cd two-claude-accounts-mac
chmod +x claude-clone.sh

# Create a branded, isolated "Claude Work" app
./claude-clone.sh --name "Claude Work"

# With a custom icon
./claude-clone.sh --name "Claude Work" --icon ~/Pictures/work.icns
```

Then open it like any normal Mac app — Finder, Spotlight, the Dock, or:

```bash
open "/Applications/Claude Work.app"
```

### Isolate a Claude Code (CLI) account

No app cloning needed for the terminal. One command adds a shell alias:

```bash
./claude-clone.sh --cli claude-work
# Open a new terminal → run `claude-work` → /login with the other account
```

---

## What the script does

1. Copies `/Applications/Claude.app` → `/Applications/<name>.app`
2. Rewrites `CFBundleName`, `CFBundleDisplayName`, `CFBundleIdentifier` in `Info.plist`
3. Swaps in your `.icns` icon (optional)
4. Wraps the executable so Finder/Dock launches always pass `--user-data-dir`
5. Re-signs the bundle ad-hoc (`codesign --sign -`)
6. Refreshes the icon cache and Launch Services database
7. Prints the `open` command to launch your new app

---

## Options

| Flag | Description |
|------|-------------|
| `--name "Claude Work"` | Name of the cloned app (required for app mode) |
| `--icon path.icns` | Custom `.icns` icon |
| `--data-dir PATH` | Config dir (default: `~/Library/Application Support/<Name>`) |
| `--update` | Re-clone after a Claude update — the copy does not auto-update |
| `--cli alias` | Add a `CLAUDE_CONFIG_DIR` shell alias instead of cloning the app |
| `--source PATH` | Source app path (default: `/Applications/Claude.app`) |

---

## Gotchas

- **Re-sign after any manual edits** or Gatekeeper may block the app.
- **Icon in an asset catalog:** newer Claude builds reference the icon via `CFBundleIconName`; the script forces a loose `.icns` and removes that key so the swap works.
- **Auto-updates only touch the original** `Claude.app`. Re-run with `--update` after each Claude Desktop release to keep the copy current.
- **Login routing:** Claude authenticates via `claude://` deep links. If a fresh login opens in the wrong window, quit the other app (Cmd+Q) while you sign in.

---

## FAQ

**Does this work with Claude Code (the CLI)?**
Yes — use `--cli alias` to create an isolated shell alias. Each alias gets its own `CLAUDE_CONFIG_DIR` so projects, auth tokens, and settings never mix.

**Will this break after a Claude Desktop update?**
The cloned app does not auto-update. Re-run `./claude-clone.sh --name "Claude Work" --update` after each Claude update to keep the copy in sync.

**Is this against Anthropic's terms?**
This tool edits a copy of your own locally installed software. It does not modify the original app and does not redistribute any Anthropic software. It is a personal-use convenience tool.

**Can I run more than two accounts?**
Yes — run the script again with a different `--name` for each additional account.

**Does it work on Apple Silicon (M1/M2/M3/M4)?**
Yes. The ad-hoc re-signing (`codesign --sign -`) works on both Apple Silicon and Intel.

---

## Notes

This edits a **copy of your own** Claude install. The original `/Applications/Claude.app` is never modified. No Anthropic software is redistributed.

## License

MIT — see [LICENSE](LICENSE). Built by [Melkon Hovhannisyan](https://melkon.tech).
