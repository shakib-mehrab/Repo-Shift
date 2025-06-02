# GitHub Repository Migration Scripts

This repository contains scripts and instructions to migrate all repositories from an old GitHub account to a new GitHub account.  
It supports **Windows (PowerShell)** and **macOS (bash)** environments.

---

## Overview

The scripts will:

- List all repos in your old GitHub account.
- Clone each repository locally as a mirror.
- Create new repos on your new GitHub account.
- Push all branches and tags to the new repos.
- Clean up local clones.

You need to have Personal Access Tokens (PAT) with `repo` scope for both accounts if private repos are involved.

---

## Windows 11 (PowerShell) Migration Script

### Prerequisites

- [Git for Windows](https://git-scm.com/download/win) installed.
- PowerShell access.
- PATs ready for old and new accounts.

### Script

Save this as `MigrateGitHubRepos.ps1` and customize the variables as needed:

```powershell
# --- Configuration ---
$OldUsername = "OLD_GITHUB_USERNAME"
$NewUsername = "NEW_GITHUB_USERNAME"
$NewToken = "YOUR_NEW_GITHUB_PAT"
$OldToken = "YOUR_OLD_GITHUB_PAT"  # Leave "" if old repos are public
$TempFolder = "$env:TEMP\GitHubRepoMigration"

# Create temp folder if missing
if (!(Test-Path $TempFolder)) { New-Item -ItemType Directory -Path $TempFolder | Out-Null }

Write-Host "Fetching repositories from $OldUsername ..."

$page = 1
$allRepos = @()

do {
    $url = "https://api.github.com/users/$OldUsername/repos?per_page=100&page=$page"
    $headers = @{}
    if ($OldToken) { $headers["Authorization"] = "token $OldToken" }
    $response = Invoke-RestMethod -Uri $url -Headers $headers -UseBasicParsing
    $allRepos += $response
    $page++
} while ($response.Count -eq 100)

Write-Host "Found $($allRepos.Count) repositories."

foreach ($repo in $allRepos) {
    $repoName = $repo.name
    $cloneUrl = $repo.clone_url
    $localPath = Join-Path $TempFolder $repoName

    Write-Host "Processing repo: $repoName"

    if (Test-Path $localPath) { Remove-Item -Recurse -Force $localPath }

    Write-Host "Cloning $repoName ..."
    git clone --mirror $cloneUrl $localPath

    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Failed to clone $repoName. Skipping..."
        continue
    }

    Write-Host "Creating $repoName on new account $NewUsername ..."
    $createRepoUrl = "https://api.github.com/user/repos"
    $body = @{
        name = $repoName
        description = $repo.description
        private = $repo.private
    } | ConvertTo-Json

    $headers = @{
        "Authorization" = "token $NewToken"
        "User-Agent" = "PowerShell"
        "Accept" = "application/vnd.github+json"
    }

    try {
        $createResponse = Invoke-RestMethod -Uri $createRepoUrl -Method POST -Headers $headers -Body $body -UseBasicParsing
    } catch {
        Write-Warning "Failed to create repo $repoName. Skipping..."
        continue
    }

    $newRepoCloneUrl = $createResponse.clone_url

    Push-Location $localPath
    git remote set-url origin $newRepoCloneUrl
    git push --mirror

    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Failed to push $repoName."
    } else {
        Write-Host "Successfully migrated $repoName."
    }
    Pop-Location

    Remove-Item -Recurse -Force $localPath
}

Write-Host "Migration complete."
