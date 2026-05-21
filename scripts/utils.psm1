#Requires -Version 5.1
Set-StrictMode -Version 3.0

function Initialize-ExternalRuntimeData {
    <#
    .SYNOPSIS
        Initialize external runtime data before installation
    .PARAMETER Source
        The source path, which is the persist runtime data path
    .PARAMETER Target
        The target path, which is the actual path app uses to access the runtime data
    #>
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
        Move-Item -Path $Target -Destination $Source -ErrorAction SilentlyContinue
    } else {
        Remove-Item -Path $Target -Recurse -ErrorAction SilentlyContinue
    }
}

function Mount-ExternalRuntimeData {
    <#
    .SYNOPSIS
        Mount external runtime data

    .PARAMETER Source
        The source path, which is the persist_dir

    .PARAMETER Target
        The target path, which is the actual path app uses to access the runtime data
    #>
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
    <#
    .SYNOPSIS
        Unmount external runtime data

    .PARAMETER Target
        The target path, which is the actual path app uses to access the runtime data
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $Target
    )

    if (Test-Path $Target) {
        Remove-Item $Target -Force -Recurse
    }
}

Export-ModuleMember `
    -Function `
    Initialize-ExternalRuntimeData, Mount-ExternalRuntimeData, Dismount-ExternalRuntimeData
