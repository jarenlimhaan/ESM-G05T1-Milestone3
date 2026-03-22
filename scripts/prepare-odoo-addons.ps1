param(
    [string]$Branch = "17.0"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$addonsRoot = Join-Path $repoRoot "external_addons"
$helpdeskDir = Join-Path $addonsRoot "helpdesk"

if (!(Test-Path $addonsRoot)) {
    New-Item -ItemType Directory -Path $addonsRoot | Out-Null
}

if (!(Test-Path $helpdeskDir)) {
    Write-Host "Cloning OCA helpdesk addons ($Branch)..."
    git clone --depth 1 --branch $Branch https://github.com/OCA/helpdesk.git $helpdeskDir
} else {
    Write-Host "Updating OCA helpdesk addons ($Branch)..."
    git -C $helpdeskDir fetch --depth 1 origin $Branch
    git -C $helpdeskDir checkout $Branch
    git -C $helpdeskDir pull --ff-only origin $Branch
}

Write-Host "Addon preparation completed: $helpdeskDir"
