# two-claude-accounts-mac

Run **two Claude accounts at the same time on a Mac** — a personal one and a work
one — with no logging out and no conflicts. `claude-clone.sh` turns Claude Desktop
into a second, fully independent app with its own **name**, **Dock icon**,
**notifications**, and **isolated config directory**.

> 📖 Full write-up, with the reasoning and every gotcha:
> **https://melkon.tech/blog/two-claude-accounts-mac**

## The problem

Claude Desktop has no account switcher, and Claude Code (the CLI) keeps all of its
state in a single `~/.claude` directory. Switching accounts means logging out and
back in, which wipes your session. Most guides stop at a terminal alias and never
solve the desktop app.

## The fix

A macOS app is just a bundle whose identity lives in `Info.plist`. Duplicate Claude,
give the copy its own `CFBundleIdentifier` (the step most guides miss — without it
macOS merges the two apps' Dock slot and notifications), swap the icon, re-sign it
ad-hoc, and launch it pointed at its own `--user-data-dir`.

## Quick start

```bash
git clone https://github.com/MelkonTech/two-claude-accounts-mac.git
cd two-claude-accounts-mac
chmod +x claude-clone.sh

# Create a branded, isolated "Claude Work" app
./claude-clone.sh --name "Claude Work"

# ...with a custom icon
./claude-clone.sh --name "Claude Work" --icon ~/Pictures/work.icns
```

Then launch it (the script prints this for you):

```bash
open -n -a "Claude Work" --args --user-data-dir="$HOME/Library/Application Support/Claude-Work"
```

Prefer the terminal? Isolate a Claude Code account with one command:

```bash
./claude-clone.sh --cli claude-work
# opens a new shell -> run `claude-work` -> /login with the other account
```

## What it does

1. Copies `/Applications/Claude.app` to `/Applications/<name>.app`
2. Rewrites `CFBundleName`, `CFBundleDisplayName`, `CFBundleIdentifier`
3. Swaps in your `.icns` icon (optional)
4. Re-signs the bundle ad-hoc (`codesign --sign -`)
5. Refreshes the icon + Launch Services caches
6. Prints the launch command

## Options

| Flag | Description |
|------|-------------|
| `--name "Claude Work"` | Name of the new app (required) |
| `--icon path.icns` | Custom icon |
| `--data-dir PATH` | Config dir (default `~/Library/Application Support/<Name>`) |
| `--update` | Re-clone after a Claude update (the copy doesn't auto-update) |
| `--cli alias` | Add a `CLAUDE_CONFIG_DIR` shell alias instead of cloning the app |
| `--source PATH` | Source app (default `/Applications/Claude.app`) |

## Gotchas

- **Re-sign after editing** or Gatekeeper may block the app.
- **Icon in an asset catalog:** newer builds reference the icon via
  `CFBundleIconName`; the script forces a loose `.icns` and removes that key.
- **Auto-updates** only touch the original `Claude.app`. Re-run with `--update`
  after each release so the copy stays current.
- **Login routing:** Claude authenticates via `claude://` deep links; if a fresh
  login lands in the wrong window, quit the other app while you sign in.

## Notes

This edits a **copy of your own** Claude install. It does not modify the original
app and does not redistribute any Anthropic software. Personal-use convenience tool.

## License

MIT — see [LICENSE](LICENSE). Built by [Melkon Hovhannisyan](https://melkon.tech).
