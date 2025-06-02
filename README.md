
# GitHub Repository Migration Scripts

This repository contains scripts and instructions to migrate all repositories from an old GitHub account to a new GitHub account.  
It supports **Windows (PowerShell)** and **macOS (bash)** environments.

---

## Overview

The scripts will:

- List all repositories in your old GitHub account.
- Clone each repository locally as a mirror.
- Create new repositories on your new GitHub account.
- Push all branches and tags to the new repositories.
- Clean up local clones.

You need to have Personal Access Tokens (PAT) with `repo` scope for both accounts if private repositories are involved.

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
````

### How to Run

1. Open PowerShell.

2. Navigate to the folder containing `MigrateGitHubRepos.ps1`.

3. Run:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\MigrateGitHubRepos.ps1
```

---

## macOS Migration Script (bash)

### Prerequisites

* Git installed (`git --version`).
* `jq` installed for JSON parsing (`brew install jq`).
* PATs ready.

### Script (`migrate_github_repos.sh`)

```bash
#!/bin/bash

OLD_USERNAME="OLD_GITHUB_USERNAME"
NEW_USERNAME="NEW_GITHUB_USERNAME"
NEW_TOKEN="YOUR_NEW_GITHUB_PAT"
OLD_TOKEN="YOUR_OLD_GITHUB_PAT" # leave empty "" if old repos are public
TEMP_FOLDER="$HOME/github_migration_temp"

mkdir -p "$TEMP_FOLDER"

echo "Fetching repos from $OLD_USERNAME..."

page=1
all_repos=()

while :; do
    if [ -z "$OLD_TOKEN" ]; then
        response=$(curl -s "https://api.github.com/users/$OLD_USERNAME/repos?per_page=100&page=$page")
    else
        response=$(curl -s -H "Authorization: token $OLD_TOKEN" "https://api.github.com/users/$OLD_USERNAME/repos?per_page=100&page=$page")
    fi

    repo_count=$(echo "$response" | jq '. | length')
    if [ "$repo_count" -eq 0 ]; then break; fi

    all_repos+=("$response")
    ((page++))
done

repos=$(printf '%s\n' "${all_repos[@]}" | jq -s 'add')
repo_names=$(echo "$repos" | jq -r '.[].name')

echo "Found $(echo "$repos" | jq length) repositories."

for repo_name in $repo_names; do
    echo "Processing $repo_name"

    clone_url=$(echo "$repos" | jq -r ".[] | select(.name==\"$repo_name\") | .clone_url")
    description=$(echo "$repos" | jq -r ".[] | select(.name==\"$repo_name\") | .description")
    private=$(echo "$repos" | jq -r ".[] | select(.name==\"$repo_name\") | .private")

    local_path="$TEMP_FOLDER/$repo_name.git"
    rm -rf "$local_path"

    echo "Cloning $repo_name ..."
    git clone --mirror "$clone_url" "$local_path"
    if [ $? -ne 0 ]; then echo "Clone failed, skipping."; continue; fi

    echo "Creating $repo_name on new account $NEW_USERNAME ..."
    create_repo_response=$(curl -s -X POST -H "Authorization: token $NEW_TOKEN" -H "Accept: application/vnd.github+json" \
        https://api.github.com/user/repos \
        -d "{\"name\":\"$repo_name\", \"description\":\"$description\", \"private\":$private}")

    if echo "$create_repo_response" | grep -q '"errors"'; then
        echo "Failed to create repo, skipping."
        continue
    fi

    new_clone_url=$(echo "$create_repo_response" | jq -r '.clone_url')

    cd "$local_path" || continue
    git remote set-url origin "$new_clone_url"
    git push --mirror
    if [ $? -ne 0 ]; then echo "Push failed."; else echo "Migrated $repo_name."; fi

    cd "$HOME"
    rm -rf "$local_path"
done

echo "Migration complete."
```

### How to Run

1. Save the script as `migrate_github_repos.sh`.

2. Make it executable:

```bash
chmod +x migrate_github_repos.sh
```

3. Run the script:

```bash
./migrate_github_repos.sh
```

---

## How to Push This Guide to GitHub

1. Create a new local folder and initialize git:

```bash
mkdir github-repo-migration
cd github-repo-migration
git init
```

2. Save this entire markdown content as `README.md` inside that folder.

3. Stage and commit:

```bash
git add README.md
git commit -m "Add complete GitHub repo migration guide for Windows and macOS"
```

4. Create a new GitHub repository via the website or GitHub CLI:

```bash
gh repo create
```

5. Link the remote repository:

```bash
git remote add origin https://github.com/YOUR_NEW_USERNAME/github-repo-migration.git
```

6. Push to GitHub:

```bash
git branch -M main
git push -u origin main
```

---

## Notes

* Replace placeholders (`OLD_GITHUB_USERNAME`, `NEW_GITHUB_USERNAME`, tokens) before running scripts.
* Backup your repositories before migrating.
* The scripts push all branches, tags, and refs via `git push --mirror`.
* If a repo already exists on the new account, it will be skipped.
* Ensure your PATs have sufficient permissions (`repo` scope).

