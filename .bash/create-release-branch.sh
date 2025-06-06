#!/bin/bash

# Default values
source_branch="dev"
target_branch="main"
release_branch_prefix="release-branch/"
release_version=""
mergedSinceDate=""
mergedUntilDate=""
include_pr_ids=""
exclude_patterns=()
verbose_detail=false
no_action=false
repo_name="bilira-org/kripto-mobile"  # Default repository name

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      source_branch="$2"
      shift 2
      ;;
    --target)
      target_branch="$2"
      shift 2
      ;;
    --version)
      release_version="$2"
      shift 2
      ;;
    --from-date)
      mergedSinceDate="$2"
      shift 2
      ;;
    --to-date)
      mergedUntilDate="$2"
      shift 2
      ;;
    --exclude)
      exclude_patterns+=("$2")
      shift 2
      ;;
    --include-pr-ids)
      include_pr_ids="$2"
      shift 2
      ;;
    --verbose)
      # Handle as a flag without requiring a value
      verbose_detail=true
      shift 1
      ;;
    --no-action)
      # Handle as a flag without requiring a value
      no_action=true
      shift 1
      ;;
    --repo)
      repo_name="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 --version VERSION [--source BRANCH] [--target BRANCH] [--from-date DATE] [--to-date DATE] [--include-patterns 'pattern1,pattern2,...'] [--exclude PATTERN] [--verbose]"
      exit 1
      ;;
  esac
done

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
RESET='\033[0m'

#deprecated
#format_changelog(){
#   local changelog_content="$1"
#   local repo_name="$2"
#
#   # Convert commit hashes to GitHub commit links
#   # [<commit-url|commit-hash>]
#   changelog_content=$(echo "$changelog_content" | sed -E "s|([^\\[])([a-f0-9]{7,8})([^a-f0-9])|\\1[\\2](https://github.com/${repo_name}/commit/\\2)\\3|g")
#
#   # Convert ClickUp IDs to ClickUp links
#   # Format: #86c1rbjd1 -> [#86c1rbjd1](https://app.clickup.com/t/86c1rbjd1)
#   changelog_content=$(echo "$changelog_content" | sed -E "s|#([a-zA-Z0-9]{8}[a-z0-9]*)|[#\\1](https://app.clickup.com/t/\\1)|g")
#
#   # Convert PR numbers to GitHub PR links
#   # Format: (#799) -> ([#799](https://github.com/bilira-org/kripto-mobile/pull/799))
#   changelog_content=$(echo "$changelog_content" | sed -E "s|\\(#([0-9]+)\\)|(\\[#\\1\\](https://github.com/${repo_name}/pull/\\1))|g")
#
#   echo "$changelog_content"
#}
##deprecated
#generate_changelog_entry() {
#  local version="$1"
#  local pr_data="$2"
#  local release_date
#  release_date=$(date +"%Y-%m-%d")
#
#  # Start building the changelog entry
#  local changelog_entry
#  changelog_entry="## [${version}] - ${release_date}"$'\n\n'
#
#
#  # Extract PR titles and categorize them
#  local features=""
#  local fixes=""
#  local breaking=""
#  local others=""
#
#  temp_file=$(mktemp)
#  echo "$pr_data" | tr -d '\000-\037' | jq -c '.[]' > "$temp_file" 2>/dev/null
#
#  while read -r pr; do
#    local pr_number
#    local pr_title
#    local pr_commit
#    pr_commit=$(git rev-parse --short "$(echo "$pr" | jq -r '.mergeCommit.oid')")
#    pr_number=$(echo "$pr" | jq -r '.number')
#    pr_title=$(echo "$pr" | jq -r '.title')
#
#    # Extract commit messages to look for conventional commit prefixes
#    local commit_messages
#    commit_messages=$(echo "$pr" | jq -r '.commits[].messageHeadline')
#
#    if echo "$commit_messages" | grep -qiE "^(\* )?( +)?BREAKING[- _]CHANGE(\([^)]+\))? ?:( .*)?"; then
#      breaking+="- ${pr_title} (#${pr_number}) (${pr_commit})\n"
#    # If no breaking changes, check the first line for feat/fix/perf, with or without colon
#    elif echo "$commit_messages" | grep -qiE "^(( +)?\* )?(feat)(\([^)]+\))? ?:( .*)?"; then
#      features+="- ${pr_title} (#${pr_number}) (${pr_commit})\n"
#    elif echo "$commit_messages" | grep -qiE "^(( +)?\* )?(fix|perf)(\([^)]+\))? ?:( .*)?"; then
#      fixes+="- ${pr_title} (#${pr_number}) (${pr_commit})\n"
#    else
#      others+="- ${pr_title} (#${pr_number}) (${pr_commit})\n"
#    fi
#  done < "$temp_file"
#
#  rm "$temp_file"
#
#  # Add sections to changelog entry if they contain changes
#  if [ -n "$breaking" ]; then
#    changelog_entry+="### BREAKING CHANGES\n\n${breaking}\n"
#  fi
#
#  if [ -n "$features" ]; then
#    changelog_entry+="### Features\n\n${features}\n"
#  fi
#
#  if [ -n "$fixes" ]; then
#    changelog_entry+="### Bug Fixes\n\n${fixes}\n"
#  fi
#
#  if [ -n "$others" ]; then
#    changelog_entry+="### Other Changes\n\n${others}\n"
#  fi
#
#  echo "$changelog_entry"
#}
##deprecated
#update_changelog() {
#  local version="$1"
#  local pr_data="$2"
#  local changelog_file="CHANGELOG.md"
#
#  # Generate new changelog entry
#  local new_entry
#  new_entry=$(generate_changelog_entry "$version" "$pr_data")
##
#  echo "$new_entry"
#
# new_entry=$(format_changelog "$new_entry" "$repo_name")
#
#  # Check if CHANGELOG.md exists
#  if [ ! -f "$changelog_file" ]; then
#    # Create a new CHANGELOG.md file
#    printf "# Changelog\n\nAll notable changes to this project will be documented in this file.\n\n${new_entry}" > "$changelog_file"
#  else
#    # Insert the new entry after the header
#    entry_file=$(mktemp)
#    echo "$new_entry" > "$entry_file"
#
#    # Use sed to insert after the first line
#    sed "4 r $entry_file" "$changelog_file" > "${changelog_file}.new"
#
#    # Clean up
#    rm "$entry_file"
#    mv "${changelog_file}.new" "$changelog_file"
#
#  fi
#
#  echo "Updated $changelog_file with changes for version $version"
#}

# Function to log messages if verbose is enabled
log_verbose() {
  if $verbose_detail; then
    echo "${CYAN}[VERBOSE]${RESET}"
    echo "$1"
    echo "${RED}------------------------------------------------------${RESET}"
  fi
}

increment_version() {
  local version=$1
  local major_increment=$2
  local minor_increment=$3
  local patch_increment=$4

  major=$(echo "$version" | cut -d. -f1)
  minor=$(echo "$version" | cut -d. -f2)
  patch=$(echo "$version" | cut -d. -f3)

  if [ "$major_increment" = true ]; then
    major=$((major + 1))
    minor=0
    patch=0
  elif [ "$minor_increment" = true ]; then
    minor=$((minor + 1))
    patch=0
  elif [ "$patch_increment" = true ]; then
    patch=$((patch + 1))
  fi

  echo "$major.$minor.$patch"
}

get_prs_by() {
  date_query=""
  if [ -n "$mergedSinceDate" ] && [ -n "$mergedUntilDate" ]; then
    date_query="merged:$mergedSinceDate..$mergedUntilDate"
  elif [ -n "$mergedSinceDate" ]; then
    date_query="merged:>=$mergedSinceDate"
  elif [ -n "$mergedUntilDate" ]; then
    date_query="merged:<=$mergedUntilDate"
  fi

  local exclude_pattern_query=""
  for pattern in "${exclude_patterns[@]}"; do
    exclude_pattern_query+=" NOT in:title \\\"${pattern}\\\""
  done

  IFS=',' read -ra pr_ids <<< "$include_pr_ids"
  local include_pr_id_query=""
  for pattern in "${pr_ids[@]}"; do
    include_pr_id_query+=" is:pr \\\"${pattern}\\\""
  done

  # Get merged PRs with their merge commits
  echo "Finding merged PRs with query: $exclude_pattern_query..." >&2
  #gh pr list --state merged --base dev --search "merged:2025-05-27T00:00:00Z..2025-05-30T00:00:00Z NOT in:title \"#86c1c1uka\" NOT in:title \"#0\""
  pr_cmd="gh pr list --state merged --base \"$source_branch\" --search \"$date_query$exclude_pattern_query$include_pr_id_query\" --json number,title,mergeCommit,commits"
  eval "$pr_cmd"
}

get_release_notes(){
  local release_branch_name="$1"
  local result
  result=$(git log --oneline "origin/$target_branch..origin/$release_branch_name")

  echo "$result"
}

semantic_versioning() {
  local version_param="$1"
  local json_data="$2"

  # Initialize version flags
  local major=false
  local minor=false
  local patch=false

  local commit_messages

commit_messages=$(echo "$json_data" | grep -o '"messageHeadline"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/"messageHeadline"[[:space:]]*:[[:space:]]*"//;s/"$//')

  if $verbose_detail; then
    echo "$commit_messages" | while read -r commit_msg; do
      log_verbose "$BLUE Processing commit:$RESET$MAGENTA $commit_msg $RESET"
          # First check entire commit message for breaking changes, with or without colon
          if echo "$commit_msg" | grep -qiE "^(\* )?( +)?BREAKING[- _]CHANGE(\([^)]+\))? ?:( .*)?"; then
            log_verbose "$RED$commit_msg$RESET"
          # If no breaking changes, check the first line for feat/fix/perf, with or without colon
          elif echo "$commit_msg" | grep -qiE "^(( +)?\* )?(feat)(\([^)]+\))? ?:( .*)?"; then
            log_verbose "$YELLOW$commit_msg$RESET"
          elif echo "$commit_msg" | grep -qiE "^(( +)?\* )?(fix|perf)(\([^)]+\))? ?:( .*)?"; then
            log_verbose "$GREEN$commit_msg$RESET"
          fi
        done
  fi
#
  result=$(echo "$commit_messages" | while read -r commit_msg; do
    # First check entire commit message for breaking changes, with or without colon
    if echo "$commit_msg" | grep -qiE "^(\* )?( +)?BREAKING[- _]CHANGE(\([^)]+\))? ?:( .*)?"; then
      echo "major"
    # If no breaking changes, check the first line for feat/fix/perf, with or without colon
    elif echo "$commit_msg" | grep -qiE "^(( +)?\* )?(feat)(\([^)]+\))? ?:( .*)?"; then
      echo "minor"
    elif echo "$commit_msg" | grep -qiE "^(( +)?\* )?(fix|perf)(\([^)]+\))? ?:( .*)?"; then
      echo "patch"
    fi
  done)

  case "$result" in
    *major*) major=true ;;
    *minor*) minor=true ;;
    *patch*) patch=true ;;
  esac

  # Calculate new version
  log_verbose "major:$RED $major $RESET minor:$YELLOW $minor $RESET patch:$GREEN $patch $RESET"
  local new_version
  new_version=$(increment_version "$version_param" "$major" "$minor" "$patch")

  echo "$new_version"
}


pr_data=$(get_prs_by)

log_verbose "$pr_data"


# Check if pr_data is empty or just "[]"
if [ -z "$pr_data" ] || [ "$pr_data" = "[]" ]; then
  echo "Error: No PRs found matching the criteria"
  exit 1
fi


# Checkout main branch to start with a clean state
git checkout "origin/$target_branch"
git branch --show-current



# Get the current version from version.json
if [ -z "$release_version" ]; then
  current_version=$(jq -r '.version' version.json)
fi
log_verbose "Current version from version.json: $current_version"

# Calculate the next version based on PR data
version_info=$(semantic_versioning "$current_version" "$pr_data")
log_verbose "Version info from semantic_versioning: $version_info"
next_version=$(echo "$version_info" | tail -n1)
log_verbose "Next version will be: $next_version"

# Create release branch name
release_branch="${release_branch_prefix}${next_version}"

echo "Creating release branch...: $release_branch"
git checkout -b "$release_branch" "origin/$target_branch"
git branch --show-current





if $no_action; then
  log_verbose "$YELLOW NO ACTION TAKEN! $RESET"
  exit 0
fi

# Create a temporary file for the PR data
temp_file=$(mktemp)
echo "$pr_data" | tr -d '\000-\037' | jq -c '.[]' > "$temp_file" 2>/dev/null


# Extract PR info and filter by exclusion patterns
echo "Filtering PRs and extracting commit hashes..."
while read -r pr; do
  commit=$(echo "$pr" | jq -r '.mergeCommit.oid')
  pr_number=$(echo "$pr" | jq -r '.number')

  echo "Cherry-picking $commit  (#$pr_number)..."
  if ! git cherry-pick "$commit" 2>/dev/null; then
    # Check if it's just an empty commit
    if git diff --cached --quiet; then
      echo "Empty cherry-pick detected for $commit, continuing with --allow-empty"
      git cherry-pick --continue --allow-empty
    else
      echo "Error: Failed to cherry-pick commit $commit (#$pr_number) due to conflicts"
      echo "Aborting cherry-pick and cleaning up..."
      git cherry-pick --abort
      git checkout "$source_branch"
      git branch -D "$release_branch"
      exit 1
    fi
  fi
done < "$temp_file"

# Remove temporary file
rm "$temp_file"

# Push the release branch
echo "Pushing release branch..."
git push origin "$release_branch"

echo "Prepare release notes..."
pr_body=$(get_release_notes "$release_branch")

echo "Generate release_notes.txt"
echo "$pr_body" > release_notes.txt
echo "Generate pr_data.txt"
echo "$pr_data" > pr_data.txt

echo "Pull request creating"
pr_url=$(gh pr create --base "$target_branch" --head "$release_branch" --title "$release_branch" --body "$pr_body")
echo "Pull request created: $pr_url"

##UPDATE version.json
echo "$next_version" > version.txt
echo "version.txt: Updated version to $next_version"

echo "Done!"