#!/usr/bin/env bash
# Pin the Haushaltsbuch module to the image built from the app repo's current
# main.
#
# The deployment intentionally references an immutable digest rather than a
# moving tag, so that Git records exactly what runs on hl01 and a revert is a
# complete rollback. This script removes the copy-and-paste step that comes
# with that, without giving up either property.
#
# It refuses to pin anything that CI has not built successfully, and it warns
# if the digest points at a multi-manifest index instead of the amd64 image —
# buildx produces one by default, and it is not what should end up here.
#
# Usage:
#   scripts/bump-haushaltsbuch.sh            # commit the bump
#   scripts/bump-haushaltsbuch.sh --push     # commit and push (GitOps deploys)
set -euo pipefail

readonly APP_REPO="ec0m3x/haushaltsbuch"
readonly PACKAGE="haushaltsbuch"
readonly IMAGE="ghcr.io/ec0m3x/haushaltsbuch"
readonly WORKFLOW="ci-image.yml"
readonly MODULE="modules/nixos/haushaltsbuch.nix"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

push=false
case "${1-}" in
  --push) push=true ;;
  "") ;;
  *)
    printf 'Unknown argument: %s\n' "$1" >&2
    exit 64
    ;;
esac

for tool in gh jq git; do
  command -v "$tool" >/dev/null || {
    printf '%s is required.\n' "$tool" >&2
    exit 69
  }
done

# A dirty module file would be swept into the bump commit.
if ! git diff --quiet -- "$MODULE" || ! git diff --cached --quiet -- "$MODULE"; then
  printf '%s has uncommitted changes; commit or stash them first.\n' "$MODULE" >&2
  exit 1
fi

printf 'Resolving current main of %s ...\n' "$APP_REPO"
head_sha="$(gh api "repos/$APP_REPO/commits/main" --jq '.sha')"
short_sha="${head_sha:0:7}"

# Pin only what CI actually built. A pending run means the image for this
# commit does not exist yet; a failed one means it must not be deployed.
run="$(
  gh run list -R "$APP_REPO" --workflow "$WORKFLOW" --branch main \
    --limit 20 --json headSha,status,conclusion \
    --jq "[.[] | select(.headSha == \"$head_sha\")] | first // empty"
)"
if [[ -z "$run" ]]; then
  printf 'No %s run found for %s. Has it been pushed?\n' "$WORKFLOW" "$short_sha" >&2
  exit 1
fi
status="$(jq -r '.status' <<<"$run")"
conclusion="$(jq -r '.conclusion // ""' <<<"$run")"
if [[ "$status" != "completed" ]]; then
  printf 'CI for %s is still %s. Wait for it to finish.\n' "$short_sha" "$status" >&2
  exit 1
fi
if [[ "$conclusion" != "success" ]]; then
  printf 'CI for %s concluded %s. Refusing to pin it.\n' "$short_sha" "$conclusion" >&2
  exit 1
fi

printf 'Looking up the image tagged %s in GHCR ...\n' "$short_sha"
digest="$(
  gh api --paginate "user/packages/container/$PACKAGE/versions" \
    --jq "[.[] | select(.metadata.container.tags // [] | index(\"$short_sha\")) | .name] | first // empty"
)"
if [[ -z "$digest" ]]; then
  printf 'No GHCR image tagged %s. Did the image job publish?\n' "$short_sha" >&2
  exit 1
fi

current="$(sed -n "s|.*$IMAGE@\(sha256:[0-9a-f]*\).*|\1|p" "$MODULE" | head -1)"
if [[ "$current" == "$digest" ]]; then
  printf 'Already pinned to %s (%s). Nothing to do.\n' "$short_sha" "$digest"
  exit 0
fi

# Best effort: a digest that resolves to an index rather than a single image
# means the workflow started attaching attestations again.
media_type="$(
  curl -fsS \
    -H "Authorization: Bearer $(printf '%s' "$(gh auth token)" | base64)" \
    -H 'Accept: application/vnd.oci.image.index.v1+json' \
    -H 'Accept: application/vnd.oci.image.manifest.v1+json' \
    -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
    "https://ghcr.io/v2/$APP_REPO/manifests/$digest" 2>/dev/null |
    jq -r '.mediaType // ""'
)" || media_type=""
case "$media_type" in
  *index*|*manifest.list*)
    printf 'Warning: %s is a manifest index, not a plain image.\n' "$digest" >&2
    printf 'Check that provenance/sbom are still disabled in %s.\n' "$WORKFLOW" >&2
    ;;
  "")
    printf 'Note: could not verify the manifest type (registry unreachable or token scope).\n' >&2
    ;;
esac

printf 'Pinning %s -> %s\n' "$short_sha" "$digest"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
# Rewrite the digest and the comment above it in one pass; sed -i is not
# portable between GNU and BSD.
awk -v image="$IMAGE" -v digest="$digest" -v tag="$short_sha" \
  -v today="$(date +%Y-%m-%d)" '
  /^  # Tag [0-9a-f]+ \(App-Repo main, / {
    printf "  # Tag %s (App-Repo main, %s).\n", tag, today
    next
  }
  /haushaltsbuchImage = / {
    printf "  haushaltsbuchImage = \"%s@%s\";\n", image, digest
    next
  }
  { print }
' "$MODULE" >"$tmp"

if ! grep -q "$digest" "$tmp"; then
  printf 'Rewrite did not take; %s may have been restructured.\n' "$MODULE" >&2
  exit 1
fi
mv "$tmp" "$MODULE"
trap - EXIT

git --no-pager diff -- "$MODULE"

git add "$MODULE"
git commit -q -m "haushaltsbuch: pin image $short_sha" \
  -m "$IMAGE@$digest" \
  -m "Built by $WORKFLOW from $APP_REPO@$head_sha."

if [[ "$push" == true ]]; then
  git push origin HEAD
  printf '\nPushed. flake-check runs first, then the GitOps controller deploys hl01.\n'
else
  printf '\nCommitted. Push to deploy:\n  git push origin main\n'
fi
