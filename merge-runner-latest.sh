#!/usr/bin/env bash
set -euo pipefail

# Merge latest v* tag from remote 'upstream' (actions/runner) into current branch.
# Adapted from https://github.com/lekoOwO/yolo-runner
#
# Last known good commits (for manual revert):
#   origin  (jk89/runner):    36a3ab8315c85f23a1e606cb311227f053520a6e
#   upstream (actions/runner): 4a587ada27a33b7b2efc15c6acf7963eb2ed2706
#
# Conflict resolution rules:
# - Always preserve local README*.md files (keep ours)
# - Always preserve local .github/workflows/ (keep ours)
# - Always preserve ContainerOperationProvider.cs (keep ours, the yolo patch)
# - Always preserve .gitignore (keep ours)
# - Preserve files that exist locally but not in upstream (local-only files)
# - For other conflicted files, accept upstream (theirs)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Usage: $0 [--push [remote [branch]]] [--dry-run]
  --push : push after successful merge. Optionally provide remote and branch.
  --dry-run : show what would happen without committing.
EOF
}

DRY_RUN=0
PUSH=0
PUSH_REMOTE=origin
PUSH_BRANCH=HEAD

forced_local=()
accepted_remote=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --push) PUSH=1; shift; if [ "$#" -gt 0 ] && [[ "$1" != --* ]]; then PUSH_REMOTE="$1"; shift; fi; if [ "$#" -gt 0 ] && [[ "$1" != --* ]]; then PUSH_BRANCH="$1"; shift; fi ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1"; usage; exit 2 ;;
  esac
done

echo "Fetching from upstream..."
git fetch upstream --tags

echo "Fetching from origin..."
git fetch origin --tags

LATEST_TAG=$(git ls-remote --tags --refs upstream 'v*' | awk '{print $2}' | sed 's#refs/tags/##' | sort -V | tail -n1 || true)

if [ -z "$LATEST_TAG" ]; then
  echo "No upstream tag starting with 'v' found" >&2
  exit 3
fi

NEW_VERSION="${LATEST_TAG#v}"
LATEST_TAG_COMMIT=$(git rev-parse "${LATEST_TAG}^{commit}" 2>/dev/null)

if [ -z "$LATEST_TAG_COMMIT" ]; then
  echo "Could not resolve commit for tag $LATEST_TAG" >&2
  exit 3
fi

# Check if this tag is already merged
if git merge-base --is-ancestor "$LATEST_TAG_COMMIT" HEAD 2>/dev/null; then
  echo "Tag $LATEST_TAG ($LATEST_TAG_COMMIT) is already merged. Nothing to do."
  exit 2
fi

LAST_COMMIT_FILE="$SCRIPT_DIR/last-upstream-commit"
if [ -f "$LAST_COMMIT_FILE" ]; then
  LAST_UPSTREAM=$(tr -d '[:space:]' < "$LAST_COMMIT_FILE")
  echo "Last merged upstream commit: $LAST_UPSTREAM"
fi

echo "Latest upstream tag: $LATEST_TAG (commit: $LATEST_TAG_COMMIT)"
echo "Current releaseVersion: $(cat "$SCRIPT_DIR/releaseVersion" 2>/dev/null || echo 'none')"

# Determine yolo N from both local and remote tags before merging
HIGHEST_N=0
for n in $(git tag -l "${NEW_VERSION}-yolo-*" 2>/dev/null | sed "s/${NEW_VERSION}-yolo-//"); do
  if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -gt "$HIGHEST_N" ]; then
    HIGHEST_N=$n
  fi
done
for n in $(git ls-remote --tags --refs origin "${NEW_VERSION}-yolo-*" 2>/dev/null | sed "s/.*${NEW_VERSION}-yolo-//"); do
  if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -gt "$HIGHEST_N" ]; then
    HIGHEST_N=$n
  fi
done

YOLO_N=$((HIGHEST_N + 1))
YOLO_VERSION="${NEW_VERSION}-yolo-${YOLO_N}"

# Validate tag does not already exist
if git rev-parse "refs/tags/${YOLO_VERSION}" >/dev/null 2>&1; then
  echo "ERROR: Tag ${YOLO_VERSION} already exists locally. Aborting." >&2
  exit 1
fi
if git ls-remote --tags --refs origin "${YOLO_VERSION}" | grep -q .; then
  echo "ERROR: Tag ${YOLO_VERSION} already exists on origin. Aborting." >&2
  exit 1
fi

echo "Will create version: ${YOLO_VERSION}"

if [ $DRY_RUN -eq 1 ]; then
  echo "Dry-run: would merge $LATEST_TAG and create tag $YOLO_VERSION"
  exit 0
fi

echo "Attempting merge (no commit) of $LATEST_TAG..."
set +e
if git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
  echo "Detected an existing in-progress merge (MERGE_HEAD present)."
  unmerged=$(git diff --name-only --diff-filter=U || true)
  if [ -z "$unmerged" ]; then
    echo "No unmerged files found, treating as merged (will finalize below)."
    MERGE_RC=0
  else
    echo "Unmerged files present; will run conflict resolution."
    MERGE_RC=1
  fi
else
  git merge --no-commit --no-ff "$LATEST_TAG"
  MERGE_RC=$?
fi
set -e

if [ $MERGE_RC -eq 0 ]; then
  echo "Merged cleanly."
  git commit -m "Merge upstream $LATEST_TAG"
else
  echo "Merge produced conflicts; resolving per rules..."

  TMP_UPSTREAM_FILES=$(mktemp)
  git ls-tree -r --name-only "$LATEST_TAG" > "$TMP_UPSTREAM_FILES"

  conflicted_files=$(git diff --name-only --diff-filter=U || true)

  forced_local=()
  accepted_remote=()

  for f in $conflicted_files; do
    case "$f" in
      README.md|README-sysbox.md|RUNNER.README.md)
        echo "Preserving local: $f"
        git checkout --ours -- "$f"
        git add "$f"
        forced_local+=("$f")
        continue
        ;;
    esac

    case "$f" in
      .github/workflows/*)
        echo "Preserving local workflow: $f"
        if git ls-tree -r --name-only HEAD | grep -Fxq -- "$f"; then
          git checkout --ours -- "$f" || true
          git add "$f" || true
        else
          git rm -f -- "$f" || true
        fi
        forced_local+=("$f")
        continue
        ;;
    esac

    case "$f" in
      src/Runner.Worker/ContainerOperationProvider.cs|.gitignore)
        echo "Preserving local (fork-specific): $f"
        git checkout --ours -- "$f"
        git add "$f"
        forced_local+=("$f")
        continue
        ;;
    esac

    if ! grep -Fxq -- "$f" "$TMP_UPSTREAM_FILES"; then
      echo "Preserving local-only file: $f"
      git checkout --ours -- "$f"
      git add "$f"
      forced_local+=("$f")
      continue
    fi

    echo "Accepting upstream version for: $f"
    git checkout --theirs -- "$f"
    git add "$f"
    accepted_remote+=("$f")
  done

  rm -f "$TMP_UPSTREAM_FILES"

  git commit -m "Merge upstream $LATEST_TAG, resolve conflicts: preserve local README/workflows/yolo-patch/local-only files"
fi

# Update tracking files
echo "$NEW_VERSION" > "$SCRIPT_DIR/releaseVersion"

MERGED_UPSTREAM_COMMIT=$(git merge-base HEAD upstream/main)
echo "$MERGED_UPSTREAM_COMMIT" > "$LAST_COMMIT_FILE"

echo "$YOLO_VERSION" > "$SCRIPT_DIR/yoloVersion"

git add releaseVersion last-upstream-commit yoloVersion
git commit -m "Bump version to ${YOLO_VERSION}"
git tag "${YOLO_VERSION}"
echo "Created tag: ${YOLO_VERSION}"

echo
echo "=== Merge Summary ==="
echo "Merged tag: $LATEST_TAG"
echo "Upstream commit: $MERGED_UPSTREAM_COMMIT"
echo "New version: ${YOLO_VERSION}"
echo "Commit: $(git --no-pager log -1 --pretty=format:'%h %s')"
echo
if [ "${#forced_local[@]}" -gt 0 ]; then
  echo "Files preserved from local (ours):"
  for p in "${forced_local[@]}"; do echo "  - $p"; done
else
  echo "No files forced to local."
fi

if [ "${#accepted_remote[@]}" -gt 0 ]; then
  echo "Files accepted from upstream (theirs):"
  for p in "${accepted_remote[@]}"; do echo "  - $p"; done
else
  echo "No conflicted files accepted from upstream."
fi

echo
echo "Git status:"; git status --porcelain

if [ $PUSH -eq 1 ]; then
  echo "Pushing to $PUSH_REMOTE $PUSH_BRANCH..."
  git push "$PUSH_REMOTE" "$PUSH_BRANCH"
  git push "$PUSH_REMOTE" "${YOLO_VERSION}"
fi

exit 0
