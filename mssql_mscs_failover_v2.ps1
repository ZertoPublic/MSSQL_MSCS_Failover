<#
Legal Disclaimer
This script is an example script and is not supported under any Zerto support program or service. The author and Zerto further disclaim all implied warranties including, without limitation, any implied warranties of merchantability or of fitness for a particular purpose.

In no event shall Zerto, its authors or anyone else involved in the creation, production or delivery of the scripts be liable for any damages whatsoever (including, without limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary loss) arising out of the use of or the inability to use the sample scripts or documentation, even if the author or Zerto has been advised of the possibility of such damages. The entire risk arising out of the use or performance of the sample scripts and documentation remains with you.
#>

#Requires -Modules Zerto.ZVM.Commandlets

[CmdletBinding()]
param (
    [Parameter()]
    [String]
    $activeNode = "" # Optional flag used for testing the Zerto parts manually (comment out the two lines below starting with $OwnerNode= and $activeNode= first)
)

Import-Module Failoverclusters, Zerto.ZVM.Commandlets

# Variables you need to modify

$SQLClusterName = ""
$SQLNode1Name = ""
$SQLNode2Name = ""

$ZertoVPG_SQLNode1 = ""
$ZertoVPG_SQLNode2 = ""

$SourceZVMaddress = ""
$SourceZVMport = 9669

$ZVMuser = ""
$ZVMpass = ""

# Script Logic follows - make sure you understand, but no need to modify

# Connect to Zerto

$Credentials = New-Object -TypeName PSCredential -argumentlist $ZVMuser, (ConvertTo-SecureString -asplaintext $ZVMpass)

Connect-ZVM -HostName $SourceZVMaddress -Port $SourceZVMport -Credential $Credentials

# Grab the info on the relevant VPGs

$vpg1 = Get-ZvmVpg -VpgName $ZertoVPG_SQLNode1 | select VpgIdentifier, VpgName, Status, SubStatus
$vpg2 = Get-ZvmVpg -VpgName $ZertoVPG_SQLNode2 | select VpgIdentifier, VpgName, Status, SubStatus

Write-Host "node1: "  $SQLNode1Name  " vpg1: "  $vpg1.VpgName  " substatus: "  $vpg1.substatus
Write-Host "node2: "  $SQLNode2Name  " vpg2: "  $vpg2.VpgName  " substatus: "  $vpg2.substatus
Write-Host "active node: "  $activeNode

# Get the information from SQL on the active node

$OwnerNode = (get-clustergroup -name $SQLClusterName | select -expandproperty OwnerNode)
$activeNode = ($OwnerNode | select -expandproperty Name)

if ($activeNode -eq $SQLNode1Name)
{
    # Enable Node1, Pause Node2

    if ($vpg1.SubStatus -eq 'ReplicationPausedUserInitiated') 
    {
        Write-Host "Resuming " $vpg1.VpgName
        Start-ZvmVpgResume -VpgId $vpg1.VpgIdentifier
        Start-Sleep 10
        Write-Host "Force Syncing"
        Start-ZvmVpgForceSync -VpgId $vpg1.VpgIdentifier
    }

    if ($vpg2.SubStatus -ne 'ReplicationPausedUserInitiated') 
    {
        Write-Host "Pausing " $vpg2.VpgName
        Start-ZvmVpgPause -VpgId $vpg2.VpgIdentifier
    }
}
elseif ($activeNode -eq $SQLNode2Name)
{
    # Enable Node2, Pause Node1

    if ($vpg2.SubStatus -eq 'ReplicationPausedUserInitiated')
    {
        Write-Host "Resuming " $vpg2.VpgName
        Start-ZvmVpgResume -VpgId $vpg2.VpgIdentifier
        Start-Sleep 10
        Write-Host "Force Syncing"
        Start-ZvmVpgForceSync -VpgId $vpg2.VpgIdentifier
    }

    if ($vpg1.SubStatus -ne 'ReplicationPausedUserInitiated') 
    {
        Write-Host "Pausing " $vpg1.VpgName
        Start-ZvmVpgPause -VpgId $vpg1.VpgIdentifier
    }
}
else 
{
    Write-Error "Active Node does not match either SQL Node, please check script variables."    
}


# Done

Write-Host "Disconnecting"

Disconnect-Zvm
