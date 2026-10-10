# ── Obsidian Installer (Windows) ─────────────────────────────────────
# Installs the Obsidian desktop app (https://obsidian.md) and, optionally,
# creates a vault and connects it to OpenJarvis.
#
# Usage (PowerShell):
#   .\scripts\install-obsidian.ps1
#   .\scripts\install-obsidian.ps1 -Vault "$HOME\Documents\Vault"
#
# Uses winget when available, otherwise downloads the official installer.
# ──────────────────────────────────────────────────────────────────────

param(
    [string]$Vault = ""
)

$ErrorActionPreference = "Stop"
$FallbackVersion = "1.8.10"

function Info($msg) { Write-Host "[info]  $msg" -ForegroundColor Blue }
function Ok($msg)   { Write-Host "[ok]    $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "[warn]  $msg" -ForegroundColor Yellow }

if (Get-Command winget -ErrorAction SilentlyContinue) {
    Info "Installing via winget (Obsidian.Obsidian)..."
    winget install --exact --id Obsidian.Obsidian --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0) { throw "winget install failed (exit code $LASTEXITCODE)" }
} else {
    try {
        $release = Invoke-RestMethod "https://api.github.com/repos/obsidianmd/obsidian-releases/releases/latest"
        $version = $release.tag_name.TrimStart("v")
    } catch {
        Warn "Could not query latest release, falling back to v$FallbackVersion."
        $version = $FallbackVersion
    }
    $url = "https://github.com/obsidianmd/obsidian-releases/releases/download/v$version/Obsidian-$version.exe"
    $installer = Join-Path $env:TEMP "Obsidian-$version.exe"
    Info "Downloading $url"
    Invoke-WebRequest -Uri $url -OutFile $installer
    Info "Running installer..."
    Start-Process -FilePath $installer -ArgumentList "/S" -Wait
    Remove-Item $installer -ErrorAction SilentlyContinue
}
Ok "Obsidian installed."

if ($Vault) {
    New-Item -ItemType Directory -Force -Path (Join-Path $Vault ".obsidian") | Out-Null
    $welcome = Join-Path $Vault "Welcome.md"
    if (-not (Test-Path $welcome)) {
        "# Welcome`n`nThis vault is indexed by OpenJarvis." | Set-Content -Path $welcome -Encoding UTF8
    }
    Ok "Vault ready at $Vault"

    if (Get-Command uv -ErrorAction SilentlyContinue) {
        Info "Connecting vault to OpenJarvis..."
        Push-Location (Join-Path $PSScriptRoot "..")
        try { uv run jarvis connect obsidian --path "$Vault" }
        catch { Warn "Connecting failed; run: uv run jarvis connect obsidian --path `"$Vault`"" }
        finally { Pop-Location }
    } else {
        Info "Connect it later with: uv run jarvis connect obsidian --path `"$Vault`""
    }
}
