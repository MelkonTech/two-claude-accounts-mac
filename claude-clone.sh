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
#   ./claude-clone.sh --name "Claude Work" --data-dir "$HOME/Library/Application Support/Claude-Work"
#   ./claude-clone.sh --name "Claude Work" --update     # re-clone after a Claude update
#   ./claude-clone.sh --cli claude-work                 # add a CLI alias instead
#
# It edits a COPY of your own Claude install. It never modifies or redistributes
# the original app.
set -euo pipefail

SOURCE_APP="/Applications/Claude.app"
NAME=""
ICON=""
DATA_DIR=""
UPDATE=0
CLI_ALIAS=""

die() { echo "error: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)     NAME="${2:-}"; shift 2 ;;
    --icon)     ICON="${2:-}"; shift 2 ;;
    --data-dir) DATA_DIR="${2:-}"; shift 2 ;;
    --update)   UPDATE=1; shift ;;
    --cli)      CLI_ALIAS="${2:-}"; shift 2 ;;
    --source)   SOURCE_APP="${2:-}"; shift 2 ;;
    -h|--help)  grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)          die "unknown option: $1" ;;
  esac
done

# --- CLI alias mode: isolate a Claude Code terminal account, no app cloning ---
if [[ -n "$CLI_ALIAS" ]]; then
  rc="$HOME/.zshrc"; [[ -n "${BASH_VERSION:-}" ]] && rc="$HOME/.bashrc"
  line="alias ${CLI_ALIAS}='CLAUDE_CONFIG_DIR=\$HOME/.${CLI_ALIAS} claude'"
  if grep -qF "alias ${CLI_ALIAS}=" "$rc" 2>/dev/null; then
    echo "alias ${CLI_ALIAS} already present in $rc"
  else
    echo "$line" >> "$rc"
    echo "added to $rc:"; echo "  $line"
  fi
  echo "Open a new terminal, run '${CLI_ALIAS}', then /login with the other account."
  exit 0
fi

[[ -n "$NAME" ]] || die "--name is required (e.g. --name \"Claude Work\")"
[[ -d "$SOURCE_APP" ]] || die "source app not found at $SOURCE_APP (pass --source)"

TARGET_APP="/Applications/${NAME}.app"
: "${DATA_DIR:=$HOME/Library/Application Support/${NAME// /-}}"
PLIST="$TARGET_APP/Contents/Info.plist"
BUNDLE_ID="com.anthropic.claude.$(echo "$NAME" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-')"

# --- 1. Duplicate (or refresh) the app bundle -------------------------------
if [[ $UPDATE -eq 1 && -d "$TARGET_APP" ]]; then
  echo "Updating: re-cloning $SOURCE_APP -> $TARGET_APP"
  rm -rf "$TARGET_APP"
fi
[[ -d "$TARGET_APP" ]] && die "$TARGET_APP already exists (use --update to refresh)"
echo "Cloning $SOURCE_APP -> $TARGET_APP"
cp -R "$SOURCE_APP" "$TARGET_APP"

# --- 2. Give the copy its own identity (the key step) -----------------------
echo "Setting identity: name=\"$NAME\" id=$BUNDLE_ID"
/usr/libexec/PlistBuddy -c "Set :CFBundleName '$NAME'" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName '$NAME'" "$PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string '$NAME'" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier '$BUNDLE_ID'" "$PLIST"

# --- 3. Optional custom icon ------------------------------------------------
if [[ -n "$ICON" ]]; then
  [[ -f "$ICON" ]] || die "icon not found: $ICON"
  icon_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$PLIST" 2>/dev/null || echo AppIcon)"
  icon_name="${icon_name%.icns}"
  cp "$ICON" "$TARGET_APP/Contents/Resources/${icon_name}.icns"
  # Some builds reference the icon from an asset catalog; force the loose file.
  /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile '${icon_name}'" "$PLIST" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "$PLIST" 2>/dev/null || true
  echo "Icon set from $ICON"
fi

# --- 4. Re-sign ad-hoc (editing the bundle invalidated the signature) -------
echo "Re-signing (ad-hoc)"
codesign --force --deep --sign - "$TARGET_APP"

# --- 5. Refresh icon + Launch Services caches -------------------------------
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$TARGET_APP" || true
killall Dock Finder 2>/dev/null || true

# --- 6. Launch it at its own data directory ---------------------------------
echo ""
echo "Done. Launch your second Claude with:"
echo "  open -n -a \"$NAME\" --args --user-data-dir=\"$DATA_DIR\""
echo ""
echo "Tip: if a fresh login lands in the wrong window, fully quit the other"
echo "Claude (Cmd+Q) while you sign in. Re-run with --update after each Claude update."
