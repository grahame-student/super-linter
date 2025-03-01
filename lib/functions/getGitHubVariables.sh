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
      if ! GITHUB_SHA=$(git -C "${GITHUB_WORKSPACE}" rev-parse HEAD); then
        fatal "Failed to initialize GITHUB_SHA. Output: ${GITHUB_SHA}"
      fi
      debug "GITHUB_SHA: ${GITHUB_SHA}"
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
      debug "${GITHUB_EVENT_PATH} contents:\n$(cat "${GITHUB_EVENT_PATH}")"
    fi

    if [ -z "${GITHUB_SHA:-}" ]; then
      fatal "Failed to get GITHUB_SHA: ${GITHUB_SHA}"
    else
      info "Successfully found GITHUB_SHA: ${GITHUB_SHA}"
    fi

    if ! GIT_ROOT_COMMIT_SHA="$(git -C "${GITHUB_WORKSPACE}" rev-list --max-parents=0 "${GITHUB_SHA}")"; then
      fatal "Failed to get the root commit: ${GIT_ROOT_COMMIT_SHA}"
    else
      debug "Successfully found the root commit: ${GIT_ROOT_COMMIT_SHA}"
    fi
    export GIT_ROOT_COMMIT_SHA

    ##################################################
    # Need to pull the GitHub Vars from the env file #
    ##################################################

    GITHUB_ORG=$(jq -r '.repository.owner.login' <"${GITHUB_EVENT_PATH}")

    # Github sha on PR events is not the latest commit.
    # https://docs.github.com/en/actions/reference/events-that-trigger-workflows#pull_request
    if [ "$GITHUB_EVENT_NAME" == "pull_request" ]; then
      debug "This is a GitHub pull request. Updating the current GITHUB_SHA (${GITHUB_SHA}) to the pull request HEAD SHA"

      if ! GITHUB_SHA=$(jq -r .pull_request.head.sha <"$GITHUB_EVENT_PATH"); then
        fatal "Failed to update GITHUB_SHA for pull request event: ${GITHUB_SHA}"
      fi
      debug "Updated GITHUB_SHA: ${GITHUB_SHA}"
    elif [ "${GITHUB_EVENT_NAME}" == "push" ]; then
      debug "This is a GitHub push event."

      if [[ "${GITHUB_SHA}" == "${GIT_ROOT_COMMIT_SHA}" ]]; then
        debug "${GITHUB_SHA} is the initial commit. Skip initializing GITHUB_BEFORE_SHA because there no commit before the initial commit"
      else
        debug "${GITHUB_SHA} is not the initial commit"
        local -i GITHUB_PUSH_COMMIT_COUNT
        GITHUB_PUSH_COMMIT_COUNT=$(GetGithubPushEventCommitCount "$GITHUB_EVENT_PATH")
        if [ -z "${GITHUB_PUSH_COMMIT_COUNT}" ]; then
          fatal "Failed to get GITHUB_PUSH_COMMIT_COUNT"
        fi
        info "Successfully found GITHUB_PUSH_COMMIT_COUNT: ${GITHUB_PUSH_COMMIT_COUNT}"

        # Ref: https://docs.github.com/en/actions/learn-github-actions/contexts#github-context
        debug "Get the hash of the commit to start the diff from Git because the GitHub push event payload may not contain references to base_ref or previous commit."

        debug "Check if the commit is a merge commit by checking if it has more than one parent"
        local GIT_COMMIT_PARENTS_COUNT
        GIT_COMMIT_PARENTS_COUNT=$(git -C "${GITHUB_WORKSPACE}" rev-list --parents -n 1 "${GITHUB_SHA}" | wc -w)
        debug "Git commit parents count (GIT_COMMIT_PARENTS_COUNT): ${GIT_COMMIT_PARENTS_COUNT}"
        GIT_COMMIT_PARENTS_COUNT=$((GIT_COMMIT_PARENTS_COUNT - 1))
        debug "Subtract 1 from GIT_COMMIT_PARENTS_COUNT to get the actual number of merge parents because the count includes the commit itself. GIT_COMMIT_PARENTS_COUNT: ${GIT_COMMIT_PARENTS_COUNT}"

        # Ref: https://git-scm.com/docs/git-rev-parse#Documentation/git-rev-parse.txt
        local GIT_BEFORE_SHA_HEAD="HEAD"
        if [ ${GIT_COMMIT_PARENTS_COUNT} -gt 1 ]; then
          debug "${GITHUB_SHA} is a merge commit because it has more than one parent."
          GIT_BEFORE_SHA_HEAD="${GIT_BEFORE_SHA_HEAD}^2"
          debug "Add the suffix to GIT_BEFORE_SHA_HEAD to get the second parent of the merge commit: ${GIT_BEFORE_SHA_HEAD}"

          if [ ${GITHUB_PUSH_COMMIT_COUNT} -gt 0 ]; then
            GITHUB_PUSH_COMMIT_COUNT=$((GITHUB_PUSH_COMMIT_COUNT - 1))
            debug "Remove one commit from GITHUB_PUSH_COMMIT_COUNT to account for the merge commit. GITHUB_PUSH_COMMIT_COUNT: ${GITHUB_PUSH_COMMIT_COUNT}"
          else
            debug "Don't subtract one commit from GITHUB_PUSH_COMMIT_COUNT to account for the merge commit because there were no commits pushed. GITHUB_PUSH_COMMIT_COUNT: ${GITHUB_PUSH_COMMIT_COUNT}"
          fi
        else
          debug "${GITHUB_SHA} is not a merge commit because it has a single parent. No need to add the parent identifier (^) to the revision indicator because it's implicitly set to ^1 when there's only one parent."
        fi

        GIT_BEFORE_SHA_HEAD="${GIT_BEFORE_SHA_HEAD}~${GITHUB_PUSH_COMMIT_COUNT}"
        debug "GIT_BEFORE_SHA_HEAD: ${GIT_BEFORE_SHA_HEAD}"

        # shellcheck disable=SC2086  # We checked that GITHUB_PUSH_COMMIT_COUNT is an integer
        if ! GITHUB_BEFORE_SHA=$(git -C "${GITHUB_WORKSPACE}" rev-parse ${GIT_BEFORE_SHA_HEAD}); then
          fatal "Failed to initialize GITHUB_BEFORE_SHA for a push event. Output: ${GITHUB_BEFORE_SHA}"
        fi

        ValidateGitBeforeShaReference
        info "Successfully found GITHUB_BEFORE_SHA: ${GITHUB_BEFORE_SHA}"
      fi
    fi

    ############################
    # Validate we have a value #
    ############################
    if [ -z "${GITHUB_ORG}" ]; then
      error "Failed to get [GITHUB_ORG]!"
      fatal "[${GITHUB_ORG}]"
    else
      info "Successfully found GITHUB_ORG: ${GITHUB_ORG}"
    fi

    #######################
    # Get the GitHub Repo #
    #######################
    GITHUB_REPO=$(jq -r '.repository.name' <"${GITHUB_EVENT_PATH}")

    ############################
    # Validate we have a value #
    ############################
    if [ -z "${GITHUB_REPO}" ]; then
      error "Failed to get [GITHUB_REPO]!"
      fatal "[${GITHUB_REPO}]"
    else
      info "Successfully found GITHUB_REPO: ${GITHUB_REPO}"
    fi

    GITHUB_REPOSITORY_DEFAULT_BRANCH=$(GetGithubRepositoryDefaultBranch "${GITHUB_EVENT_PATH}")
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
