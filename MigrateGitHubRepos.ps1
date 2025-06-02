# --- Configuration ---
$OldUsername = "mehrab-shakib"     # Your old GitHub username
$NewUsername = "shakib-mehrab"     # Your new GitHub username
$NewToken = ""        # Your PAT for the new GitHub account
$OldToken = ""        # Optional: if your old repos are private, provide PAT here
$TempFolder = "$env:TEMP\GitHubRepoMigration"

# --- Setup ---
if (!(Test-Path $TempFolder)) {
    New-Item -ItemType Directory -Path $TempFolder | Out-Null
}

Write-Host "Fetching repositories from $OldUsername ..."

# API url to list all repos from old account (100 per page max)
$page = 1
$allRepos = @()

do {
    $url = "https://api.github.com/users/$OldUsername/repos?per_page=100&page=$page"
    $headers = @{}
    if ($OldToken) {
        $headers["Authorization"] = "token $OldToken"
    }

    $response = Invoke-RestMethod -Uri $url -Headers $headers -UseBasicParsing
    $allRepos += $response
    $page++
} while ($response.Count -eq 100)

Write-Host "Found $($allRepos.Count) repositories."

foreach ($repo in $allRepos) {
    $repoName = $repo.name
    $cloneUrl = $repo.clone_url
    $repoFullName = $repo.full_name

    Write-Host "Processing repo: $repoFullName"

    $localPath = Join-Path $TempFolder $repoName

    # Clone the repo
    if (Test-Path $localPath) {
        Remove-Item -Recurse -Force $localPath
    }

    Write-Host "Cloning $repoFullName ..."
    git clone --mirror $cloneUrl $localPath

    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Failed to clone $repoFullName. Skipping..."
        continue
    }

    # Create new repo on new GitHub account using API
    Write-Host "Creating repository $repoName on new account $NewUsername ..."
    $createRepoUrl = "https://api.github.com/user/repos"
    $body = @{
        name = $repoName
        description = $repo.description
        private = $repo.private
        has_issues = $true
        has_projects = $true
        has_wiki = $true
    } | ConvertTo-Json

    $headers = @{
        "Authorization" = "token $NewToken"
        "User-Agent" = "PowerShell"
        "Accept" = "application/vnd.github+json"
    }

    try {
        $createResponse = Invoke-RestMethod -Uri $createRepoUrl -Method POST -Headers $headers -Body $body -UseBasicParsing
    } catch {
        Write-Warning "Failed to create repo $repoName on new account. Skipping..."
        continue
    }

    $newRepoCloneUrl = $createResponse.clone_url

    # Push all branches and tags to new repo
    Write-Host "Pushing $repoName to new repo ..."
    Push-Location $localPath
    git remote set-url origin $newRepoCloneUrl
    git push --mirror

    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Failed to push $repoName to new repo."
    } else {
        Write-Host "Successfully migrated $repoName."
    }

    Pop-Location

    # Optional: Remove local clone to save space
    Remove-Item -Recurse -Force $localPath
}

Write-Host "Migration complete. Cleaned up local clones."
