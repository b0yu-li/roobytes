#!/bin/bash
# If there are uncommitted Swift/plist changes, nudge the agent to ship.
cd "$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0

# Local harness may install a weekday commit guard (symlinked + excluded).
# Don't nag to ship when that guard would refuse the commit.
guard=".cursor/hooks/block-weekday-work-commits.sh"
if [ -e "$guard" ] && ! "$guard" git >/dev/null 2>&1; then
  echo '{}'
  exit 0
fi

changed=$(git status --porcelain -- '*.swift' 'Resources/Info.plist' 2>/dev/null | head -1)
if [ -n "$changed" ]; then
  cat <<'EOF'
{
  "followup_message": "There are uncommitted Swift changes. Run ./ship.sh patch -m \"<changelog>\" to bump, test, commit, and install to /Applications/Roobytes.app."
}
EOF
else
  echo '{}'
fi
