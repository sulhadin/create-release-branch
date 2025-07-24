if [ -z "$1" ]; then
  echo "Usage: sh file-name <version> <pr_data> <filename> <repo_name>"
  exit 1
fi

if [ -z "$2" ]; then
  echo "Usage: sh file-name <version> <pr_data> <filename> <repo_name>"
  exit 1
fi

if [ -z "$3" ]; then
  echo "Usage: sh file-name <version> <pr_data> <filename> <repo_name>"
  exit 1
fi
if [ -z "$4" ]; then
  echo "Usage: sh file-name <version> <pr_data> <filename> <repo_name>"
  exit 1
fi

new_version=$1
pr_changelog=$2
changelog_file_path=$3
repo_name=$4

format_changelog(){
   local changelog_content="$1"
   local repo_name="$2"

   # Convert commit hashes to GitHub commit links
   # [<commit-url|commit-hash>]
   changelog_content=$(echo "$changelog_content" | sed -E "s|([^\\[])([a-f0-9]{9})([^a-f0-9])|\\1[\\2](https://github.com/${repo_name}/commit/\\2)\\3|g")

   # Convert ClickUp IDs to ClickUp links
   # Format: #86c1rbjd1 -> [#86c1rbjd1](https://app.clickup.com/t/86c1rbjd1)
   changelog_content=$(echo "$changelog_content" | sed -E "s|#([a-zA-Z0-9]{8}[a-z0-9]*)|[#\\1](https://app.clickup.com/t/\\1)|g")

   # Convert PR numbers to GitHub PR links
   # Format: (#799) -> ([#799](https://github.com/bilira-org/kripto-mobile/pull/799))
   changelog_content=$(echo "$changelog_content" | sed -E "s|\\(#([0-9]+)\\)|(\\[#\\1\\](https://github.com/${repo_name}/pull/\\1))|g")

   echo "$changelog_content"
}

generate_changelog_entry() {
  local version="$1"
  local pr_data="$2"
  local release_date
  release_date=$(date +"%Y-%m-%d")

  # Start building the changelog entry
  local changelog_entry
  changelog_entry=$'\n'"## [${version}] - ${release_date}"$'\n'

  # Extract PR titles and categorize them
  local features=""
  local fixes=""
  local breaking=""
  local others=""

  temp_file=$(mktemp)
  echo "$pr_data" > "$temp_file"
  items_file=$(mktemp)
  jq -c '.[]' "$temp_file" > "$items_file" 2>/dev/null

  while IFS= read -r pr; do
    local pr_title
    local pr_commit
    pr_commit=$(git rev-parse --short "$(echo "$pr" | jq -r '.oid')")
    pr_title=$(echo "$pr" | jq -r '.messageHeadline')

    # Extract commit message body - fix here
    local messageBody
    messageBody=$(echo "$pr" | jq -r '.messageBody')

    if echo "$messageBody" | grep -qiE "(\* )?( +)?BREAKING[- _]CHANGE(\([^)]+\))? ?:( .*)?"; then
      breaking+="- ${pr_title} (${pr_commit})"$'\n'
    # If no breaking changes, check for feat/fix/perf
    elif echo "$messageBody" | grep -qiE "(( +)?\* )?(feat)(\([^)]+\))? ?:( .*)?"; then
      features+="- ${pr_title} (${pr_commit})"$'\n'
    elif echo "$messageBody" | grep -qiE "(( +)?\* )?(fix|perf)(\([^)]+\))? ?:( .*)?"; then
      fixes+="- ${pr_title} (${pr_commit})"$'\n'
    else
      others+="- ${pr_title} (${pr_commit})"$'\n'
    fi
  done < "$items_file"

  rm "$temp_file" "$items_file"

  # Add sections to changelog entry if they contain changes
  if [ -n "$breaking" ]; then
    changelog_entry+=$'\n'"### BREAKING CHANGES"$'\n\n'"${breaking}"
  fi

  if [ -n "$features" ]; then
    changelog_entry+=$'\n'"### Features"$'\n\n'"${features}"
  fi

  if [ -n "$fixes" ]; then
    changelog_entry+=$'\n'"### Bug Fixes"$'\n\n'"${fixes}"
  fi

  if [ -n "$others" ]; then
    changelog_entry+=$'\n'"### Other Changes"$'\n\n'"${others}"
  fi

  echo "$changelog_entry"
}

update_changelog() {
  local version="$1"
  local pr_data="$2"
  local changelog_file="$3"

  changelog_dir=$(dirname "$changelog_file")
  mkdir -p "$changelog_dir"


  # Generate new changelog entry
  local new_entry
  new_entry=$(generate_changelog_entry "$version" "$pr_data")
#
  echo "$new_entry"

 new_entry=$(format_changelog "$new_entry" "$repo_name")

  # Check if CHANGELOG.md exists
  if [ ! -f "$changelog_file" ]; then
    # Create a new CHANGELOG.md file
    printf "# Changelog\n\nAll notable changes to this project will be documented in this file.\n\n${new_entry}" > "$changelog_file"
  else
    # Insert the new entry after the header
    entry_file=$(mktemp)
    echo "$new_entry" > "$entry_file"

    # Use sed to insert after the first line
    awk 'NR==4{print; system("cat '"$entry_file"'"); next}1' "$changelog_file" > "${changelog_file}.new"

    # Clean up
    rm "$entry_file"
    mv "${changelog_file}.new" "$changelog_file"
  fi

  echo "Updated $changelog_file with changes for version $version"
}

update_changelog "$new_version" "$pr_changelog" "$changelog_file_path"