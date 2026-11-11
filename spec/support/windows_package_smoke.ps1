$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/../../scripts/package-helpers.ps1"

$version = (Invoke-CheckedNative -FilePath 'shards' -Arguments @('version', '.')).Trim()
$root = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory $root | Out-Null

function Run-Package {
    param([string]$Path, [string[]]$Arguments)
    $stdout = Join-Path $root 'stdout.txt'
    $stderr = Join-Path $root 'stderr.txt'
    $process = Start-Process -FilePath (Resolve-Path -LiteralPath $Path).Path -ArgumentList $Arguments `
        -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    if ($process.ExitCode -ne 0) {
        throw "Package process failed: $Path (exit $($process.ExitCode)): $(Get-Content $stderr -Raw)"
    }
    return (Get-Content $stdout -Raw)
}

try {
    $portable = "dist/memo_${version}_ucrt64.exe"
    Assert-PackageFile $portable
    if ((Run-Package $portable @('--version')).Trim() -ne $version) {
        throw 'Standalone executable did not report the expected version'
    }
    $installDir = Join-Path $root 'Memo install'
    Run-Package "dist/memo_${version}_ucrt64_setup.exe" @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/DIR=`"$installDir`"") | Out-Null
    $installed = Join-Path $installDir 'memo.exe'
    Assert-PackageFile $installed
    if ((Run-Package $installed @('--version')).Trim() -ne $version) {
        throw 'Installed executable did not report the expected version'
    }
    Write-Host 'Standalone EXE, silent installation, and installed EXE checks passed'
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force
}
