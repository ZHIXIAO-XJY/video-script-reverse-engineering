# install.ps1 - Install this skill into the WorkBuddy user-level skills folder
# Usage: powershell -ExecutionPolicy Bypass -File scripts\install.ps1
$ErrorActionPreference = "Stop"

$Src  = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Base = if ($env:WORKBUDDY_SKILLS_DIR) { $env:WORKBUDDY_SKILLS_DIR } else { Join-Path $env:USERPROFILE ".workbuddy\skills" }
$Dest = Join-Path $Base "video-script-reverse-engineering"

Write-Host "Source: $Src"
Write-Host "Target: $Dest"

if (-not (Test-Path (Join-Path $Src "SKILL.md"))) {
    Write-Error "SKILL.md not found in $Src. Run this script from the repository root."
    exit 1
}

if (Test-Path $Dest) {
    $Backup = "$Dest.bak." + (Get-Date -Format "yyyyMMddHHmmss")
    Write-Host "Existing install found, backing up to: $Backup"
    Move-Item $Dest $Backup
}

New-Item -ItemType Directory -Path $Dest -Force | Out-Null
Copy-Item (Join-Path $Src "SKILL.md") $Dest -Force
Copy-Item (Join-Path $Src "references") $Dest -Recurse -Force
Copy-Item (Join-Path $Src "scripts")    $Dest -Recurse -Force

Write-Host ""
Write-Host "Installed to: $Dest"
Get-ChildItem $Dest -Recurse -File -Name | ForEach-Object { Write-Host ("  " + $_) }

if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Host ""
    Write-Host "WARNING: ffmpeg not found. Install it first: winget install ffmpeg"
}

Write-Host ""
Write-Host "Restart WorkBuddy, then try: reverse-engineer the script of <video path>"
