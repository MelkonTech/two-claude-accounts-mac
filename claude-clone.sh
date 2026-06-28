#!/usr/bin/env bash
#
# claude-clone.sh — turn Claude Desktop into two (or more) fully independent
# apps on macOS, each with its own name, Dock icon, notifications, and isolated
# config directory. Run a personal and a work account side by side, no logout.
#
# Full write-up: https://melkon.tech/blog/two-claude-accounts-mac
#
# Usage:
#   ./claude-clone.sh --name "Claude Work"
#   ./claude-clone.sh --name "Claude Work" --icon ~/Pictures/work.icns
#   ./claude-clone.sh --name "Claude Work" --update
#   ./claude-clone.sh --cli claude-work
#   ./claude-clone.sh --list
#   ./claude-clone.sh --remove "Claude Work"
#
# Options:
#   --name NAME       Name of the new app, e.g. "Claude Work"  [required]
#   --icon PATH       Custom .icns icon for the new app
#   --data-dir PATH   Config dir (default: ~/Library/Application Support/<Name>)
#   --source PATH     Source app (default: /Applications/Claude.app)
#   --update          Re-clone after a Claude update (replaces the existing copy)
#   --no-wrap         Skip wrapper executable; print open command instead
#   --cli ALIAS       Add a CLAUDE_CONFIG_DIR shell alias (no app cloning)
#   --list            List all cloned Claude apps in /Applications
#   --remove NAME     Remove a cloned app by name
#   -h, --help        Show this help
#
# It edits a COPY of your own Claude install. It does not modify the original
# app and does not redistribute any Anthropic software.
set -euo pipefail

SOURCE_APP="/Applications/Claude.app"
NAME=""
ICON=""
DATA_DIR=""
UPDATE=0
NO_WRAP=0
CLI_ALIAS=""
LIST_MODE=0
REMOVE_NAME=""

# ── helpers ───────────────────────────────────────────────────────────────────
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '  → %s\n' "$*"; }
ok()   { printf '  ✓ %s\n' "$*"; }
hr()   { printf '%s\n' "────────────────────────────────────────────────"; }

# ── arg parsing ───────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)      NAME="${2:-}";       shift 2 ;;
    --icon)      ICON="${2:-}";       shift 2 ;;
    --data-dir)  DATA_DIR="${2:-}";   shift 2 ;;
    --source)    SOURCE_APP="${2:-}"; shift 2 ;;
    --update)    UPDATE=1;            shift   ;;
    --no-wrap)   NO_WRAP=1;           shift   ;;
    --cli)       CLI_ALIAS="${2:-}";  shift 2 ;;
    --list)      LIST_MODE=1;         shift   ;;
    --remove)    REMOVE_NAME="${2:-}";shift 2 ;;
    -h|--help)
      grep '^#' "$0" | sed -n '/^# Usage/,/^# It edits/{ /^#/p }' | sed 's/^# \{0,2\}//'
      exit 0 ;;
    *) die "unknown option: $1 (run with --help)" ;;
  esac
done

# ── --list: show all cloned Claude apps ───────────────────────────────────────
if [[ $LIST_MODE -eq 1 ]]; then
  found=0
  for app in /Applications/*.app; do
    [[ -f "$app/Contents/Info.plist" ]] || continue
    bid=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
           "$app/Contents/Info.plist" 2>/dev/null || true)
    [[ "$bid" == com.anthropic.claude.* && "$bid" != "com.anthropic.claude" ]] || continue
    disp=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' \
           "$app/Contents/Info.plist" 2>/dev/null || basename "$app" .app)
    printf '  %s  [%s]\n' "$disp" "$app"
    found=1
  done
  [[ $found -eq 1 ]] || echo "No cloned Claude apps found in /Applications."
  exit 0
fi

# ── --remove: delete a cloned app by name ────────────────────────────────────
if [[ -n "$REMOVE_NAME" ]]; then
  target="/Applications/${REMOVE_NAME}.app"
  [[ -d "$target" ]] || die "app not found: $target"
  bid=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
         "$target/Contents/Info.plist" 2>/dev/null || true)
  [[ "$bid" != "com.anthropic.claude" ]] \
    || die "that looks like the original Claude.app — aborting to be safe"
  printf 'Remove "%s" (%s)? [y/N] ' "$REMOVE_NAME" "$target"
  read -r ans
  [[ "$ans" =~ ^[Yy] ]] || { echo "Cancelled."; exit 0; }
  rm -rf "$target"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -u "$target" 2>/dev/null || true
  killall Dock Finder 2>/dev/null || true
  ok "Removed $target"
  exit 0
fi

# ── --cli: add a CLAUDE_CONFIG_DIR shell alias (no app cloning) ───────────────
if [[ -n "$CLI_ALIAS" ]]; then
  rc="$HOME/.zshrc"
  [[ -n "${BASH_VERSION:-}" ]] && rc="$HOME/.bashrc"
  config_dir="\$HOME/.${CLI_ALIAS}"
  line="alias ${CLI_ALIAS}='CLAUDE_CONFIG_DIR=${config_dir} claude'"
  if grep -qF "alias ${CLI_ALIAS}=" "$rc" 2>/dev/null; then
    echo "alias '${CLI_ALIAS}' is already in $rc — no change."
  else
    printf '%s\n' "$line" >> "$rc"
    ok "Added to $rc:"
    printf '    %s\n' "$line"
  fi
  echo ""
  echo "Open a new terminal (or: source $rc), run '${CLI_ALIAS}', then /login."
  echo ""
  echo "Check which account is active:"
  echo "  python3 -c \"import json,os; print(json.load(open(os.path.expanduser('~/.${CLI_ALIAS}/.claude.json')))['oauthAccount']['emailAddress'])\" 2>/dev/null || echo 'not logged in yet'"
  exit 0
fi

# ── validate ──────────────────────────────────────────────────────────────────
[[ -n "$NAME" ]] || die "--name is required (e.g. --name \"Claude Work\")"
[[ -d "$SOURCE_APP" ]] || die "source app not found: $SOURCE_APP (use --source PATH)"

TARGET_APP="/Applications/${NAME}.app"
: "${DATA_DIR:=$HOME/Library/Application Support/${NAME}}"
PLIST="$TARGET_APP/Contents/Info.plist"
BUNDLE_ID="com.anthropic.claude.$(echo "$NAME" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-')"

hr
echo ""
echo "  Creating: $TARGET_APP"
echo "  Config:   $DATA_DIR"
echo "  Bundle:   $BUNDLE_ID"
echo ""

# ── 1. Duplicate (or refresh) the app bundle ──────────────────────────────────
if [[ $UPDATE -eq 1 && -d "$TARGET_APP" ]]; then
  info "Update mode: removing old copy"
  rm -rf "$TARGET_APP"
elif [[ -d "$TARGET_APP" ]]; then
  die "$TARGET_APP already exists — pass --update to replace it"
fi
info "Copying $SOURCE_APP"
cp -R "$SOURCE_APP" "$TARGET_APP"
ok "Copied"

# ── 2. Give the copy its own identity (CFBundleIdentifier is the key step) ───
# Without a unique CFBundleIdentifier, macOS merges both apps into one Dock slot
# and routes notifications to whichever opened last.
info "Setting bundle identity"
/usr/libexec/PlistBuddy -c "Set :CFBundleName '$NAME'" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName '$NAME'" "$PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string '$NAME'" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier '$BUNDLE_ID'" "$PLIST"
ok "Identity set (name=\"$NAME\", id=$BUNDLE_ID)"

# ── 3. Optional custom icon ───────────────────────────────────────────────────
if [[ -n "$ICON" ]]; then
  [[ -f "$ICON" ]] || die "icon not found: $ICON"
  icon_key=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$PLIST" 2>/dev/null \
             || echo "AppIcon")
  icon_key="${icon_key%.icns}"
  cp "$ICON" "$TARGET_APP/Contents/Resources/${icon_key}.icns"
  # Newer Electron builds reference icons via an asset catalog (CFBundleIconName).
  # Force the loose .icns so our replacement is actually used.
  /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile '${icon_key}'" "$PLIST" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "$PLIST" 2>/dev/null || true
  ok "Icon set from $(basename "$ICON")"
fi

# ── 4. Wrapper executable ─────────────────────────────────────────────────────
# This is what makes normal Finder / Dock / Spotlight opens work without flags.
# The wrapper replaces the real binary with a one-line shell script that always
# forwards launches to the original binary with --user-data-dir pre-set.
# Re-signing (step 5) MUST happen after this edit.
EXE_NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST")
EXE_PATH="$TARGET_APP/Contents/MacOS/$EXE_NAME"
REAL_PATH="${EXE_PATH}.real"

if [[ $NO_WRAP -eq 0 ]]; then
  info "Wrapping launcher (so Finder/Dock/Spotlight auto-apply --user-data-dir)"
  mv "$EXE_PATH" "$REAL_PATH"
  printf '%s\n' \
    '#!/bin/bash' \
    'APP_DIR="$(cd "$(dirname "$0")" && pwd)"' \
    "exec \"\$APP_DIR/${EXE_NAME}.real\" --user-data-dir=\"$DATA_DIR\" \"\$@\"" \
    > "$EXE_PATH"
  chmod +x "$EXE_PATH"
  ok "Wrapper created → config dir embedded"
fi

# ── 5. Re-sign ad-hoc (must run after ALL bundle edits, including wrapper) ───
# Sign INSIDE-OUT, deepest nested code first, the outer .app last. Apple has
# deprecated `codesign --deep` for signing — it silently mis-orders or skips
# nested helpers, leaving Anthropic's Developer-ID + hardened-runtime signature
# on a helper under an ad-hoc parent. That mismatch is what produces the
# "broken code signature / unable to find helper app (Electron FATAL)" crash.
# Signing each component explicitly, innermost first, avoids it entirely.
info "Re-signing ad-hoc (inside-out)"
# 5a. nested frameworks
while IFS= read -r -d '' fw; do
  codesign --force --sign - "$fw" 2>/dev/null || true
done < <(find "$TARGET_APP/Contents/Frameworks" -name "*.framework" -type d -print0 2>/dev/null)
# 5b. nested helper .app bundles (Claude Helper.app, (GPU), (Renderer), (Plugin))
while IFS= read -r -d '' h; do
  codesign --force --sign - "$h" 2>/dev/null || true
done < <(find "$TARGET_APP/Contents/Frameworks" -name "*.app" -type d -print0 2>/dev/null)
# 5c. loose Mach-O helpers and the renamed real launcher binary
for extra in "$TARGET_APP/Contents/Helpers/"* "$REAL_PATH"; do
  [[ -f "$extra" ]] && codesign --force --sign - "$extra" 2>/dev/null || true
done
# 5d. the outer app bundle LAST, so its seal covers the freshly signed insides
codesign --force --sign - "$TARGET_APP"
# 5e. fail loudly if the result still won't verify (catches future bundle changes)
if ! codesign --verify --deep --strict "$TARGET_APP" 2>/dev/null; then
  die "re-sign failed strict verification — the app would crash on launch. \
Quit any running copy of \"$NAME\" and re-run."
fi
ok "Signed (inside-out) and verified"

# ── 6. Refresh caches ─────────────────────────────────────────────────────────
info "Refreshing Launch Services and icon caches"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$TARGET_APP" 2>/dev/null || true
killall Dock Finder 2>/dev/null || true
ok "Caches refreshed"

# ── 7. Done ───────────────────────────────────────────────────────────────────
hr
echo ""
if [[ $NO_WRAP -eq 0 ]]; then
  echo "  Done. Open from Finder, Spotlight, or the Dock, or run:"
  echo ""
  echo "    open \"/Applications/${NAME}.app\""
else
  echo "  Done. Launch with:"
  echo ""
  echo "    open -n -a \"$NAME\" --args --user-data-dir=\"$DATA_DIR\""
fi
echo ""
echo "  Config dir: $DATA_DIR"
echo "  First launch: run /login inside Claude Code, or sign in via the app."
echo ""
echo "  Heads up:"
echo "    • Re-run with --update after each Claude release to keep the copy current."
echo "    • If a fresh login routes to the wrong window, fully quit the other Claude first."
echo ""
