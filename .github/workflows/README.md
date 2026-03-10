# GitHub Actions Workflows

This directory contains automated workflows for managing LLM model metadata updates and releases.

## Workflows

### 1. CI (`ci.yml`)

Runs on every push and pull request to ensure code quality.

**Triggers:**
- Push to `main` branch
- Pull requests to `main` branch

**Jobs:**
- Install dependencies and cache them
- Check code formatting (`mix format --check-formatted`)
- Compile with warnings as errors
- Run test suite
- Generate coverage report (on Elixir 1.16/OTP 26 only)

**Matrix Testing:**
- Elixir versions: 1.14, 1.15, 1.16
- OTP versions: 25, 26
- Excludes: Elixir 1.14 with OTP 26 (compatibility)

### 2. Refresh Upstream Metadata (`build-metadata.yml`)

Automatically pulls latest LLM model metadata from upstream sources and creates PRs for review.

**Triggers:**
- **Schedule**: Every Monday at 00:00 UTC
- **Manual**: Via workflow_dispatch in GitHub Actions UI

**Jobs:**
1. Pull latest metadata using `mix llm_db.pull`
2. Regenerate metadata using `mix llm_db.build`
3. Reset `metadata-update` from `origin/main`
4. If non-history metadata changes are detected:
   - Commit metadata artifacts first
   - Run `mix llm_db.history.sync --to HEAD`
   - Commit history artifacts second
   - Create or update the PR with `gh pr create` / `gh pr edit`

**Output:**
- Pull request with metadata changes for human review
- Summary includes provider/model statistics and changed files
- Metadata update PRs now contain two commits
- Metadata update PRs must be merged with a merge commit, not squash-merged or rebase-merged

### 3. Publish Release (`publish-release.yml`)

Automatically publishes new Hex.pm releases when metadata updates are merged.

**Triggers:**
- Push to `main` branch
- Only when `priv/llm_db/snapshot.json` changes
- Only from metadata update merges

**Jobs:**
1. Verify trigger is from metadata update merge
2. Prepare release using `mix llm_db.release prepare`
   - Determines version from snapshot timestamp (YYYY.MM.DD format)
   - Updates `mix.exs` version
3. Run tests to ensure quality
4. Build Hex package
5. Publish to Hex.pm
6. Create git tag (e.g., `v2024.11.06`)
7. Create GitHub release with:
   - Provider and model statistics
   - Installation instructions
   - Generated release notes

**Version Format:**
- Date-based: `YYYY.MM.DD`
- Multiple releases same day: `YYYY.MM.DD.N` (e.g., `2024.11.06.1`)

## Setup Instructions

### 1. Required Secrets

Configure these secrets in your GitHub repository settings:

#### `HEX_API_KEY`

Your Hex.pm API key for publishing packages.

**How to get it:**
1. Login to [hex.pm](https://hex.pm)
2. Go to Settings → API keys
3. Create a new key with publish permissions
4. Copy the key

**Add to GitHub:**
1. Go to repository Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Name: `HEX_API_KEY`
4. Value: Your Hex API key
5. Click "Add secret"

### 2. Permissions

The workflows use `GITHUB_TOKEN` with these permissions:
- `contents: write` - Create branches, tags, and commits
- `pull-requests: write` - Create and manage pull requests

These are configured in each workflow file and should work automatically.

### 3. Optional Configuration

#### Cron Schedule

To change the update frequency, edit `build-metadata.yml`:

```yaml
on:
  schedule:
    - cron: '0 0 * * 1'  # Every Monday at 00:00 UTC
```

Cron examples:
- `'0 0 * * *'` - Daily at midnight UTC
- `'0 0 * * 0'` - Weekly on Sunday
- `'0 0 1 * *'` - Monthly on the 1st

#### PR Reviewers

To auto-assign reviewers to metadata update PRs, modify the PR creation step in `build-metadata.yml`:

```bash
gh pr create \
  --base main \
  --head "metadata-update" \
  --title "Update model metadata - $(date +%Y-%m-%d)" \
  --body-file "$SUMMARY_FILE" \
  --label "metadata-update" \
  --label "automated" \
  --reviewer "username1,username2"  # Add this line
```

## Manual Operations

### Manually Trigger Metadata Update

1. Go to Actions tab in GitHub
2. Select "Refresh Upstream Metadata" workflow
3. Click "Run workflow"
4. Select branch (usually `main`)
5. Click "Run workflow"

### Manually Create a Release

Releases are automatically triggered when metadata updates merge to main. To manually release:

1. Ensure snapshot is updated: `mix llm_db.pull`
2. Prepare release: `mix llm_db.release prepare`
3. Review version in `mix.exs`
4. Commit and push to main
5. Workflow will detect snapshot change and publish

## Workflow Scripts

Helper scripts in `.github/workflows/scripts/`:

### `generate_summary.sh`

Generates PR description for metadata updates with:
- Provider and model counts
- Generated timestamp
- File diff statistics
- Review checklist

### `generate_release_notes.sh`

Generates GitHub release notes with:
- Snapshot version and statistics
- Provider breakdown
- Installation instructions

## Troubleshooting

### Workflow Not Triggering

**Problem:** Update workflow doesn't run on schedule

**Solutions:**
1. Check workflow is enabled in Actions tab
2. Verify cron syntax is correct
3. Note: Scheduled workflows may be delayed during high GitHub load
4. Try manual trigger to test

### Release Not Publishing

**Problem:** Publish workflow doesn't trigger after metadata merge

**Solutions:**
1. Verify provider metadata or generated artifacts were actually modified
2. Check commit message contains "Update model metadata"
3. Review workflow logs in Actions tab
4. Ensure `HEX_API_KEY` secret is set correctly

### Test Failures

**Problem:** CI fails on specific Elixir/OTP combinations

**Solutions:**
1. Review test output in Actions logs
2. Check matrix exclusions in `ci.yml`
3. Test locally with same Elixir/OTP versions
4. Update matrix if version is no longer supported

### Permission Errors

**Problem:** Workflow can't create branches or PRs

**Solutions:**
1. Verify workflow has `contents: write` and `pull-requests: write` permissions
2. Check repository settings → Actions → General → Workflow permissions
3. Ensure "Allow GitHub Actions to create and approve pull requests" is enabled

## Best Practices

1. **Review All Metadata PRs**: Always review automated PRs before merging
2. **Use Merge Commits for Metadata PRs**: Do not squash-merge or rebase-merge `metadata-update` PRs
3. **Test Before Release**: CI runs automatically, but check test results
4. **Monitor Releases**: Check Hex.pm after publish to verify release
5. **Keep Secrets Secure**: Rotate `HEX_API_KEY` periodically
6. **Update Dependencies**: Keep actions versions current (e.g., `@v4` → `@v5`)

## Development

To test workflow changes:

1. Create a branch with workflow modifications
2. Push to GitHub
3. Workflows won't run on branches, but you can:
   - Use `workflow_dispatch` for manual testing
   - Create a PR to see CI in action
   - Merge to main to test full pipeline

## Support

For issues or questions:
1. Check workflow logs in Actions tab
2. Review this README
3. Check GitHub Actions documentation
4. Open an issue in the repository
