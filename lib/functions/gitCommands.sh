#!/usr/bin/env bash

ConfigureGitSafeDirectories() {
  debug "Configuring Git safe directories"
  declare -a git_safe_directories=("${GITHUB_WORKSPACE}" "${DEFAULT_SUPER_LINTER_WORKSPACE}" "${DEFAULT_WORKSPACE}")
  for safe_directory in "${git_safe_directories[@]}"; do
    debug "Set ${safe_directory} as a Git safe directory"
    if ! git config --global --add safe.directory "${safe_directory}"; then
      fatal "Cannot configure ${safe_directory} as a Git safe directory."
    fi
  done
}
