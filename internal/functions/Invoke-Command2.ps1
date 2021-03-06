﻿function Invoke-Command2 {
    <#
    .SYNOPSIS
        Wrapper function that calls Invoke-Command and gracefully handles credentials.

    .DESCRIPTION
        Wrapper function that calls Invoke-Command and gracefully handles credentials.

    .PARAMETER ComputerName
        Default: $env:COMPUTERNAME
        The computer to invoke the scriptblock on.

    .PARAMETER Credential
        The credentials to use.
        Can accept $null on older PowerShell versions, since it expects type object, not PSCredential

    .PARAMETER ScriptBlock
        The code to run on the targeted system

    .PARAMETER ArgumentList
        Any arguments to pass to the scriptblock being run

    .PARAMETER Raw
        Passes through the raw return data, rather than prettifying stuff.

    .EXAMPLE
        PS C:\> Invoke-Command2 -ComputerName sql2014 -Credential $Credential -ScriptBlock { dir }

        Executes the scriptblock '{ dir }' on the computer sql2014 using the credentials stored in $Credential.
        If $Credential is null, no harm done.
#>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUsePSCredentialType", "")]
    param (
        [DbaInstanceParameter]$ComputerName = $env:COMPUTERNAME,
        [object]$Credential,
        [scriptblock]$ScriptBlock,
        [object[]]$ArgumentList,
        [switch]$Raw
    )
    
    $InvokeCommandSplat = @{
        ScriptBlock  = $ScriptBlock
    }
    if ($ArgumentList) { $InvokeCommandSplat["ArgumentList"] = $ArgumentList }
    if (-not $ComputerName.IsLocalhost) {
        $runspaceid = [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace.InstanceId
        $sessionname = "dbatools_$runspaceid"
        
        # Retrieve a session from the session cache, if available (it's unique per runspace)
        if (-not ($currentsession = [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::PSSessionGet($runspaceid, $ComputerName.ComputerName) | Where-Object State -Match "Opened|Disconnected")) {
            $timeout = New-PSSessionOption -IdleTimeout (New-TimeSpan -Minutes 10).TotalMilliSeconds
            if ($Credential) {
                $InvokeCommandSplat["Session"] = (New-PSSession -ComputerName $ComputerName.ComputerName -Name $sessionname -SessionOption $timeout -Credential $Credential -ErrorAction Stop)
            }
            else {
                $InvokeCommandSplat["Session"] = (New-PSSession -ComputerName $ComputerName.ComputerName -Name $sessionname -SessionOption $timeout -ErrorAction Stop)
            }
            $currentsession = $InvokeCommandSplat["Session"]
        }
        else {
            if ($currentsession.State -eq "Disconnected") {
                $null = $currentsession | Connect-PSSession -ErrorAction Stop
            }
            $InvokeCommandSplat["Session"] = $currentsession
            
            # Refresh the session registration if registered, to reset countdown until purge
            [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::PSSessionSet($runspaceid, $ComputerName.ComputerName, $currentsession)
        }
    }
    
    if ($Raw) { Invoke-Command @InvokeCommandSplat }
    else { Invoke-Command @InvokeCommandSplat | Select-Object -Property * -ExcludeProperty PSComputerName, RunspaceId, PSShowComputerName }
    
    if (-not $ComputerName.IsLocalhost) {
        # Tell the system to clean up if the session expires
        [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::PSSessionSet($runspaceid, $ComputerName.ComputerName, $currentsession)
        
        if (-not (Get-DbaConfigValue -FullName 'PSRemoting.Sessions.Enable' -Fallback $true)) {
            $currentsession | Remove-PSSession
        }
    }
}