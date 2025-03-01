#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=/dev/null
source "test/testUtils.sh"

# shellcheck source=/dev/null
source "lib/functions/validation.sh"
# shellcheck source=/dev/null
source "lib/functions/gitCommands.sh"
# shellcheck source=/dev/null
source "lib/functions/githubEvent.sh"

# shellcheck source=/dev/null
source "lib/functions/getGitHubVariables.sh"

function InitGitRepository() {
  local REPOSITORY_PATH="${1}"
  initialize_git_repository "${REPOSITORY_PATH}"

  touch "${REPOSITORY_PATH}/test-initial-commit.txt"
  git -C "${REPOSITORY_PATH}" add .
  git -C "${REPOSITORY_PATH}" commit --allow-empty -m "Initial commit"
  INITIAL_SHA=$(git -C "${GITHUB_WORKSPACE}" rev-parse HEAD)
}

function InitTestEnv() {
  GITHUB_WORKSPACE="$(mktemp -d)"
  export DEFAULT_SUPER_LINTER_WORKSPACE="/tmp/lint"
  export DEFAULT_WORKSPACE="${GITHUB_WORKSPACE}"

  InitGitRepository "${GITHUB_WORKSPACE}"
}

function SetGitHubShaToPrHeadSha() {
  local FUNCTION_NAME
  FUNCTION_NAME="${FUNCNAME[0]}"
  info "${FUNCTION_NAME} start"

  # Given super-linter not run locally
  export RUN_LOCAL="false"
  export MULTI_STATUS="true"

  # And super-linter triggered by pull_request
  # Mock out GITHUB_EVENT_PATH with a crafted pull_request event payload
  export GITHUB_EVENT_PATH="test/data/github-event/github-event-pull_request.json"
  export GITHUB_EVENT_NAME="pull_request"

  # Mock out variables not essential to this test case
  export GITHUB_TOKEN="xxx"
  export GITHUB_REPOSITORY="xxx"
  export GITHUB_RUN_ID="xxx"
  export GITHUB_API_URL="xxx"
  export GITHUB_SERVER_URL="xxx"

  # When GitHub variables are collected
  GITHUB_SHA="${INITIAL_SHA}"
  GetGitHubVars

  # Then set GITHUB_SHA to PR head SHA
  # Expected SHA can be found
  #   - "test/data/github-event/github-event-pull_request.json" : .pull_request.head.sha
  if [ "$GITHUB_SHA" != "857bb4758bcb283d3b1a9ce986c7fb43b5b4f108" ]; then
    fatal "GITHUB_SHA not set to .pull_request.head.sha"
  fi

  notice "${FUNCTION_NAME} PASS"
}

InitTestEnv

# Test cases
SetGitHubShaToPrHeadSha
