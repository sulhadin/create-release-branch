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

if [ -n "$CI" ] || [ -n "$GITHUB_ACTIONS" ]; then
  # Disable colors in CI
  RED=''
  GREEN=''
  YELLOW=''
  BLUE=''
  MAGENTA=''
  CYAN=''
  RESET=''
fi


log_verbose() {
  if $verbose_detail; then
    echo "${CYAN}[VERBOSE]${RESET}"
    echo "$1"
    echo "${RED}------------------------------------------------------${RESET}"
  fi
}

cherry_pick_pr_commits() {
  local commit_hash="$1"
  local pr_title="$2"
  local pr_number="$3"

  echo "Cherry-picking commit for PR #$pr_number: $commit_hash"

  # First, verify the commit exists
  if ! git cat-file -e "$commit_hash^{commit}" 2>/dev/null; then
    echo "Warning: Commit $commit_hash doesn't exist in the local repository. Trying to fetch..."

    # Try to fetch the commit directly
    if ! git fetch origin "$commit_hash"; then
      echo "Error: Couldn't fetch commit $commit_hash. Let's try finding the PR directly..."

      # Try to fetch the PR directly
      if git fetch origin "refs/pull/$pr_number/head"; then
        pr_head_commit=$(git rev-parse FETCH_HEAD)
        echo "Found PR #$pr_number head commit: $pr_head_commit"
        commit_hash="$pr_head_commit"
      else
        # Try to find the PR merge commit in dev branch
        merge_commit=$(git log --grep="Merge pull request #$pr_number" --format="%H" "origin/dev" | head -n 1)
        if [ -n "$merge_commit" ]; then
          echo "Found merge commit for PR #$pr_number: $merge_commit"
          commit_hash="$merge_commit"
        else
          echo "Error: Could not find commit or PR #$pr_number. Skipping."
          return 1
        fi
      fi
    fi
  fi

  # Now try to cherry-pick
  if git cherry-pick -n "$commit_hash" 2>/dev/null; then
    # Check if there are any changes
    if git diff --cached --quiet; then
      echo "Empty cherry-pick detected for $commit_hash. No changes to apply."
      git reset --hard  # Clean up any partial state
      return 0
    else
      # We have changes, commit them
      if [ -n "$pr_number" ]; then
        git commit -m "$pr_title (#$pr_number)"
      else
        git commit -m "$pr_title"
      fi

      echo "Successfully cherry-picked changes from PR #$pr_number"
      return 0
    fi
  else
    # Cherry-pick failed
    echo "Cherry-pick failed for PR #$pr_number ($commit_hash)"
    git status
    git cherry-pick --abort 2>/dev/null || git reset --hard
    return 1
  fi
}

debug_commits() {
    local source_branch="$1"
    local target_branch="$2"
    local release_branch="$3"

    echo "${CYAN}===== COMMIT DEBUGGING INFORMATION =====${RESET}"

    # Log the latest commits in each branch
    echo "${YELLOW}Latest commits in $source_branch:${RESET}"
    git log -n 5 --oneline "origin/$source_branch"

    echo "${YELLOW}Latest commits in $target_branch:${RESET}"
    git log -n 5 --oneline "origin/$target_branch"

    # If release branch exists
    if git rev-parse --verify "origin/$release_branch" >/dev/null 2>&1; then
        echo "${YELLOW}Latest commits in $release_branch:${RESET}"
        git log -n 5 --oneline "origin/$release_branch"
    fi

    # Show commits that are in source but not in target
    echo "${GREEN}Commits in $source_branch that are not in $target_branch:${RESET}"
    git log --oneline "origin/$target_branch..origin/$source_branch"

    # Show common ancestor
    echo "${MAGENTA}Common ancestor between $source_branch and $target_branch:${RESET}"
    common_commit=$(git merge-base "origin/$source_branch" "origin/$target_branch")
    git log -n 1 --oneline "$common_commit"
    echo "${CYAN}===== END DEBUGGING INFORMATION =====${RESET}"
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

get_prs_by_ids() {
  local pr_ids
  IFS=',' read -ra pr_ids <<< "$include_pr_ids"

  local grep_pattern=""
  for id in "${pr_ids[@]}"; do
    # Add each PR ID to the grep pattern with OR operator
    if [ -z "$grep_pattern" ]; then
      grep_pattern="(#${id})"
    else
      grep_pattern="${grep_pattern}\|(#${id})"
    fi
  done

  echo "Finding commits with PR IDs in headline: $grep_pattern..." >&2

  # Search specifically in the message headline for PR IDs
  git_cmd="git log \"$source_branch\" --no-merges --grep=\"${grep_pattern}\" --pretty=format:'{\"oid\":\"%H\",\"messageHeadline\":\"%s\",\"messageBody\":\"%b\"}'"

  echo "$git_cmd" >&2


  local direct_commits
  direct_commits=$(eval "$git_cmd" | tr -d '\000-\037' | jq -s '.')
  echo "$direct_commits"

}

get_direct_commits() {
  local date_range=""

#    local exclude_pattern_query=""
#    for pattern in "${exclude_patterns[@]}"; do
#      exclude_pattern_query+=" NOT in:title \\\"${pattern}\\\""
#    done

  if [ -n "$mergedSinceDate" ] && [ -n "$mergedUntilDate" ]; then
    date_range="--since=\"$mergedSinceDate\" --until=\"$mergedUntilDate\""
  elif [ -n "$mergedSinceDate" ]; then
    date_range="--since=\"$mergedSinceDate\""
  elif [ -n "$mergedUntilDate" ]; then
    date_range="--until=\"$mergedUntilDate\""
  fi

  # Get all commits on the branch within the date range
  # Format direct commits to match PR commits structure
  local git_cmd="git log $source_branch --no-merges $date_range --format='{\"oid\":\"%H\",\"messageHeadline\":\"%s\",\"messageBody\":\"%b\"}'"
#
#  # Filter out commits that came from PRs
  local direct_commits
  direct_commits=$(eval "$git_cmd" | tr -d '\000-\037' | jq -s '.')
  echo "$direct_commits"
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

if [ -n "$include_pr_ids" ]; then
  pr_data=$(get_prs_by_ids)
else
  pr_data=$(get_direct_commits)
fi

log_verbose "$pr_data"

# Check if pr_data is empty or just "[]"
if [ -z "$pr_data" ] || [ "$pr_data" = "[]" ]; then
  echo "Error: No PRs found matching the criteria"
  exit 1
fi


if $no_action; then
  log_verbose "$YELLOW NO ACTION TAKEN! $RESET"
  exit 0
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

# Ensure we have the latest from remote
echo "Creating release branch...: $release_branch"

# Ensure we have the latest from remote with full history
echo "Fetching latest from remote..."
git fetch --all --prune || true

# Ensure both branches exist remotely
git ls-remote --heads origin "$source_branch" || { echo "Source branch $source_branch does not exist on remote!"; exit 1; }
git ls-remote --heads origin "$target_branch" || { echo "Target branch $target_branch does not exist on remote!"; exit 1; }

# Create the release branch from the target branch
echo "Creating release branch from $target_branch..."
git checkout -B "$release_branch" "origin/$target_branch" || { echo "Failed to create branch from $target_branch"; exit 1; }
git branch --set-upstream-to="origin/$target_branch" "$release_branch"
echo "Current branch: $(git branch --show-current)"


debug_commits "$source_branch" "$target_branch" "$release_branch"

# Create a temporary file for the PR data
temp_file=$(mktemp)
echo "$pr_data" | tr -d '\000-\037' | jq -c '.[]' > "$temp_file" 2>/dev/null

# Now extract the PR numbers and commit hashes from your PR data
echo "Filtering PRs and extracting commit hashes..."

# Process each PR
while read -r pr; do
  commit=$(echo "$pr" | jq -r '.mergeCommit.oid')
  pr_number=$(echo "$pr" | jq -r '.number')
  pr_title=$(echo "$pr" | jq -r '.title')

  echo "$pr_title"

  cherry_pick_pr_commits "$commit" "$pr_title" "$pr_number"
done < "$temp_file"

# Remove temporary file
rm "$temp_file"
rm -f cherry-pick-error.log

# Push the release branch
echo "Pushing release branch..."
git push origin "$release_branch"

echo "Prepare release notes..."
pr_body=$(get_release_notes "$release_branch")

echo "PRs:$pr_body"
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

