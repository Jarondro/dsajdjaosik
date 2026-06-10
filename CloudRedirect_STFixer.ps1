# CloudRedirect_STFixer.ps1
# Downloads CloudRedirectCLI.exe from the latest GitHub release, verifies SHA-256 when available,
# then optionally runs it with /stfixer.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Owner = "Selectively11"
$Repo = "CloudRedirect"
$AssetName = "CloudRedirectCLI.exe"
$OutFile = Join-Path $env:TEMP $AssetName
$ApiUrl = "https://api.github.com/repos/$Owner/$Repo/releases/latest"

Write-Host "Fetching latest release info..." -ForegroundColor Cyan

# Helps older Windows PowerShell versions use modern TLS.
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {}

$Headers = @{
    "Accept" = "application/vnd.github+json"
    "User-Agent" = "CloudRedirect-STFixer-Downloader"
}

$Release = Invoke-RestMethod -Uri $ApiUrl -Headers $Headers
$Asset = $Release.assets | Where-Object { $_.name -eq $AssetName } | Select-Object -First 1

if (-not $Asset) {
    throw "Asset '$AssetName' was not found in the latest release."
}

Write-Host "Latest release: $($Release.tag_name)"
Write-Host "Download URL: $($Asset.browser_download_url)"
Write-Host "Downloading to: $OutFile" -ForegroundColor Cyan

Invoke-WebRequest -Uri $Asset.browser_download_url -OutFile $OutFile -Headers @{ "User-Agent" = "CloudRedirect-STFixer-Downloader" }

if (-not (Test-Path $OutFile)) {
    throw "Download failed: file was not created."
}

$ActualHash = (Get-FileHash -Path $OutFile -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host "Downloaded SHA-256: $ActualHash"

# GitHub release assets may include a digest field like: sha256:<hash>
$ExpectedHash = $null
if ($Asset.PSObject.Properties.Name -contains "digest" -and $Asset.digest) {
    $ExpectedHash = ($Asset.digest -replace "^sha256:", "").ToLowerInvariant()
}

if ($ExpectedHash) {
    Write-Host "Expected SHA-256:   $ExpectedHash"

    if ($ActualHash -ne $ExpectedHash) {
        Remove-Item $OutFile -Force -ErrorAction SilentlyContinue
        throw "SHA-256 mismatch. The downloaded file was deleted and will not be run."
    }

    Write-Host "Hash verified successfully." -ForegroundColor Green
} else {
    Write-Warning "No SHA-256 digest was provided by GitHub API for this asset. Review the file before running it."
}

Write-Host ""
Write-Host "This will run: `"$OutFile`" /stfixer" -ForegroundColor Yellow
$Answer = Read-Host "Run it now? Type Y to continue"

if ($Answer -eq "Y") {
    & $OutFile /stfixer
    exit $LASTEXITCODE
} else {
    Write-Host "Not run. File remains here: $OutFile"
}
