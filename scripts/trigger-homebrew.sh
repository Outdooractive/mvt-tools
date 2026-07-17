#!/bin/sh
#
# Trigger the "Homebrew" GitHub Actions workflow to build, upload, and bump
# the Homebrew formula for the `mvt` command line tool.
#
# Usage:
#   scripts/trigger-homebrew.sh [tag]
#
# Without an argument the most recent tag reachable from the local `main`
# branch is used. The workflow always checks out the tag from the default
# branch (`main`) on GitHub, so the tag must exist on `main`.
#
# Requires:
#   - `gh` (GitHub CLI), authenticated with a token that has `Actions: Write`
#     on the Outdooractive/mvt-tools repository.
#

set -eu

REPOSITORY="Outdooractive/mvt-tools"
WORKFLOW="homebrew.yml"
MAIN_BRANCH="main"

if ! command -v gh >/dev/null 2>&1
then
    echo "Error: 'gh' (GitHub CLI) is required. Install it from https://cli.github.com/"
    exit 1
fi

if ! gh auth status >/dev/null 2>&1
then
    echo "Error: not authenticated with 'gh'. Run 'gh auth login' first."
    exit 1
fi

if [ "$#" -gt 1 ]
then
    echo "Usage: $0 [tag]"
    exit 1
fi

TAG_NAME="${1:-}"

if [ -z "$TAG_NAME" ]
then
    echo "No tag given, determining the most recent tag from '$MAIN_BRANCH'..."

    if ! git rev-parse --verify "origin/$MAIN_BRANCH" >/dev/null 2>&1
    then
        echo "Error: could not find 'origin/$MAIN_BRANCH'. Run 'git fetch origin' first."
        exit 1
    fi

    TAG_NAME=$(git tag --merged "origin/$MAIN_BRANCH" --sort=-creatordate | head -n 1)

    if [ -z "$TAG_NAME" ]
    then
        echo "Error: no tags found on '$MAIN_BRANCH'."
        exit 1
    fi

    echo "Using latest tag: $TAG_NAME"
fi

if ! git rev-parse --verify "refs/tags/$TAG_NAME" >/dev/null 2>&1
then
    echo "Error: tag '$TAG_NAME' does not exist locally."
    echo "Run 'git fetch --tags' to update, or pass an existing tag as argument."
    exit 1
fi

TAG_BRANCH=$(git branch -r --contains "refs/tags/$TAG_NAME" | grep -E "^[[:space:]]*origin/$MAIN_BRANCH\$" || true)

if [ -z "$TAG_BRANCH" ]
then
    echo "Error: tag '$TAG_NAME' is not reachable from 'origin/$MAIN_BRANCH'."
    echo "The workflow always deploys from '$MAIN_BRANCH'. Create the tag on '$MAIN_BRANCH' first."
    exit 1
fi

echo "Triggering workflow '$WORKFLOW' on '$REPOSITORY' with tag_name=$TAG_NAME..."

gh workflow run "$WORKFLOW" \
    --repo "$REPOSITORY" \
    --ref "$MAIN_BRANCH" \
    --raw-field "tag_name=$TAG_NAME"

echo "Workflow triggered. View progress at:"
echo "  https://github.com/$REPOSITORY/actions/workflows/$WORKFLOW"