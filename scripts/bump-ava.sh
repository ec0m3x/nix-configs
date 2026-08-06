#!/usr/bin/env bash
# Pin the Ava module to the newest published Hermes Agent release.
#
# Ava runs third-party code on its own release cycle, so unlike the
# Haushaltsbuch there is no CI run of ours to gate on. What we can check is
# that the tag is an actual release rather than a rolling one, and that the
# index it points at carries an amd64 image — hl01 is x86_64, and an arm64-only
# index would only fail once podman tried to start the container.
#
# `latest` and `main` both track the current main build, which is exactly what
# the module comment says not to pin; they are filtered out.
#
# Release tags are dates (v2026.7.30, v2026.8.3), so they do not sort
# lexically — v2026.7.7.2 would beat v2026.7.30. The registry's own
# last_updated ordering decides instead.
#
# Usage:
#   scripts/bump-ava.sh              # commit the bump
#   scripts/bump-ava.sh --push       # commit and push (GitOps deploys)
#   scripts/bump-ava.sh --dry-run    # show what would change, write nothing
set -euo pipefail

readonly REPOSITORY="nousresearch/hermes-agent"
readonly IMAGE="docker.io/$REPOSITORY"
readonly MODULE="modules/nixos/ava.nix"
readonly RELEASES="https://github.com/NousResearch/hermes-agent/releases"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

push=false
dry_run=false
case "${1-}" in
  --push) push=true ;;
  --dry-run) dry_run=true ;;
  "") ;;
  *)
    printf 'Unknown argument: %s\n' "$1" >&2
    exit 64
    ;;
esac

for tool in curl python3 git; do
  command -v "$tool" >/dev/null || {
    printf '%s is required.\n' "$tool" >&2
    exit 69
  }
done

if [[ "$dry_run" == false ]]; then
  # A dirty module file would be swept into the bump commit.
  if ! git diff --quiet -- "$MODULE" || ! git diff --cached --quiet -- "$MODULE"; then
    printf '%s has uncommitted changes; commit or stash them first.\n' "$MODULE" >&2
    exit 1
  fi
fi

printf 'Querying Docker Hub for %s releases ...\n' "$REPOSITORY"
tags_json="$(mktemp)"
trap 'rm -f "$tags_json"' EXIT
curl -fsS \
  "https://hub.docker.com/v2/repositories/$REPOSITORY/tags?page_size=50&ordering=last_updated" \
  >"$tags_json" || {
  printf 'Could not reach the Docker Hub tag API.\n' >&2
  exit 1
}

# Emits "<tag> <digest>", or exits non-zero with a diagnostic on stderr.
read -r tag digest < <(python3 - "$tags_json" <<'PY'
import json, re, sys

with open(sys.argv[1]) as handle:
    results = json.load(handle)["results"]

# Release tags only: vYYYY.M.D[.N]. Excludes `latest` and `main`, which both
# follow the current main build.
release = re.compile(r"^v\d{4}\.\d{1,2}\.\d{1,2}(\.\d+)?$")
candidates = [t for t in results if release.match(t["name"])]
if not candidates:
    sys.exit("No release tag found in the first page of results.")

# The query is already ordered by last_updated, so the first match is newest.
newest = candidates[0]
digest = newest.get("digest") or ""
if not digest.startswith("sha256:"):
    sys.exit(f"{newest['name']} has no usable digest in the API response.")

arches = {image.get("architecture") for image in newest.get("images") or []}
if "amd64" not in arches:
    sys.exit(
        f"{newest['name']} has no amd64 image (found: {sorted(a for a in arches if a)}). "
        "hl01 is x86_64 — refusing to pin it."
    )

print(newest["name"], digest)
PY
)

current="$(sed -n "s|.*$IMAGE@\(sha256:[0-9a-f]*\).*|\1|p" "$MODULE" | head -1)"
if [[ -z "$current" ]]; then
  printf 'Could not read the current digest from %s.\n' "$MODULE" >&2
  exit 1
fi
if [[ "$current" == "$digest" ]]; then
  printf 'Already pinned to %s (%s). Nothing to do.\n' "$tag" "$digest"
  exit 0
fi

printf 'Pinning %s -> %s\n' "$tag" "$digest"

if [[ "$dry_run" == true ]]; then
  printf 'Dry run: %s would change from\n  %s\nto\n  %s\nNothing written.\n' \
    "$MODULE" "$current" "$digest"
  exit 0
fi

tmp="$(mktemp)"
# Rewrite the version comment and the digest in one pass; sed -i is not
# portable between GNU and BSD.
awk -v image="$IMAGE" -v digest="$digest" -v tag="$tag" '
  /^  # v[0-9]{4}\./ {
    printf "  # %s\n", tag
    next
  }
  /avaImage = / {
    printf "  avaImage = \"%s@%s\";\n", image, digest
    next
  }
  { print }
' "$MODULE" >"$tmp"

if ! grep -q "$digest" "$tmp" || ! grep -q "# $tag" "$tmp"; then
  rm -f "$tmp"
  printf 'Rewrite did not take; %s may have been restructured.\n' "$MODULE" >&2
  exit 1
fi
mv "$tmp" "$MODULE"

git --no-pager diff -- "$MODULE"

git add "$MODULE"
git commit -q -m "ava: pin image $tag" \
  -m "$IMAGE@$digest" \
  -m "Published upstream release, amd64 verified in the manifest index."

# The module hands the dashboard its configuration through HERMES_DASHBOARD_*
# environment variables. Upstream renaming one would not fail the build — the
# container would start and only the login would break.
printf '\nCheck the release notes before deploying, especially for renamed\n'
printf 'HERMES_DASHBOARD_* variables:\n  %s/tag/%s\n' "$RELEASES" "$tag"

if [[ "$push" == true ]]; then
  git push origin HEAD
  printf '\nPushed. flake-check runs first, then the GitOps controller deploys hl01.\n'
else
  printf '\nCommitted. Push to deploy:\n  git push origin main\n'
fi
