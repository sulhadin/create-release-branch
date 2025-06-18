# Release Branch Creation Workflow #2

## Overview
This GitHub Actions workflow automates the creation of release branches from a source branch (typically `dev`). It handles the branching process, changelog generation, version updates, and commits these changes to the newly created release branch.

## Workflow Trigger
This workflow is manually triggered using GitHub's event, allowing users to specify various parameters when running the workflow. `workflow_dispatch`

## Workflow Steps
1. **Checkout Code**: Fetches the repository with its history
2. **Fetch All Branches**: Ensures all branch information is available
3. **Generate Release Branch**: The main step that:
    - Configures git merge conflict style and rebase settings
    - Runs the create-release-branch.sh script with provided parameters
    - Generates a changelog based on included PRs
    - Updates version information
    - Commits and pushes changes to the new branch

## Required Secrets
- : SSH key with repository write access `DEPLOY_KEY`

## Generated Artifacts
The workflow generates several temporary files during execution:
- : Contains the new version number `version.txt`
- : Contains formatted release notes `release_notes.txt`
- : Contains PR information for the changelog `pr_data.txt`
- Updates the file `CHANGELOG.md`

## Usage
1. Navigate to the "Actions" tab in your repository
2. Select the "Release Branch Creation" workflow
3. Click "Run workflow"
4. Fill in the required parameters:
    - Source Branch (default: dev)
    - Target Branch (default: main)

5. Optionally provide additional parameters:
    - Date range for PR filtering
    - Specific PR IDs to include
    - Patterns to exclude

6. Click "Run workflow" to start the process

## Requirements
The workflow requires:
- A Unix-like environment (runs on Ubuntu)
- Access to the script `.bash/create-release-branch.sh`
- Access to the script `.bash/utils/generate-changelog.sh`
- Access to the script `.bash/update-version.sh`
- A properly formatted file `version.json`

## Error Handling
The workflow includes error handling to detect and report failures during the release branch creation process. If the process fails, it will exit with an appropriate error message.
