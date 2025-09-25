# Create Release Branch - GitHub Action

[![GitHub Marketplace](https://img.shields.io/badge/Marketplace-Create%20Release%20Branch-blue.svg?colorA=24292e&colorB=0366d6&style=flat&longCache=true&logo=github)](https://github.com/marketplace/actions/create-release-branch)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Automate your release process by creating release branches, updating version numbers, and generating changelogs based on PR data.

## 👻 Motivation
To manually create a release branch using a cherry-pick strategy, you typically follow these steps:
- Create a release branch from main.
- Cherry-pick desired commits from the development branch or other current branches to include in the release.
- Generate a changelog
- Create a PR and add the PR description.
- Merge the release branch back to main.

When a new task needs to be included in the current released branch after the release PR is created, these same steps usually need to be repeated.

`create-release-branch` on the other hand automates this process by creating your desired release branch with just a few parameters, handling semantic versioning, and automatically generating changelogs.

## 🚀 Features

- **Automated Branch Creation**: Create release branches from your development branch to your production branch
- **Version Management**: Automatically updates version information in your project
- **Changelog Generation**: Create detailed changelogs based on merged pull requests
- **Customizable Filtering**: Filter PRs by date ranges, specific IDs, or exclude patterns
- **GitHub Integration**: Creates and links pull requests for your releases

## 📋 Prerequisites

This action requires:

1. A repository with at least two branches (source and target)
2. Any file in the root directory with a `version` field

## 🔧 Usage

Add this action to your workflow file (e.g., `.github/workflows/release.yml`):
```yaml 
name: Create Release Branch
on:
   workflow_dispatch:
     inputs:
         source-branch:
           description: 'Source branch to cherry-pick commits from'
           required: true
           default: 'dev'
           type: string
         target-branch:
           description: 'Target branch to create the release from'
           required: true
           default: 'main'
           type: choice
           options:
             - main
         mergedSince:
           description: 'Include PRs merged since date (format: YYYY-MM-DDTHH:MM:SSZ)'
           required: false
           default: ''
         mergedUntil:
           description: 'Include PRs merged until date (format: YYYY-MM-DDTHH:MM:SSZ)'
           required: false
           default: ''
         includePrIds:
           description: 'Comma-separated list of PR IDs to include'
           required: false
           default: ''
         excludePattern:
           description: 'Comma-separated list of title patterns to exclude'
           required: false
           default: ''
         enforceVersion:
           description: 'Enforcing a specific version (not cool but anyway)'
           required: false
jobs: 
   create-release-branch: 
      runs-on: ubuntu-latest
      steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
           fetch-depth: 0
           token: ${{ secrets.GITHUB_TOKEN }}
      - name: Create Release Branch
        uses: sulhadin/create-release-branch@v1
        with:
          source-branch: ${{ github.event.inputs.source-branch }}
          target-branch: ${{ github.event.inputs.target-branch }}
          github-token: ${{ secrets.PR_CREATION_TOKEN }}
          branch-prefix: "Release/"
          merged-since: ${{ github.event.inputs.mergedSince }}
          merged-until: ${{ github.event.inputs.mergedUntil }}
          include-pr-ids: ${{ github.event.inputs.includePrIds }}
          exclude-pattern: ${{ github.event.inputs.excludePattern }}
          version-file: "version.json"
          enforce-version: ${{ github.event.inputs.enforceVersion }}
          repo-path: "sulhadin/create-release-branch"
          verbose: 'false'
```
## ⚙️ Inputs
| Input             | Description                                               | Required | Default |
|-------------------|-----------------------------------------------------------|----------|---------|
| `source-branch`   | Source branch to cherry pick latest changes from.         | Yes      | `dev`   |
| `target-branch`   | Target branch. This is a base branch of the release.      | Yes      | `main`  |
| `merged-since`    | Merged since date in iso format (YYYY-MM-DDTHH:MM:SSZ)    | No       | -       |
| `merged-until`    | Merged until date in iso format (YYYY-MM-DDTHH:MM:SSZ)    | No       | -       |
| `include-pr-ids`  | PR IDs to include (100,101,102,104)                       | No       | -       |
| `exclude-pattern` | PR title EXCLUDE to exclude PRs/commits from the release. | No       | -       |

## ⚙️ Others
| Input            | Description                                             | Required | Default        |
|------------------|---------------------------------------------------------|----------|----------------|
| `github-token`   | GitHub token for API access                             | Yes      | -              |
| `repo-path`      | Repository path  (org/repo-name)                        | Yes      | -              |
| `branch-prefix`  | Prefix for the release branch name                      | No       | `Release/`     |
| `version-file`   | File name holding the version (should contain .version) | No       | `package.json` |
| `commit-changes` | CleanUp&Commit created files                            | No       | `true`         |
| `working-dir`    | Working directory for monorepos                         | No       | -              |
| `verbose`        | Enable verbose logging                                  | No       | `false`        |


## 📤 Outputs

| Output | Description |
|--------|-------------|
| `new-version` | The new version created by the action |
| `release-branch` | The name of the created release branch |
| `pr-url` | URL of the created pull request |

## 📊 Example Workflow with Outputs
```yaml
- name: Create Release Branch 
  id: release 
  uses: sulhadin/create-release-branch@v1 
  with: 
      source-branch: 'dev' 
      target-branch: 'main' 
      github-token: {{ secrets.GITHUB_TOKEN }} 
      repo-path: {{ github.repository }}

- name: Use Action Outputs 
  run: | 
    echo "New version: {{ steps.release.outputs.new-version }}" 
    echo "Release branch:{{ steps.release.outputs.release-branch }}" 
    echo "PR URL: ${{ steps.release.outputs.pr-url }}"
```
## 🔍 Advanced Configuration

### Date Filtering

Filter PRs by date range to create releases for specific periods:
```yaml 
with: 
  merged-since: '2023-01-01T00:00:00Z' 
  merged-until: '2023-01-31T23:59:59Z'
``` 
### Specific PRs

Include only specific PRs in your release:
```yaml 
with: 
  include-pr-ids: '123,456,789'
``` 

### Exclude Patterns

Exclude PRs matching certain patterns:
```yaml 
with: 
  exclude-pattern: 'chore:,#norelease'
``` 

## 🛠️ Customization

You can customize the branch naming convention:
```yaml 
with: 
  branch-prefix: 'release/' # Creates branches like release/1.2.0
``` 

## Caution
- If the workflow creates a pr name that is already taken, the action will fail. So make sure to delete the previous release after merging it into the main.

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 👥 Contributing

Contributions, issues, and feature requests are welcome! Feel free to check [issues page](https://github.com/sulhadin/create-release-branch/issues).

## 📝 Changelog

See the [CHANGELOG.md](CHANGELOG.md) file for details about version changes.

## 🙏 Acknowledgements

- This action was inspired by the need for automating release processes
- Special thanks to all the contributors and users who provide feedback

---

Made with ❤️ by [Sulhadin Öney](https://github.com/sulhadin)
