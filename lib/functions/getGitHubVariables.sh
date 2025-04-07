#!/usr/bin/env bash

GetGitHubVars() {
  info "--------------------------------------------"
  info "Gathering GitHub information..."

  local GITHUB_REPOSITORY_DEFAULT_BRANCH
  GITHUB_REPOSITORY_DEFAULT_BRANCH="master"

  if [[ ${RUN_LOCAL} != "false" ]]; then
    info "RUN_LOCAL has been set to: ${RUN_LOCAL}. Bypassing GitHub Actions variables..."

    if [ -z "${GITHUB_WORKSPACE:-}" ]; then
      GITHUB_WORKSPACE="${DEFAULT_WORKSPACE}"
    fi

    ValidateGitHubWorkspace "${GITHUB_WORKSPACE}"

    pushd "${GITHUB_WORKSPACE}" >/dev/null || exit 1

    if [[ "${USE_FIND_ALGORITHM}" == "false" ]]; then
      ConfigureGitSafeDirectories
      debug "Initializing GITHUB_SHA considering ${GITHUB_WORKSPACE}"
      GITHUB_SHA=$(git -C "${GITHUB_WORKSPACE}" rev-parse HEAD)
      local RET_CODE=$?
      if [[ "${RET_CODE}" -gt 0 ]]; then
        fatal "Failed to initialize GITHUB_SHA. Output: ${GITHUB_SHA}"
      fi
      info "Initialized GITHUB_SHA to: ${GITHUB_SHA}"

      if ! InitializeRootCommitSha; then
        fatal "Failed to initialize root commit"
      fi
    else
      debug "Skip the initalization of GITHUB_SHA because we don't need it"
    fi

    MULTI_STATUS="false"
    debug "Setting MULTI_STATUS to ${MULTI_STATUS} because we are not running on GitHub Actions"
  else
    ValidateGitHubWorkspace "${GITHUB_WORKSPACE}"

    # Ensure that Git can access the local repository
    ConfigureGitSafeDirectories

    if [ -z "${GITHUB_EVENT_PATH:-}" ]; then
      fatal "Failed to get GITHUB_EVENT_PATH: ${GITHUB_EVENT_PATH}]"
    else
      info "Successfully found GITHUB_EVENT_PATH: ${GITHUB_EVENT_PATH}]"
    fi

    if [[ ! -e "${GITHUB_EVENT_PATH}" ]]; then
      fatal "${GITHUB_EVENT_PATH} doesn't exist or it's not readable"
    else
      debug "${GITHUB_EVENT_PATH} exists and it's readable"
      debug "${GITHUB_EVENT_PATH} contents:\n$(cat "${GITHUB_EVENT_PATH}")"
    fi

    if [ -z "${GITHUB_SHA:-}" ]; then
      fatal "Failed to get GITHUB_SHA: ${GITHUB_SHA}"
    else
      info "Successfully found GITHUB_SHA: ${GITHUB_SHA}"
    fi

    if ! InitializeRootCommitSha; then
      fatal "Failed to initialize root commit"
    fi

    debug "This is a ${GITHUB_EVENT_NAME} event"

    if [ "${GITHUB_EVENT_NAME}" == "pull_request" ]; then
      # GITHUB_SHA on PR events is not the latest commit.
      # https://docs.github.com/en/actions/reference/events-that-trigger-workflows#pull_request
      # "Note that GITHUB_SHA for this [pull_request] event is the last merge commit of the pull request merge branch.
      # If you want to get the commit ID for the last commit to the head branch of the pull request,
      # use github.event.pull_request.head.sha instead."
      debug "Updating the current GITHUB_SHA (${GITHUB_SHA}) to the pull request HEAD SHA"

      GITHUB_SHA="$(GetPullRequestHeadSha "${GITHUB_EVENT_PATH}")"
      local RET_CODE=$?
      if [[ "${RET_CODE}" -gt 0 ]]; then
        fatal "Failed to get the root commit: ${GIT_ROOT_COMMIT_SHA}"
      fi
      debug "Updated GITHUB_SHA: ${GITHUB_SHA}"

      GITHUB_EVENT_COMMIT_COUNT=$(GetGithubPullRequestEventCommitCount "${GITHUB_EVENT_PATH}")
      RET_CODE=$?
      if [[ "${RET_CODE}" -gt 0 ]]; then
        fatal "Failed to get GITHUB_EVENT_COMMIT_COUNT. Output: ${GITHUB_EVENT_COMMIT_COUNT}"
      else
        debug "Successfully found commit count for ${GITHUB_EVENT_NAME} event: ${GITHUB_EVENT_COMMIT_COUNT}"
      fi
    elif [ "${GITHUB_EVENT_NAME}" == "push" ]; then
      GITHUB_EVENT_COMMIT_COUNT=$(GetGithubPushEventCommitCount "${GITHUB_EVENT_PATH}")
      RET_CODE=$?
      if [[ "${RET_CODE}" -gt 0 ]]; then
        fatal "Failed to get GITHUB_EVENT_COMMIT_COUNT. Output: ${GITHUB_EVENT_COMMIT_COUNT}"
      fi
      debug "Successfully found commit count for ${GITHUB_EVENT_NAME} event: ${GITHUB_EVENT_COMMIT_COUNT}"
    fi

    InitializeAndValidateGitBeforeShaReference "${GITHUB_SHA}" "${GITHUB_EVENT_COMMIT_COUNT}" "${GIT_ROOT_COMMIT_SHA}"

    GITHUB_REPOSITORY_DEFAULT_BRANCH=$(GetGithubRepositoryDefaultBranch "${GITHUB_EVENT_PATH}")
    local RET_CODE=$?
    if [[ "${RET_CODE}" -gt 0 ]]; then
      fatal "Failed to get GITHUB_REPOSITORY_DEFAULT_BRANCH. Output: ${GITHUB_REPOSITORY_DEFAULT_BRANCH}"
    fi
  fi

  if [ -z "${GITHUB_REPOSITORY_DEFAULT_BRANCH}" ]; then
    fatal "Failed to get GITHUB_REPOSITORY_DEFAULT_BRANCH"
  else
    debug "Successfully detected the default branch for this repository: ${GITHUB_REPOSITORY_DEFAULT_BRANCH}"
  fi

  DEFAULT_BRANCH="${DEFAULT_BRANCH:-${GITHUB_REPOSITORY_DEFAULT_BRANCH}}"

  if [[ "${DEFAULT_BRANCH}" != "${GITHUB_REPOSITORY_DEFAULT_BRANCH}" ]]; then
    debug "The default branch for this repository was set to ${GITHUB_REPOSITORY_DEFAULT_BRANCH}, but it was explicitly overridden using the DEFAULT_BRANCH variable, and set to: ${DEFAULT_BRANCH}"
  fi
  info "The default branch for this repository is set to: ${DEFAULT_BRANCH}"

  if [ "${MULTI_STATUS}" == "true" ]; then

    if [[ ${RUN_LOCAL} == "true" ]]; then
      # Safety check. This shouldn't occur because we forcefully set MULTI_STATUS=false above
      # when RUN_LOCAL=true
      fatal "Cannot enable status reports when running locally."
    fi

    if [ -z "${GITHUB_TOKEN:-}" ]; then
      fatal "Failed to get [GITHUB_TOKEN]. Terminating because status reports were explicitly enabled, but GITHUB_TOKEN was not provided."
    else
      info "Successfully found GITHUB_TOKEN."
    fi

    if [ -z "${GITHUB_REPOSITORY:-}" ]; then
      error "Failed to get [GITHUB_REPOSITORY]!"
      fatal "[${GITHUB_REPOSITORY}]"
    else
      info "Successfully found GITHUB_REPOSITORY: ${GITHUB_REPOSITORY}"
    fi

    if [ -z "${GITHUB_RUN_ID:-}" ]; then
      error "Failed to get [GITHUB_RUN_ID]!"
      fatal "[${GITHUB_RUN_ID}]"
    else
      info "Successfully found GITHUB_RUN_ID ${GITHUB_RUN_ID}"
    fi

    GITHUB_STATUS_URL="${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/statuses/${GITHUB_SHA}"
    debug "GitHub Status URL: ${GITHUB_STATUS_URL}"

    GITHUB_STATUS_TARGET_URL="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
    debug "GitHub Status target URL: ${GITHUB_STATUS_TARGET_URL}"
  else
    debug "Skip GITHUB_TOKEN, GITHUB_REPOSITORY, and GITHUB_RUN_ID validation because we don't need these variables for GitHub Actions status reports. MULTI_STATUS: ${MULTI_STATUS}"
  fi

  # We need this for parallel
  export GITHUB_WORKSPACE
}
