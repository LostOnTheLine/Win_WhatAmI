# Install whatami into the current PowerShell profile.
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\Install-WhatAmi.ps1
# Then restart the terminal, or:
#   . $PROFILE

$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$src = Join-Path $here 'WhatAmi.ps1'
if (!(Test-Path $src)) {
    Write-Error "WhatAmi.ps1 not found next to the installer: $src"
}

$ProfileDir = Split-Path $PROFILE -Parent
if (!(Test-Path $ProfileDir)) {
    New-Item -Type Directory -Path $ProfileDir -Force | Out-Null
}
if (!(Test-Path $PROFILE)) {
    New-Item -Type File -Path $PROFILE -Force | Out-Null
}

$dest = Join-Path $ProfileDir 'WhatAmi.ps1'
Copy-Item -Path $src -Destination $dest -Force

$dotline = ". (Join-Path (Split-Path `$PROFILE -Parent) 'WhatAmi.ps1')  # whatami"

$raw = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
if (-not $raw) { $raw = '' }

$raw = [regex]::Replace(
    $raw,
    '(?s)# Added by whatami installer\r?\nfunction whatami \{.*?\n\}\r?\n?',
    ''
)
$raw = [regex]::Replace(
    $raw,
    '(?m)^function whatami \{[\s\S]*?\n\}\r?\n?',
    ''
)

if ($raw -notmatch 'WhatAmi\.ps1') {
    $raw = $raw.TrimEnd() + "`r`n`r`n# whatami`r`n$dotline`r`n"
}

Set-Content -Path $PROFILE -Value ($raw.TrimEnd() + "`r`n") -Encoding UTF8

Write-Host "Installed WhatAmi.ps1 to $dest" -ForegroundColor Green
Write-Host "Profile updated: $PROFILE" -ForegroundColor Green
Write-Host "Reload with:  . `$PROFILE" -ForegroundColor Cyan
Write-Host ""
Write-Host "  whatami" -ForegroundColor Gray
Write-Host "  whatami -d" -ForegroundColor Gray
Write-Host "  whatami -Json" -ForegroundColor Gray
Write-Host "  whatami -Plain" -ForegroundColor Gray
