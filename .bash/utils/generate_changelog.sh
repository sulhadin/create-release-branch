if [ -z "$1" ]; then
  echo "Usage: sh file-name <pr_data>"
  exit 1
fi

if [ -z "$2" ]; then
  echo "Usage: sh file-name pr_data"
  exit 1
fi

new_version=$1
pr_changelog=$2

format_changelog(){
   local changelog_content="$1"
   local repo_name="$2"

   # Convert commit hashes to GitHub commit links
   # [<commit-url|commit-hash>]
   changelog_content=$(echo "$changelog_content" | sed -E "s|([^\\[])([a-f0-9]{7,8})([^a-f0-9])|\\1[\\2](https://github.com/${repo_name}/commit/\\2)\\3|g")

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
  changelog_entry="## [${version}] - ${release_date}"$'\n\n'


  # Extract PR titles and categorize them
  local features=""
  local fixes=""
  local breaking=""
  local others=""

  temp_file=$(mktemp)
  echo "$pr_data" | tr -d '\000-\037' | jq -c '.[]' > "$temp_file" 2>/dev/null

  while read -r pr; do
    local pr_number
    local pr_title
    local pr_commit
    pr_commit=$(git rev-parse --short "$(echo "$pr" | jq -r '.mergeCommit.oid')")
    pr_number=$(echo "$pr" | jq -r '.number')
    pr_title=$(echo "$pr" | jq -r '.title')

    # Extract commit messages to look for conventional commit prefixes
    local commit_messages
    commit_messages=$(echo "$pr" | jq -r '.commits[].messageHeadline')

    if echo "$commit_messages" | grep -qiE "^(\* )?( +)?BREAKING[- _]CHANGE(\([^)]+\))? ?:( .*)?"; then
      breaking+="- ${pr_title} (#${pr_number}) (${pr_commit})\n"
    # If no breaking changes, check the first line for feat/fix/perf, with or without colon
    elif echo "$commit_messages" | grep -qiE "^(( +)?\* )?(feat)(\([^)]+\))? ?:( .*)?"; then
      features+="- ${pr_title} (#${pr_number}) (${pr_commit})\n"
    elif echo "$commit_messages" | grep -qiE "^(( +)?\* )?(fix|perf)(\([^)]+\))? ?:( .*)?"; then
      fixes+="- ${pr_title} (#${pr_number}) (${pr_commit})\n"
    else
      others+="- ${pr_title} (#${pr_number}) (${pr_commit})\n"
    fi
  done < "$temp_file"

  rm "$temp_file"

  # Add sections to changelog entry if they contain changes
  if [ -n "$breaking" ]; then
    changelog_entry+="### BREAKING CHANGES\n\n${breaking}\n"
  fi

  if [ -n "$features" ]; then
    changelog_entry+="### Features\n\n${features}\n"
  fi

  if [ -n "$fixes" ]; then
    changelog_entry+="### Bug Fixes\n\n${fixes}\n"
  fi

  if [ -n "$others" ]; then
    changelog_entry+="### Other Changes\n\n${others}\n"
  fi

  echo "$changelog_entry"
}

update_changelog() {
  local version="$1"
  local pr_data="$2"
  local changelog_file="CHANGELOG.md"

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
    sed "4 r $entry_file" "$changelog_file" > "${changelog_file}.new"

    # Clean up
    rm "$entry_file"
    mv "${changelog_file}.new" "$changelog_file"

  fi

  echo "Updated $changelog_file with changes for version $version"
}

update_changelog "$new_version" "$pr_changelog"