const core = require('@actions/core');
const exec = require('@actions/exec');
const fs = require('fs');
const path = require('path');

async function run() {
    try {
        // Get inputs
        const sourceInput = core.getInput('source-branch', { required: true });
        const targetInput = core.getInput('target-branch', { required: true });
        const branchPrefix = core.getInput('branch-prefix') || 'release-branch/';
        const currentVersion = core.getInput('current-version', { required: true });
        const mergedSince = core.getInput('merged-since');
        const mergedUntil = core.getInput('merged-until');
        const includePrIds = core.getInput('include-pr-ids');
        const excludePattern = core.getInput('exclude-pattern');
        const verbose = core.getInput('verbose') === 'true';
        process.env.GH_TOKEN = core.getInput('github-token', { required: true });

        await exec.exec('git', ['config', '--global', 'user.name', process.env.GITHUB_ACTOR || 'GitHub Action']);
        await exec.exec('git', ['config', '--global', 'user.email', `${process.env.GITHUB_ACTOR_ID || '41898282'}+${process.env.GITHUB_ACTOR || 'github-actions[bot]'}@users.noreply.github.com`]);

        // Make script files executable
        const scriptDir = path.join(__dirname, 'scripts');
        await exec.exec('chmod', ['-R', '+x', scriptDir]);

        // Build the command with required parameters
        let cmd = [
            path.join(scriptDir, 'create-release-branch.sh'),
            '--source', sourceInput,
            '--target', targetInput,
            '--version', currentVersion
        ];

        // Add optional parameters
        if (branchPrefix) cmd.push('--branch-prefix', branchPrefix);
        if (mergedSince) cmd.push('--from-date', mergedSince);
        if (mergedUntil) cmd.push('--to-date', mergedUntil);
        if (includePrIds) cmd.push('--include-pr-ids', includePrIds);
        if (excludePattern) cmd.push('--exclude', excludePattern);
        if (verbose) cmd.push('--verbose');

        // Execute the release branch creation script
        core.info(`Executing create-release-branch.sh with parameters: ${cmd.join(' ')}`);
        await exec.exec('bash', cmd);

        // Read the new version from version.txt
        const newVersion = fs.readFileSync('version.txt', 'utf8').trim();
        core.info(`New version: ${newVersion}`);

        // Update the version.json file
        await exec.exec('bash', [
            path.join(scriptDir, 'update-version.sh'),
            newVersion
        ]);

        // Generate changelog
        const prData = fs.readFileSync('pr_data.txt', 'utf8');
        await exec.exec('bash', [
            path.join(scriptDir, 'generate-changelog.sh'),
            newVersion,
            prData
        ]);

        // Get the current branch name (should be the release branch)
        let releaseBranch = '';
        await exec.exec('git', ['branch', '--show-current'], {
            listeners: {
                stdout: (data) => {
                    releaseBranch += data.toString().trim();
                }
            }
        });
        core.info(`Release branch: ${releaseBranch}`);

        // Commit and push changes
        await exec.exec('git', ['add', '.']);
        await exec.exec('git', ['commit', '-m', `bump(version): app to ${newVersion}`]);
        await exec.exec('git', ['push', 'origin', `HEAD:${releaseBranch}`]);

        // Set outputs
        core.setOutput('new-version', newVersion);
        core.setOutput('release-branch', releaseBranch);

        // Get PR URL if available
        if (fs.existsSync('pr_url.txt')) {
            const prUrl = fs.readFileSync('pr_url.txt', 'utf8').trim();
            core.setOutput('pr-url', prUrl);
        }

        // Clean up
        fs.unlinkSync('version.txt');
        fs.unlinkSync('release_notes.txt');
        fs.unlinkSync('pr_data.txt');
        if (fs.existsSync('pr_url.txt')) fs.unlinkSync('pr_url.txt');

    } catch (error) {
        core.setFailed(error.message);
    }
}

run().then();