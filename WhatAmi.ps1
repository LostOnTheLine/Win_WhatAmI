# whatami for Windows PowerShell
# Version: 0.1.7
# Dot-source:  . .\WhatAmi.ps1
# Then:        whatami
#              whatami -d
#              whatami -Version
#              whatami -Plain
#              whatami -Json

function whatami {
    [CmdletBinding()]
    param(
        [Alias('d')]
        [switch]$Details,
        [switch]$Version,
        [switch]$Plain,
        [switch]$Json,
        [switch]$NoColor
    )

    $WhatAmiVersion = '0.1.7'

    if ($Version -and -not $Json -and -not $Details) {
        Write-Output "whatami $WhatAmiVersion"
        return
    }

    function Get-WhatAmiContext {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]$identity
        $isElevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

        $canElevate = $false
        $adminAttr = $null
        $integrity = 'unknown'
        try {
            $groups = @(whoami /groups /fo csv 2>$null | ConvertFrom-Csv)
            foreach ($g in $groups) {
                $name = [string]$g.'Group Name'
                $sid  = [string]$g.SID
                $attr = [string]$g.Attributes
                if ($sid -eq 'S-1-5-32-544' -or $name -eq 'BUILTIN\Administrators') {
                    $canElevate = $true
                    $adminAttr = $attr
                }
                if ($sid -eq 'S-1-16-16384' -or $name -match 'System Mandatory Level') {
                    $integrity = 'system'
                } elseif ($sid -eq 'S-1-16-12288' -or $name -match 'High Mandatory Level') {
                    $integrity = 'high'
                } elseif ($sid -eq 'S-1-16-8192' -or $name -match 'Medium Mandatory Level') {
                    $integrity = 'medium'
                } elseif ($sid -eq 'S-1-16-4096' -or $name -match 'Low Mandatory Level') {
                    $integrity = 'low'
                }
            }
        } catch { }

        if ($isElevated) { $canElevate = $true }

        $userName = if ($identity.Name) { $identity.Name } else { [string](whoami) }
        $slashIdx = $userName.LastIndexOf('\')
        if ($slashIdx -ge 0) {
            $machinePart = $userName.Substring(0, $slashIdx)
            $accountPart = $userName.Substring($slashIdx + 1)
        } else {
            $machinePart = [string]$env:USERDOMAIN
            $accountPart = $userName
        }

        $hostName = [string]$env:COMPUTERNAME
        if (-not $hostName) {
            try { $hostName = [System.Net.Dns]::GetHostName() } catch { $hostName = $machinePart }
        }

        if ($isElevated -and $integrity -eq 'system') {
            $role = 'SYSTEM'; $roleLabel = 'SYSTEM'
        } elseif ($isElevated) {
            $role = 'ADMIN'; $roleLabel = 'ADMIN'
        } elseif ($canElevate) {
            $role = 'ADMIN_AVAILABLE'; $roleLabel = 'ADMIN AVAILABLE'
        } else {
            $role = 'USER'; $roleLabel = 'USER'
        }

        $cwd = (Get-Location).Path

        $gitBranch = $null
        $gitDirty = $false
        if (Get-Command git -ErrorAction SilentlyContinue) {
            try {
                $branch = & git rev-parse --abbrev-ref HEAD 2>$null
                if ($LASTEXITCODE -eq 0 -and $branch) {
                    $gitBranch = ([string]($branch | Select-Object -First 1)).Trim()
                    if ($gitBranch -eq 'HEAD') {
                        $sha = & git rev-parse --short HEAD 2>$null
                        if ($LASTEXITCODE -eq 0 -and $sha) {
                            $gitBranch = "detached:" + ([string]($sha | Select-Object -First 1)).Trim()
                        }
                    }
                    $status = & git status --porcelain 2>$null
                    if ($LASTEXITCODE -eq 0 -and $status) { $gitDirty = $true }
                }
            } catch { }
        }

        $envGuess = 'local'
        $hay = ("$hostName $cwd $machinePart $env:USERDOMAIN").ToLowerInvariant()
        if ($hay -match 'prod|production') { $envGuess = 'production' }
        elseif ($hay -match 'stag') { $envGuess = 'staging' }
        elseif ($hay -match 'dev|develop') { $envGuess = 'dev' }

        $isPSSession = $false
        try { if ($PSSenderInfo) { $isPSSession = $true } } catch { }

        $session = 'console'
        if ($env:SSH_CLIENT -or $env:SSH_CONNECTION -or $env:SSH_TTY) {
            $session = 'ssh'
        } elseif ($env:SESSIONNAME -match '^RDP-') {
            $session = 'rdp'
        } elseif ($isPSSession) {
            $session = 'PSSession'
        }

        $mux = $null
        $muxSession = $null
        $muxOnDefault = $false
        if ($env:ZELLIJ -or $env:ZELLIJ_SESSION_NAME) {
            $mux = 'zellij'
            $muxSession = $env:ZELLIJ_SESSION_NAME
            $muxOnDefault = $true
        } elseif ($env:PSMUX_SESSION_NAME -or $env:PSMUX_TARGET_SESSION -or $env:PSMUX_DATA_DIR) {
            $mux = 'psmux'
            $muxSession = $env:PSMUX_SESSION_NAME
            if (-not $muxSession) { $muxSession = $env:PSMUX_TARGET_SESSION }
            $muxOnDefault = $true
        } elseif ($env:TMUX) {
            # psmux also sets TMUX inside panes (tmux-compatible). Prefer psmux if its vars exist.
            $mux = 'tmux'
            if ($env:TMUX -match '^([^,]+)') { $muxSession = $Matches[1] }
            $muxOnDefault = $true
        } elseif ($env:STY) {
            $mux = 'screen'
            $muxSession = $env:STY
            $muxOnDefault = $true
        } elseif ($env:WEZTERM_PANE -or $env:WEZTERM_UNIX_SOCKET) {
            $mux = 'wezterm'
            $muxOnDefault = $true
        } elseif ($env:WT_SESSION) {
            $mux = 'windowsterminal'
        } elseif ($env:ConEmuPID) {
            $mux = 'conemu'
        }

        $container = $null
        if ($env:container) {
            $container = [string]$env:container
        } elseif ($env:WSL_DISTRO_NAME) {
            $container = "wsl:$($env:WSL_DISTRO_NAME)"
        } elseif ($env:KUBERNETES_SERVICE_HOST) {
            $container = 'kubernetes'
        } elseif ($env:DOCKER_CONTAINER) {
            $container = 'docker'
        }

        $cloud = @()
        if ($env:AWS_PROFILE -or $env:AWS_DEFAULT_PROFILE -or $env:AWS_ACCESS_KEY_ID) {
            $p = $env:AWS_PROFILE; if (-not $p) { $p = $env:AWS_DEFAULT_PROFILE }
            $cloud += $(if ($p) { "aws:$p" } else { 'aws' })
        }
        if ($env:AZURE_CONFIG_DIR -or $env:AZUREPS_HOST_ENVIRONMENT -or $env:MSI_ENDPOINT) {
            $cloud += 'azure'
        }
        if ($env:GOOGLE_CLOUD_PROJECT -or $env:GCLOUD_PROJECT -or $env:CLOUDSDK_CORE_PROJECT) {
            $proj = $env:GOOGLE_CLOUD_PROJECT
            if (-not $proj) { $proj = $env:GCLOUD_PROJECT }
            $cloud += $(if ($proj) { "gcp:$proj" } else { 'gcp' })
        }

        $warnings = @()
        if ($isElevated) { $warnings += 'elevated' }
        if ($canElevate -and -not $isElevated) { $warnings += 'admin_available' }
        if ($envGuess -eq 'production') { $warnings += 'production_environment' }
        if ($gitBranch -match '^(main|master)$') { $warnings += 'main_branch' }
        if ($isElevated -and $envGuess -eq 'production') { $warnings += 'admin_on_production' }

        $risk = 'low'
        if ($isElevated -and $envGuess -eq 'production') { $risk = 'critical' }
        elseif ($envGuess -eq 'production') { $risk = 'high' }
        elseif ($isElevated -and $gitBranch -match '^(main|master)$') { $risk = 'high' }
        elseif ($canElevate) { $risk = 'medium' }
        elseif ($gitBranch -match '^(main|master)$') { $risk = 'medium' }

        $virt = $null
        $isGuest = $false
        $hypervisor = $null
        $hvPresent = $false
        $vendor = $null
        $machineModel = $null
        $chipset = $null
        $cpu = $null
        $memory = $null
        $gpu = $null
        $osName = $null
        $uptime = $null
        if ($Details -or $Json) {
            try {
                $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
                $model = [string]$cs.Model
                $mfr = [string]$cs.Manufacturer
                if ($model) { $machineModel = $model.Trim() }
                $blob = "$mfr $model"

                # Guest only when SMBIOS looks like a VM vendor. HypervisorPresent alone
                # is also true on bare metal with Hyper-V, WSL2, or VBS/Memory Integrity.
                if ($blob -match 'VMware') {
                    $virt = 'VMware'; $isGuest = $true
                } elseif ($blob -match 'VirtualBox|innotek') {
                    $virt = 'VirtualBox'; $isGuest = $true
                } elseif ($blob -match 'QEMU|KVM') {
                    $virt = 'QEMU/KVM'; $isGuest = $true
                } elseif ($blob -match 'Xen' -or $model -match '(^|\s)HVM(\s|$)') {
                    $virt = 'Xen'; $isGuest = $true
                } elseif ($blob -match 'Hyper-V' -or ($mfr -match 'Microsoft' -and $model -match 'Virtual Machine')) {
                    $virt = 'Hyper-V'; $isGuest = $true
                } elseif ($blob -match 'Amazon|EC2') {
                    $virt = 'Amazon EC2'; $isGuest = $true
                } elseif ($mfr -match 'Google' -and $model -match 'Google|Compute') {
                    $virt = 'Google'; $isGuest = $true
                } elseif ($blob -match 'Virtual Machine|Virtual Platform|HVMhouse|Bochs|Parallels') {
                    $virt = $(if ($mfr) { $mfr.Trim() } else { 'virtual' })
                    $isGuest = $true
                }

                $hvPresent = [bool]$cs.HypervisorPresent
                if ($mfr) { $vendor = $mfr.Trim() }

                # HypervisorPresent = the Windows hypervisor is loaded on this OS
                # (Hyper-V, WSL2, VBS/Memory Integrity). It is not "this session is a VM".
                if ($isGuest) {
                    $hypervisor = 'In-Use (VM)'
                } elseif ($hvPresent) {
                    $hypervisor = 'Enabled'
                } else {
                    $hypervisor = 'Disabled'
                }

                if ($model -match 'Q35') { $chipset = 'Q35' }
                elseif ($model -match 'i440FX') { $chipset = 'i440FX' }
                elseif ($model -match 'ICH9') { $chipset = 'ICH9' }
                elseif ($model -match '440BX') { $chipset = '440BX' }
            } catch { }

            try {
                $cpuObjs = @(Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop)
                if ($cpuObjs.Count -gt 0) {
                    $name = ([string]$cpuObjs[0].Name) -replace '\s+', ' '
                    $name = $name.Trim()
                    $cores = ($cpuObjs | Measure-Object -Property NumberOfCores -Sum).Sum
                    $lps = ($cpuObjs | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
                    if (-not $lps) { $lps = [int]$cs.NumberOfLogicalProcessors }
                    $cpu = $name
                    if ($cores -or $lps) {
                        $cpu = "$name (${cores}c/${lps}t)"
                    }
                }
            } catch { }

            try {
                $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
                $totalKb = [double]$os.TotalVisibleMemorySize
                $freeKb = [double]$os.FreePhysicalMemory
                if ($totalKb -gt 0) {
                    $totalGiB = $totalKb / 1MB
                    $usedGiB = ($totalKb - $freeKb) / 1MB
                    $memory = ('{0:N1} / {1:N1} GB' -f $usedGiB, $totalGiB)
                }
                $cap = [string]$os.Caption
                if ($cap) { $osName = ($cap -replace '^Microsoft\s+', '').Trim() }
                if ($os.LastBootUpTime) {
                    $boot = [datetime]$os.LastBootUpTime
                    $span = (Get-Date) - $boot
                    if ($span.TotalDays -ge 1) {
                        $uptime = '{0}d {1}h' -f [int]$span.TotalDays, $span.Hours
                    } elseif ($span.TotalHours -ge 1) {
                        $uptime = '{0}h {1}m' -f [int]$span.TotalHours, $span.Minutes
                    } else {
                        $uptime = '{0}m' -f [int]$span.TotalMinutes
                    }
                }
            } catch {
                try {
                    if ($cs.TotalPhysicalMemory) {
                        $totalGiB = [double]$cs.TotalPhysicalMemory / 1GB
                        $memory = ('{0:N1} GB' -f $totalGiB)
                    }
                } catch { }
            }

            try {
                $gpus = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop)
                $names = foreach ($g in $gpus) {
                    $n = ([string]$g.Name).Trim()
                    if (-not $n) { continue }
                    if ($n -match 'Microsoft Basic Display|DameWare|Mirror Driver') { continue }
                    $n
                }
                $names = @($names | Select-Object -Unique)
                if ($names.Count) { $gpu = $names -join ', ' }
            } catch { }
        }

        [pscustomobject]@{
            Machine        = $machinePart
            User           = $accountPart
            HostName       = $hostName
            FullName       = $userName
            Role           = $role
            RoleLabel      = $roleLabel
            DisplayRole    = $(if ($role -eq 'ADMIN_AVAILABLE') { 'USER' } else { $roleLabel })
            IsElevated     = $isElevated
            CanElevate     = $canElevate
            AdminAttribute = $adminAttr
            Integrity      = $integrity
            Environment    = $envGuess
            GitBranch      = $gitBranch
            GitDirty       = $gitDirty
            Session        = $session
            IsPSSession    = $isPSSession
            Mux            = $mux
            MuxSession     = $muxSession
            MuxOnDefault   = $muxOnDefault
            Container      = $container
            Cloud          = $cloud
            Virt           = $virt
            IsGuest        = $isGuest
            Hypervisor     = $hypervisor
            Vendor         = $vendor
            MachineModel   = $machineModel
            Chipset        = $chipset
            Cpu            = $cpu
            Gpu            = $gpu
            Memory         = $memory
            OS             = $osName
            Uptime         = $uptime
            Cwd            = $cwd
            RiskLevel      = $risk
            Warnings       = $warnings
            Is64Bit        = [Environment]::Is64BitProcess
            PSEdition      = [string]$PSVersionTable.PSEdition
            PSVersion      = $PSVersionTable.PSVersion.ToString()
            Version        = $WhatAmiVersion
        }
    }

    function Write-WhatAmiColored {
        param($ctx)

        $useColor = -not $Plain -and -not $NoColor

        function C([ConsoleColor]$fg, [string]$text) {
            if (-not $useColor) {
                Write-Host $text -NoNewline
            } else {
                Write-Host $text -NoNewline -ForegroundColor $fg
            }
        }

        C Cyan $ctx.Machine
        Write-Host '\' -NoNewline
        C Green $ctx.User
        Write-Host '  [' -NoNewline

        switch ($ctx.Role) {
            'SYSTEM' { C Red $ctx.DisplayRole }
            'ADMIN'  { C Red $ctx.DisplayRole }
            'ADMIN_AVAILABLE' { C DarkYellow $ctx.DisplayRole }
            default  { C DarkGray $ctx.DisplayRole }
        }
        Write-Host ']' -NoNewline

        if ($useColor) {
            Write-Host "  $($ctx.Environment)" -NoNewline -ForegroundColor DarkCyan
        } else {
            Write-Host "  $($ctx.Environment)" -NoNewline
        }

        if ($ctx.GitBranch) {
            $branchText = $ctx.GitBranch
            if ($ctx.GitDirty) { $branchText += '*' }
            Write-Host '  git:' -NoNewline -ForegroundColor DarkGray
            $branchColor = if ($ctx.GitBranch -match '^(main|master)$') { [ConsoleColor]::DarkYellow } else { [ConsoleColor]::DarkGreen }
            C $branchColor $branchText
        }

        if ($ctx.Session -ne 'console') {
            Write-Host "  $($ctx.Session)" -NoNewline -ForegroundColor Magenta
        }
        if ($ctx.IsPSSession -and $ctx.Session -ne 'PSSession') {
            Write-Host '  PSSession' -NoNewline -ForegroundColor Magenta
        }

        if ($ctx.Mux -and ($ctx.MuxOnDefault -or $Details)) {
            $muxText = $ctx.Mux
            if ($ctx.MuxSession) { $muxText = "$($ctx.Mux):$($ctx.MuxSession)" }
            Write-Host "  $muxText" -NoNewline -ForegroundColor DarkMagenta
        }

        if ($ctx.Container) {
            Write-Host "  $($ctx.Container)" -NoNewline -ForegroundColor DarkBlue
        }

        Write-Host ''

        if (-not $Details) { return }

        Write-Host ''
        Write-Host 'Details' -ForegroundColor White
        $rows = @(
            @{ K = 'Account';     V = $ctx.FullName }
            @{ K = 'HostName';    V = $ctx.HostName }
            @{ K = 'Role';        V = $ctx.RoleLabel }
            @{ K = 'Elevated';    V = $ctx.IsElevated }
            @{ K = 'CanElevate';  V = $ctx.CanElevate }
            @{ K = 'Integrity';   V = $ctx.Integrity }
            @{ K = 'Environment'; V = $ctx.Environment }
            @{ K = 'Session';     V = $ctx.Session }
            @{ K = 'PSSession';   V = $ctx.IsPSSession }
            @{ K = 'Mux';         V = $(if ($ctx.MuxSession) { "$($ctx.Mux) ($($ctx.MuxSession))" } else { $ctx.Mux }) }
            @{ K = 'Git';         V = $(if ($ctx.GitBranch) { "$( $ctx.GitBranch )$( if ($ctx.GitDirty) { ' (dirty)' } )" } else { $null }) }
            @{ K = 'Container';   V = $ctx.Container }
            @{ K = 'Cloud';       V = $(if ($ctx.Cloud -and $ctx.Cloud.Count) { $ctx.Cloud -join ', ' } else { $null }) }
            @{ K = 'OS';          V = $ctx.OS }
            @{ K = 'Uptime';      V = $ctx.Uptime }
            @{ K = 'Virt';        V = $ctx.Virt }
            @{ K = 'Hypervisor';  V = $ctx.Hypervisor }
            @{ K = 'Vendor';      V = $ctx.Vendor }
            @{ K = 'Board';       V = $(
                $parts = @()
                if ($ctx.Chipset) { $parts += $ctx.Chipset }
                if ($ctx.MachineModel) { $parts += $ctx.MachineModel }
                if ($parts.Count) { $parts -join ' — ' } else { $null }
            ) }
            @{ K = 'CPU';         V = $ctx.Cpu }
            @{ K = 'GPU';         V = $ctx.Gpu }
            @{ K = 'Memory';      V = $ctx.Memory }
            @{ K = 'Cwd';         V = $ctx.Cwd }
            @{ K = 'Risk';        V = $ctx.RiskLevel }
            @{ K = 'Warnings';    V = $(if ($ctx.Warnings -and $ctx.Warnings.Count) { $ctx.Warnings -join ', ' } else { $null }) }
            @{ K = 'PowerShell';  V = "$($ctx.PSEdition) $($ctx.PSVersion) $(if ($ctx.Is64Bit) { 'x64' } else { 'x86' })" }
            @{ K = 'whatami';     V = $ctx.Version }
        )
        foreach ($r in $rows) {
            if ($null -eq $r.V -or $r.V -eq '') { continue }
            Write-Host ('  {0,-12}' -f $r.K) -NoNewline -ForegroundColor DarkGray
            Write-Host $r.V
        }

        if ($ctx.Role -eq 'ADMIN') {
            Write-Host '  Elevated token. Destructive commands will succeed.' -ForegroundColor DarkYellow
        } elseif ($ctx.Role -eq 'ADMIN_AVAILABLE') {
            Write-Host '  Not elevated. Account is in Administrators and can UAC-elevate.' -ForegroundColor DarkYellow
        }
        if ($ctx.Environment -eq 'production') {
            Write-Host '  Hostname or path looks like production.' -ForegroundColor DarkYellow
        }
        if ($ctx.GitBranch -match '^(main|master)$') {
            Write-Host "  On $($ctx.GitBranch)." -ForegroundColor DarkYellow
        }
    }

    $ctx = Get-WhatAmiContext

    if ($Json) {
        $ctx | ConvertTo-Json -Compress:$false
        return
    }

    if ($Plain) {
        $bits = @("$($ctx.FullName)", $ctx.DisplayRole, $ctx.Environment)
        if ($Details -and $ctx.Role -eq 'ADMIN_AVAILABLE') {
            $bits[1] = $ctx.RoleLabel
        }
        if ($ctx.GitBranch) {
            $g = $ctx.GitBranch
            if ($ctx.GitDirty) { $g += '*' }
            $bits += "git:$g"
        }
        if ($ctx.Session -ne 'console') { $bits += $ctx.Session }
        if ($ctx.IsPSSession -and $ctx.Session -ne 'PSSession') { $bits += 'PSSession' }
        if ($ctx.Mux -and ($ctx.MuxOnDefault -or $Details)) {
            $bits += $(if ($ctx.MuxSession) { "$($ctx.Mux):$($ctx.MuxSession)" } else { $ctx.Mux })
        }
        if ($ctx.Container) { $bits += $ctx.Container }
        Write-Output ($bits -join ' ')
        if ($Details) {
            Write-Output ("role=$($ctx.RoleLabel) elevated=$($ctx.IsElevated) canElevate=$($ctx.CanElevate) integrity=$($ctx.Integrity) risk=$($ctx.RiskLevel)")
        }
        return
    }

    Write-WhatAmiColored $ctx
}
