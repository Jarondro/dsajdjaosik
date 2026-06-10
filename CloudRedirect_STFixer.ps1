# CloudRedirect_STFixer_safe.ps1
# Downloads CloudRedirectCLI.exe from the latest GitHub release, verifies SHA-256 when available,
# then runs it with /stfixer in a safer way: logs output and does not close/crash the PowerShell window.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Owner = "Selectively11"
$Repo = "CloudRedirect"
$AssetName = "CloudRedirectCLI.exe"
$OutFile = Join-Path $env:TEMP $AssetName
$ApiUrl = "https://api.github.com/repos/$Owner/$Repo/releases/latest"

$LogDir = Join-Path $env:TEMP "CloudRedirect_STFixer_Logs"
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$StdOutLog = Join-Path $LogDir "stfixer_stdout_$Timestamp.log"
$StdErrLog = Join-Path $LogDir "stfixer_stderr_$Timestamp.log"

function Pause-End {
    Write-Host ""
    Read-Host "Hotovo. Stiskni Enter pro ukonceni"
}

try {
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

    if ($Answer -ne "Y") {
        Write-Host "Not run. File remains here: $OutFile"
        Pause-End
        return
    }

    Write-Host ""
    Write-Host "Running /stfixer..." -ForegroundColor Cyan
    Write-Host "STDOUT log: $StdOutLog"
    Write-Host "STDERR log: $StdErrLog"
    Write-Host ""

    # Run as a process so PowerShell itself does not crash/close if the EXE returns an error code.
    $Process = Start-Process `
        -FilePath $OutFile `
        -ArgumentList "/stfixer" `
        -Wait `
        -PassThru `
        -NoNewWindow `
        -RedirectStandardOutput $StdOutLog `
        -RedirectStandardError $StdErrLog

    Write-Host ""
    Write-Host "CloudRedirectCLI.exe finished with exit code: $($Process.ExitCode)" -ForegroundColor Yellow

    if (Test-Path $StdOutLog) {
        $OutText = Get-Content $StdOutLog -Raw -ErrorAction SilentlyContinue
        if ($OutText) {
            Write-Host ""
            Write-Host "---- STDOUT ----" -ForegroundColor DarkCyan
            Write-Host $OutText
        }
    }

    if (Test-Path $StdErrLog) {
        $ErrText = Get-Content $StdErrLog -Raw -ErrorAction SilentlyContinue
        if ($ErrText) {
            Write-Host ""
            Write-Host "---- STDERR / ERROR ----" -ForegroundColor Red
            Write-Host $ErrText
        }
    }

    if ($Process.ExitCode -ne 0) {
        Write-Warning "The fixer returned a non-zero exit code. Check the logs above."
    } else {
        Write-Host "Finished successfully." -ForegroundColor Green
    }

    Pause-End
}
catch {
    Write-Host ""
    Write-Host "SCRIPT ERROR:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red

    if ($_.ScriptStackTrace) {
        Write-Host ""
        Write-Host "Stack trace:" -ForegroundColor DarkGray
        Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "Logs folder: $LogDir"
    Pause-End
}
