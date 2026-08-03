#!/usr/bin/env bash
# Ship Roobytes: bump version → CHANGELOG/About → test → commit → package → verify.
#
# Usage:
#   ./ship.sh patch|minor|major -m "changelog bullet" [-m "another"] [--skip-tests] [--no-commit]
#   ./ship.sh patch -m "$(cat <<'EOF'
#   multi-line notes become separate bullets
#   EOF
#   )"
#
# Commit subject is Conventional Commits from bump + first -m:
#   patch → fix: <first -m>
#   minor → feat: <first -m>
#   major → feat!: <first -m>
# Extra -m values become body bullets. CHANGELOG.md lists all -m bullets.
#
# Defaults: patch bump, run tests, commit all dirty files, package to /Applications.
set -euo pipefail
cd "$(dirname "$0")"

usage() {
  cat <<'EOF'
Usage: ./ship.sh <patch|minor|major> -m "changelog" [-m "..."] [--skip-tests] [--no-commit]

  patch   0.4.2 → 0.4.3  (fixes, small UX)
  minor   0.4.2 → 0.5.0  (features, architecture)
  major   0.4.2 → 1.0.0  (breaking / explicit)

  -m / --message   Changelog bullet (repeatable). Required unless --dry-run.
                   First -m becomes the Conventional Commit subject (type from bump);
                   extra -m values are commit body bullets.
  --skip-tests     Skip ./test.sh (docs/rules-only ships)
  --no-commit      Update metadata + package, but do not git commit
  --dry-run        Print planned version and commit message, then exit

Agent bump inference (when the user does not specify):
  patch  — bug fixes, polish, harness/docs with a versioned ship
  minor  — user-facing features, notable architecture
  major  — only when the user explicitly asks
EOF
}

BUMP=""
SKIP_TESTS=0
NO_COMMIT=0
DRY_RUN=0
MESSAGES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    patch|minor|major)
      BUMP="$1"
      shift
      ;;
    -m|--message)
      [[ $# -ge 2 ]] || { echo "error: $1 needs an argument" >&2; exit 1; }
      MESSAGES+=("$2")
      shift 2
      ;;
    --skip-tests)
      SKIP_TESTS=1
      shift
      ;;
    --no-commit)
      NO_COMMIT=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$BUMP" ]]; then
  echo "error: bump level required (patch|minor|major)" >&2
  usage >&2
  exit 1
fi

PLIST="Resources/Info.plist"
OLD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
OLD_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"

IFS=. read -r MAJOR MINOR PATCH <<<"$OLD_VERSION"
MAJOR="${MAJOR:-0}"
MINOR="${MINOR:-0}"
PATCH="${PATCH:-0}"

case "$BUMP" in
  patch) PATCH=$((PATCH + 1)) ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
esac

NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
NEW_BUILD=$((OLD_BUILD + 1))

# Conventional Commit: type from bump + first -m as subject.
commit_type_for_bump() {
  case "$1" in
    patch) echo "fix" ;;
    minor) echo "feat" ;;
    major) echo "feat!" ;;
    *) echo "feat" ;;
  esac
}

# Strip a leading Conventional type so agents can pass typed or bare -m.
strip_conventional_prefix() {
  local msg="$1"
  # shellcheck disable=SC2001
  sed -E 's/^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([^)]*\))?\!?:[[:space:]]*//' <<<"$msg"
}

build_commit_message() {
  local type subject
  type="$(commit_type_for_bump "$BUMP")"
  subject="$(strip_conventional_prefix "${MESSAGES[0]}")"
  local commit_msg="${type}: ${subject}"
  if [[ ${#MESSAGES[@]} -gt 1 ]]; then
    local body
    body="$(printf '%s\n' "${MESSAGES[@]:1}" | sed 's/^/- /')"
    printf '%s\n\n%s\n' "$commit_msg" "$body"
  else
    printf '%s\n' "$commit_msg"
  fi
}

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "Would ship Roobytes ${OLD_VERSION} (build ${OLD_BUILD}) → ${NEW_VERSION} (build ${NEW_BUILD}) [${BUMP}]"
  if [[ ${#MESSAGES[@]} -gt 0 ]]; then
    printf 'Changelog:\n'
    for m in "${MESSAGES[@]}"; do
      printf '  - %s\n' "$m"
    done
    printf '\nCommit message:\n'
    build_commit_message | sed 's/^/  /'
  fi
  exit 0
fi

if [[ ${#MESSAGES[@]} -eq 0 ]]; then
  echo "error: at least one -m / --message changelog bullet is required" >&2
  exit 1
fi

echo "Shipping Roobytes ${OLD_VERSION} → ${NEW_VERSION} (build ${NEW_BUILD}) [${BUMP}]"

# 1) Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${NEW_VERSION}" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${NEW_BUILD}" "$PLIST"

# 2) CHANGELOG.md section; AppDelegate About fallbacks
python3 - "$NEW_VERSION" "$NEW_BUILD" "$OLD_VERSION" "${MESSAGES[@]}" <<'PY'
import re, sys
from pathlib import Path

new_ver, new_build, old_ver = sys.argv[1], sys.argv[2], sys.argv[3]
bullets = sys.argv[4:]

root = Path(".")
changelog = root / "CHANGELOG.md"
text = changelog.read_text()

changelog_body = "\n".join(f"- {b}" for b in bullets)
section = f"## {new_ver}\n\n{changelog_body}\n\n"

# Insert after the intro, before the first ## version heading
m = re.search(r"^## \d+\.\d+\.\d+\s*$", text, flags=re.M)
if not m:
    raise SystemExit("error: no ## x.y.z section found in CHANGELOG.md")
if text[m.start():].startswith(f"## {new_ver}"):
    raise SystemExit(f"error: CHANGELOG.md already has ## {new_ver}")
text = text[: m.start()] + section + text[m.start() :]
changelog.write_text(text)

app = root / "Sources/Roobytes/AppDelegate.swift"
app_text = app.read_text()
app_text2, n1 = re.subn(
    r'(forInfoDictionaryKey: "CFBundleShortVersionString"\) as\? String \?\? )"\d+\.\d+\.\d+"',
    rf'\1"{new_ver}"',
    app_text,
    count=1,
)
app_text3, n2 = re.subn(
    r'(forInfoDictionaryKey: "CFBundleVersion"\) as\? String \?\? )"\d+"',
    rf'\1"{new_build}"',
    app_text2,
    count=1,
)
if n1 != 1 or n2 != 1:
    raise SystemExit("error: could not update AppDelegate About fallbacks")
app.write_text(app_text3)
print(f"Updated CHANGELOG.md and AppDelegate.swift for {new_ver} / build {new_build}")
PY

# 3) Tests
if [[ "$SKIP_TESTS" -eq 0 ]]; then
  echo "Running ./test.sh…"
  ./test.sh
else
  echo "Skipping tests (--skip-tests)"
fi

# 4) Commit
FULL_MSG="$(build_commit_message)"

if [[ "$NO_COMMIT" -eq 0 ]]; then
  git add -A
  if git diff --cached --quiet; then
    echo "error: nothing to commit after version bump" >&2
    exit 1
  fi
  git commit -m "$FULL_MSG"
  echo "Committed."
else
  echo "Skipping commit (--no-commit); changes left unstaged/uncommitted as-is after edits."
fi

# 5) Package
echo "Running ./package-app.sh…"
./package-app.sh

# 6) Verify
INSTALLED="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/Roobytes.app/Contents/Info.plist)"
if [[ "$INSTALLED" != "$NEW_VERSION" ]]; then
  echo "error: installed version is ${INSTALLED}, expected ${NEW_VERSION}" >&2
  exit 1
fi

echo "Shipped Roobytes ${NEW_VERSION} (build ${NEW_BUILD}) → /Applications/Roobytes.app"
