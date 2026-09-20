#Requires -Version 5.1
Set-StrictMode -Version 3.0

function Initialize-ExternalRuntimeData {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $Source,
        [Parameter(Mandatory = $true, Position = 1)]
        [string] $Target
    )
    if (-not (Test-Path $Source)) {
        New-Item (Split-Path $Source -Parent) -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
        New-Item $Source -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
        if (Test-Path $Target) {
            Get-ChildItem -Path $Target -Force | Move-Item -Destination $Source -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $Target -Recurse -Force -ErrorAction SilentlyContinue
        }
    } else {
        Remove-Item -Path $Target -Recurse -ErrorAction SilentlyContinue
    }
}

function Mount-ExternalRuntimeData {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $Source,
        [Parameter(Mandatory = $true, Position = 1)]
        [string] $Target
    )

    if (Test-Path $Source) {
        Remove-Item $Target -Force -Recurse -ErrorAction SilentlyContinue
    } else {
        New-Item -ItemType Directory $Source -Force | Out-Null
        if (Test-Path $Target) {
            Get-ChildItem $Target | Move-Item -Destination $Source -Force
            Remove-Item $Target
        }
    }

    New-Item -ItemType Junction -Path $Target -Target $Source -Force | Out-Null
}

function Dismount-ExternalRuntimeData {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $Target
    )

    if (Test-Path $Target) {
        Remove-Item $Target -Force -Recurse
    }
}

function Get-ProcessIsForeground {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Process] $Process
    )

    # A GUI application is considered foreground for uninstall purposes whenever
    # it owns a main window. Minimized, maximized, frontmost, and background
    # windows all remain GUI applications and must be closed by the user first.
    try {
        return $Process.MainWindowHandle -ne [IntPtr]::Zero
    } catch {
        return $false
    }
}

function Stop-RunningApplication {
    <#
    .SYNOPSIS
        Reject foreground applications and stop matching background processes.

    .DESCRIPTION
        This is deliberately application-specific. It does not suspend threads and
        it does not guess a process tree. A foreground match is rejected before any
        process is stopped. Every stop operation is verified; any failure throws.
        When StatePath is supplied, a JSON record is written for post_install or
        an external wrapper to consume.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]] $ProcessName,
        [string[]] $ServiceName,
        [string] $StatePath,
        [int] $WaitSeconds = 20
    )

    $names = @($ProcessName | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) } | Where-Object { $_ })
    $services = @($ServiceName | Where-Object { $_ } | ForEach-Object { Get-Service -Name $_ -ErrorAction SilentlyContinue })
    $runningServices = @($services | Where-Object { $_.Status -eq 'Running' })
    $running = @(Get-Process -Name $names -ErrorAction SilentlyContinue)
    $state = [ordered]@{
        WasRunning = ($running.Count -gt 0 -or $runningServices.Count -gt 0)
        Stopped = $false
        ServiceNames = @($runningServices | ForEach-Object { $_.Name })
        ProcessIds = @($running | ForEach-Object { $_.Id })
        ProcessNames = @($running | ForEach-Object { $_.ProcessName })
        Timestamp = (Get-Date).ToString('o')
    }

    if ($running.Count -eq 0 -and $runningServices.Count -eq 0) {
        if ($StatePath) {
            $parent = Split-Path -Parent $StatePath
            if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            $state | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $StatePath -Encoding UTF8
        }
        return $false
    }

    $foreground = @($running | Where-Object {
        try { Get-ProcessIsForeground -Process $_ } catch { $false }
    })
    if ($foreground.Count -gt 0) {
        $names = [string]::Join(', ', @($foreground | ForEach-Object { "$($_.ProcessName) (PID $($_.Id))" }))
        throw "Foreground application detected: $names. Close it manually before continuing."
    }

    foreach ($service in $runningServices) {
        try {
            Stop-Service -Name $service.Name -Force -ErrorAction Stop
        } catch {
            throw "Failed to stop service $($service.Name): $($_.Exception.Message)"
        }
    }

    foreach ($process in $running) {
        # Stopping a Windows service can terminate its host process before the
        # process loop is reached. Re-check the PID to avoid treating that
        # expected race as a stop failure.
        $currentProcess = Get-Process -Id $process.Id -ErrorAction SilentlyContinue
        if ($null -eq $currentProcess) {
            continue
        }
        try {
            Stop-Process -Id $currentProcess.Id -Force -ErrorAction Stop
        } catch {
            throw "Failed to stop $($currentProcess.ProcessName) (PID $($currentProcess.Id)): $($_.Exception.Message)"
        }
    }

    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    do {
        Start-Sleep -Milliseconds 250
        $remaining = @(Get-Process -Name $names -ErrorAction SilentlyContinue | Where-Object {
            $state.ProcessIds -contains $_.Id
        })
        $remainingServices = @($ServiceName | Where-Object { $_ } | ForEach-Object {
            Get-Service -Name $_ -ErrorAction SilentlyContinue
        } | Where-Object { $_.Status -eq 'Running' })
    } while (($remaining.Count -gt 0 -or $remainingServices.Count -gt 0) -and (Get-Date) -lt $deadline)

    if ($remaining.Count -gt 0) {
        $names = [string]::Join(', ', @($remaining | ForEach-Object { "$($_.ProcessName) (PID $($_.Id))" }))
        throw "Failed to stop process(es): $names"
    }
    if ($remainingServices.Count -gt 0) {
        $names = [string]::Join(', ', @($remainingServices | ForEach-Object { $_.Name }))
        throw "Failed to stop service(s): $names"
    }

    $state.Stopped = $true
    if ($StatePath) {
        $parent = Split-Path -Parent $StatePath
        if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        $state | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $StatePath -Encoding UTF8
    }
    return $true
}

Export-ModuleMember `
    -Function `
    Initialize-ExternalRuntimeData, Mount-ExternalRuntimeData, Dismount-ExternalRuntimeData, Get-ProcessIsForeground, Stop-RunningApplication
