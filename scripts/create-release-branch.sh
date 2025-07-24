#!/bin/bash

# Default values
source_branch="dev"
target_branch="main"
release_branch_prefix="Release/"
current_version=""
version_file=""
mergedSinceDate=""
mergedUntilDate=""
include_pr_ids=""
exclude_patterns=""
verbose_detail=false
no_action=false

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
    --version-file)
      version_file="$2"
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
      exclude_patterns="$2"
      shift 2
      ;;
    --include-pr-ids)
      include_pr_ids="$2"
      shift 2
      ;;
      --branch-prefix)
        release_branch_prefix="$2"
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
  local pr_number
  pr_number=$(echo "$pr_title" | grep -oE '\(#[0-9]+\)' | grep -oE '[0-9]+')


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
     git commit --no-verify -m "$pr_title"

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

    log_verbose "${CYAN}===== COMMIT DEBUGGING INFORMATION =====${RESET}"

    # Log the latest commits in each branch
    log_verbose "${YELLOW}Latest commits in $source_branch:${RESET}"
    git log -n 5 --oneline "origin/$source_branch"

    log_verbose "${YELLOW}Latest commits in $target_branch:${RESET}"
    git log -n 5 --oneline "origin/$target_branch"

    # If release branch exists
    if git rev-parse --verify "origin/$release_branch" >/dev/null 2>&1; then
        log_verbose "${YELLOW}Latest commits in $release_branch:${RESET}"
        git log -n 5 --oneline "origin/$release_branch"
    fi

    # Show commits that are in source but not in target
    log_verbose "${GREEN}Commits in $source_branch that are not in $target_branch:${RESET}"
    git log --oneline "origin/$target_branch..origin/$source_branch"

    # Show common ancestor
    log_verbose "${MAGENTA}Common ancestor between $source_branch and $target_branch:${RESET}"
    common_commit=$(git merge-base "origin/$source_branch" "origin/$target_branch")
    git log -n 1 --oneline "$common_commit"
    log_verbose "${CYAN}===== END DEBUGGING INFORMATION =====${RESET}"
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
  log_verbose "Begin: get_prs_by_ids"
   # Parse comma-separated PR IDs
   IFS=',' read -ra pr_ids <<< "$include_pr_ids"
   local include_pr_id_query=""
   first=true
   printf "["
   for ((i=${#pr_ids[@]}-1; i>=0; i--)); do
       pattern="${pr_ids[i]}"

      include_pr_id_query="is:pr \\\"${pattern}\\\""
      pr_cmd="gh pr list --state merged --base \"$source_branch\" --search \"$include_pr_id_query\" --json number,mergeCommit"
      log_verbose "$pr_cmd"

      merge_commit=$(eval "$pr_cmd" | jq -r '.[0].mergeCommit.oid')

      log_verbose "oid: $merge_commit"

     if [ -z "$merge_commit" ]; then
       log_verbose "No matching PRs found" >&2
     else
       if $first; then
         first=false
       else
         printf ","
       fi

       # Get commit details with newlines converted to spaces
       oid=$(git log -n 1 --pretty=format:'%H' "$merge_commit")
       headline=$(git log -n 1 --pretty=format:'%s' "$merge_commit" | sed 's/"/\\"/g')
       body=$(git log -n 1 --pretty=format:'%b' "$merge_commit" | sed 's/"/\\"/g')

       echo "{\"oid\":\"$oid\",\"messageHeadline\":\"$headline\",\"messageBody\":\"$body\"}" | tr '\n' ' '
     fi
   done

   printf "]\n"
}

get_direct_commits() {
  local date_range=""

  IFS=',' read -ra exclude_filter <<< "$exclude_patterns"


  if [ -n "$mergedSinceDate" ] && [ -n "$mergedUntilDate" ]; then
    date_range="--since=\"$mergedSinceDate\" --until=\"$mergedUntilDate\""
  elif [ -n "$mergedSinceDate" ]; then
    date_range="--since=\"$mergedSinceDate\""
  elif [ -n "$mergedUntilDate" ]; then
    date_range="--until=\"$mergedUntilDate\""
  fi


  # Use printf to format the JSON array opening
    printf "["

    # Get commits with a simple format that we can parse
    local commits
    commits=$(eval "git log $source_branch --no-merges $date_range --format='%H'")

    # Process each commit with proper comma handling
    first=true
    for commit in $commits; do
      oid=$(git log -n 1 --pretty=format:'%H' "$commit")
      headline=$(git log -n 1 --pretty=format:'%s' "$commit" | sed 's/"/\\"/g')
      body=$(git log -n 1 --pretty=format:'%b' "$commit" | sed 's/"/\\"/g')

      #/start This block is for excluding some commits
      skip_commit=false
      if [ -n "$exclude_patterns" ]; then
        for pattern in "${exclude_filter[@]}"; do
          if echo "$headline" | grep -q "$pattern"; then
            skip_commit=true
            break
          fi
        done
      fi

      if $skip_commit; then
        continue
      fi
      #/end This block is for excluding some commits

      if $first; then
        first=false
      else
        printf ","
      fi
      echo "{\"oid\":\"$oid\",\"messageHeadline\":\"$headline\",\"messageBody\":\"$body\"}" | tr '\n' ' '
    done

    # Close the JSON array
    printf "]\n"
}

semantic_versioning() {
  log_verbose "Begin: semantic_versioning"
  local version_param="$1"
  local json_data="$2"

  # Initialize version flags
  local major=false
  local minor=false
  local patch=false

  temp_file=$(mktemp)
  echo "$json_data" > "$temp_file"

  # Create another temporary file for the extracted items
  items_file=$(mktemp)
  jq -c '.[]' "$temp_file" > "$items_file"

  # Process each commit
  while IFS= read -r item; do
    messageBody=$(echo "$item" | jq -r '.messageBody')

    if $verbose_detail; then
      log_verbose "Checking commit: $messageBody"
    fi

    if echo "$messageBody" | grep -qiE "(\* )?( +)?BREAKING[- _]CHANGE(\([^)]+\))? ?:( .*)?"; then
      major=true
      if $verbose_detail; then
        log_verbose "${RED}Found BREAKING CHANGE${RESET}"
      fi
      break
    elif echo "$messageBody" | grep -qiE "(( +)?\* )?(feat)(\([^)]+\))? ?:( .*)?"; then
      minor=true
      if $verbose_detail; then
        log_verbose "${YELLOW}Found feature${RESET}"
      fi
    elif echo "$messageBody" | grep -qiE "(( +)?\* )?(fix|perf)(\([^)]+\))? ?:( .*)?"; then
      patch=true
      if $verbose_detail; then
        log_verbose "${GREEN}Found fix/perf${RESET}"
      fi
    fi
  done < "$items_file"

  # Clean up
  rm "$temp_file" "$items_file"

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

echo "PR DATA: $CYAN$pr_data$RESET"

# Check if pr_data is empty or just "[]"
if [ -z "$pr_data" ] || [ "$pr_data" = "[]" ]; then
  echo "Error: No PRs found matching the criteria"
  exit 1
fi


if $no_action; then
  echo "$YELLOW NO ACTION TAKEN! $RESET"
  exit 0
fi

# Checkout main branch to start with a clean state
git checkout "origin/$target_branch"
git branch --show-current

current_version=$(jq -r '.version' "$version_file")

echo "Current version from version.json: $current_version"

# Calculate the next version based on PR data
version_info=$(semantic_versioning "$current_version" "$pr_data")
echo "Version info from semantic_versioning: $version_info"

next_version=$(echo "$version_info" | tail -n1)
echo "Next version will be: $next_version"

# Create release branch name
release_branch="${release_branch_prefix}${next_version}"

# Ensure we have the latest from remote
echo "Creating release branch...: $release_branch"

# Ensure we have the latest from remote with full history
echo "Fetching latest from remote..."
git fetch --all --prune || true
#
## Ensure both branches exist remotely
git ls-remote --heads origin "$source_branch" || { echo "Source branch $source_branch does not exist on remote!"; exit 1; }
git ls-remote --heads origin "$target_branch" || { echo "Target branch $target_branch does not exist on remote!"; exit 1; }

# Create the release branch from the target branch
echo "Creating release branch from $target_branch..."
git checkout -B "$release_branch" "origin/$target_branch" || { echo "Failed to create branch from $target_branch"; exit 1; }
git branch --set-upstream-to="origin/$target_branch" "$release_branch"
echo "Current branch: $(git branch --show-current)"


debug_commits "$source_branch" "$target_branch" "$release_branch"


json=$(echo "$pr_data" | jq 'reverse')

echo "Reverse PR DATA: $CYAN$json$RESET"

# Now extract the PR numbers and commit hashes from your PR data
echo "Filtering PRs and extracting commit hashes..."

echo "$json" | jq -c '.[]' | while read -r item; do
    oid=$(echo "$item" | jq -r '.oid')
    messageHeadline=$(echo "$item" | jq -r '.messageHeadline')

    cherry_pick_pr_commits "$oid" "$messageHeadline"
done

rm -f cherry-pick-error.log

# Push the release branch
echo "Pushing release branch..."
if ! git push --no-verify origin "HEAD:$release_branch"; then
  echo "Error pushing branch $release_branch"
  # Check if the branch exists locally
  git branch | grep "$release_branch"
  exit 1
fi

if ! git ls-remote --heads origin "$release_branch" | grep -q "$release_branch"; then
  echo "Error: Branch $release_branch was not successfully pushed to remote"
  exit 1
fi



echo "Prepare release notes..."
pr_body=$(git log --oneline "origin/$target_branch..HEAD")

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