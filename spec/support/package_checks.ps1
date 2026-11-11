$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/../../scripts/package-helpers.ps1"

function Expect-Failure {
    param([scriptblock]$Action, [string]$Message)
    try {
        & $Action
    } catch {
        if ($_.Exception.Message -notlike "*$Message*") { throw }
        return
    }
    throw "Expected failure containing: $Message"
}

$shell = (Get-Process -Id $PID).Path
Invoke-CheckedNative -FilePath $shell -Arguments @('-NoProfile', '-Command', 'exit 0')
Expect-Failure { Invoke-CheckedNative -FilePath $shell -Arguments @('-NoProfile', '-Command', 'exit 7') } 'exit code 7'

$root = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory $root | Out-Null
try {
    $artifact = Join-Path $root 'installer.exe'
    Expect-Failure { Assert-PackageFile $artifact } 'Missing or empty'
    [System.IO.File]::WriteAllBytes($artifact, [byte[]]@())
    Expect-Failure { Assert-PackageFile $artifact } 'Missing or empty'
    [System.IO.File]::WriteAllBytes($artifact, [byte[]]@(77, 90))
    Assert-PackageFile $artifact
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force
}
Write-Host 'Package checks passed: failed compiler exit, missing/empty artifacts, and successful output'
# Expected native failures can leave LASTEXITCODE nonzero. GitHub's pwsh
# wrapper propagates it, so reset it only after all assertions have passed.
exit 0
