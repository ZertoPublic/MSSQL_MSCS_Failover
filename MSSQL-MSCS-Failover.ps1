#requires -RunAsAdministrator
<#
.SYNOPSIS
This script is designed to automate the protection of the Active SQL cluster node by Zerto in the event a role changes owner.
.DESCRIPTION
This script is designed for MSCS clusters using shared RDMs where both the active and passive nodes are protected in their own VPGs. The active node VPG replicating while the passive node VPG is paused. When the Active node changes this script will alter the replicating/paused VPGs
For failover testing a SQL cluster node VPG you need to have active directory running in the same isolated network with both DNS/GC services set as the primary or secondary DNS on the protected cluster node. You cannot test failover MSCS without AD being online at least 5 minutes in advance in the isolated test network.
It is therefore recommended to have a local AD server to the MSCS cluster in a VPG, separate to the MSCS VPG for best practice, replicating to the recovery site for failover testing.
If you are failing over to a remote site with a separate IP subnet then it is recommended to replicate a local AD server in the target site between 2 hosts (enabled with the replicate to self option in advanced Zerto settings) so you can easily bring a copy of AD online in the test failover network to simulate real failover of MSCS.
.EXAMPLE
Examples of script execution
.VERSION
Applicable versions of Zerto Products script has been tested on. Unless specified, all scripts in repository will be 5.0u3 and later. If you have tested the script on multiple
versions of the Zerto product, specify them here. If this script is for a specific version or previous version of a Zerto product, note that here and specify that version
in the script filename. If possible, note the changes required for that specific version.
.LEGAL
Legal Disclaimer:
 
----------------------
This script is an example script and is not supported under any Zerto support program or service.
The author and Zerto further disclaim all implied warranties including, without limitation, any implied warranties of merchantability or of fitness for a particular purpose.
 
In no event shall Zerto, its authors or anyone else involved in the creation, production or delivery of the scripts be liable for any damages whatsoever (including, without
limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary loss) arising out of the use of or the inability
to use the sample scripts or documentation, even if the author or Zerto has been advised of the possibility of such damages. The entire risk arising out of the use or
performance of the sample scripts and documentation remains with you.
----------------------
#>

#Adds the Windows Failover Cluster commands

Import-Module Failoverclusters

################################################
# Setting Cert Policy - required for successful auth with the Zerto API without connecting to vsphere using PowerCLI
################################################
add-type @"
 using System.Net;
 using System.Security.Cryptography.X509Certificates;
 public class TrustAllCertsPolicy : ICertificatePolicy {
 public bool CheckValidationResult(
 ServicePoint srvPoint, X509Certificate certificate,
 WebRequest request, int certificateProblem) {
 return true;
 }
 }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy


##PowerCLI requires remote signed execution policy - if this is not 
##enabled, it may be enabled here by uncommenting the line below.
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force

#PARAMETERS SECTION

#Configure the below variables first
$node1name = "<Node1>"
$node1vpgname = "<VPG1>"

$node2name = "<Node2>"
$node2vpgname = "<VPG2>"

$sqlclustername = "Sql Server (MSSQLSERVER)" #Clustered SQL Instance Name

$strZVMIP = "<ZVMIP>" #Source site ZVM IP
$zvpPort = "9669"
$strZVMUser = "administrator" 
$strZVMPw = "password"

$BASEURL = "https://" + $strZVMIP + ":"+$zvpPort+"/v1/" #base URL for all APIs

##FUNCTIONS DEFINITIONS

#Authenticates with Zerto's APIs, Creates a Zerto api session and returns it, to be used in other APIs
function getZertoXSession (){
    #Authenticating with Zerto APIs
    $xZertoSessionURI = $BASEURL + "session/add"
    $authInfo = ("{0}:{1}" -f $strZVMUser,$strZVMPw)
    $authInfo = [System.Text.Encoding]::UTF8.GetBytes($authInfo)
    $authInfo = [System.Convert]::ToBase64String($authInfo)
    $headers = @{Authorization=("Basic {0}" -f $authInfo)}
    $xZertoSessionResponse = Invoke-WebRequest -Uri $xZertoSessionURI -Headers $headers -Method POST

    #Extracting x-zerto-session from the response, and adding it to the actual API
    $xZertoSession = $xZertoSessionResponse.headers.get_item("x-zerto-session")
    return $xZertoSession 
}

#Get a vpg identifier by invoking Zerto's APIs given a Zerto API session and a vpg name
function getVpgIdentifierByName ($vpgName){
    $url = $BASEURL + "vpgs"
    $response = Invoke-RestMethod -Uri $url -TimeoutSec 100 -Headers $zertSessionHeader -ContentType "application/json"
	    ForEach ($vpg in $response) {
      if ($vpg.VpgName -eq $vpgName){
            return $vpg.VpgIdentifier
        }
    }
}

#Get a vpg status by invoking Zerto's APIs given a Zerto API session and a vpg name
function CheckVpgStatus ($vpgName){
    # Build List of VPGs
    $url = $BASEURL + "vpgs"
    $response = Invoke-RestMethod -Uri $url -TimeoutSec 100 -Headers $zertSessionHeader -ContentType "application/json"
    # Building VPG array 
    ForEach ($vpg in $response) {
      if ($vpg.VpgName -eq $vpgName){
            $vpgStatus = $vpg.SubStatus                        
        }
    }
    # If statement to set pause status
    if ($vpgStatus -eq "25")
       {
       return $true
       }
    else
       {
       return $false
       }
}

#SCRIPT STARTS HERE - nothing to change beyond here but the logic is explained

$xZertoSession = getZertoXSession

$zertSessionHeader = @{"x-zerto-session"=$xZertoSession}

#Selects the current cluster owner
$getowner = (get-clustergroup -name $sqlclustername | select -expandproperty OwnerNode)
$currentowner = ($getowner | select -expandproperty Name)

#Checks to see if Node 1 is paused
$node1paused = CheckVpgStatus $node1vpgname

#Checks to see if Node 2 is paused
$node2paused = CheckVpgStatus $node2vpgname

#Node 1 checks if node 1 is pasued and the cluster owner
if (($node1paused -eq $True) -And ($currentowner -eq $node1name))
{

#As node 1 is paused but it is now the owner of the cluster it needs to be unpaused and force synced
$vpgIdentifier1 = getVpgIdentifierByName $node1vpgname
$ResumeVPGUrl = $BASEURL + "vpgs/" + $vpgIdentifier1 + "/resume"
Invoke-RestMethod -Uri $ResumeVPGUrl -TimeoutSec 100 -Headers $zertSessionHeader -ContentType "application/json" -method POST
Start-Sleep 10
$CheckpointUrl = $BASEURL + "vpgs/" + $vpgIdentifier1 + "/Checkpoints"
$CheckpointBody = '{ "checkpointName": "NOW Cluster Owner - Auto Force Sync Started" }'
Invoke-RestMethod -Uri $CheckpointUrl -TimeoutSec 100 -Headers $zertSessionHeader -Body $CheckpointBody -ContentType "application/json" -method POST
Start-Sleep 10
$SyncVPGUrl = $BASEURL + "vpgs/" + $vpgIdentifier1 + "/forcesync"
Invoke-RestMethod -Uri $SyncVPGUrl -TimeoutSec 100 -Headers $zertSessionHeader -ContentType "application/json" -method POST
}

#This checks if the node isn't paused and if it isn't the cluster owner
elseif (($node1paused -eq $False) -And ($currentowner -eq $node2name))
{

#As node 1 is not the Owner it pauses its VPG
$vpgIdentifier1 = getVpgIdentifierByName $node1vpgname
$CheckpointUrl = $BASEURL + "vpgs/" + $vpgIdentifier1 + "/Checkpoints"
$CheckpointBody = '{ "checkpointName": "NOT Cluster Owner - Auto Paused" }'
Invoke-RestMethod -Uri $CheckpointUrl -TimeoutSec 100 -Headers $zertSessionHeader -Body $CheckpointBody -ContentType "application/json" -method POST
Start-Sleep 10
$PauseVPGUrl = $BASEURL + "vpgs/" + $vpgIdentifier1 + "/pause"
Invoke-RestMethod -Uri $PauseVPGUrl -TimeoutSec 100 -Headers $zertSessionHeader -ContentType "application/json" -method POST
}

else {write-host "Nothing to do for Node 1"}

#Node 2 checks if node 2 is paused and the cluster owner
if (($node2paused -eq $True ) -and ($currentowner -eq $node2name))
{

#As node 2 is paused but it is now the owner of the cluster it needs to be unpaused and force synced
$vpgIdentifier2 = getVpgIdentifierByName $node2vpgname
$ResumeVPGurl = $BASEURL + "vpgs/" + $vpgIdentifier2 + "/resume"
Invoke-RestMethod -Uri $ResumeVPGUrl -TimeoutSec 100 -Headers $zertSessionHeader -ContentType "application/json" -method POST
Start-Sleep 10
$CheckpointUrl = $BASEURL + "vpgs/" + $vpgIdentifier2 + "/Checkpoints"
$CheckpointBody = '{ "checkpointName": "NOW Cluster Owner - Auto Force Sync Started" }'
Invoke-RestMethod -Uri $CheckpointUrl -TimeoutSec 100 -Headers $zertSessionHeader -Body $CheckpointBody -ContentType "application/json" -method POST
Start-Sleep 10
$SyncVPGUrl = $BASEURL + "vpgs/" + $vpgIdentifier2 + "/forcesync"
Invoke-RestMethod -Uri $SyncVPGUrl -TimeoutSec 100 -Headers $zertSessionHeader -ContentType "application/json" -method POST
}

#This checks if the node isn't paused and if it isn't the cluster owner
elseif (($node2paused -eq $False) -And ($currentowner -eq $node1name))
{

#As node 2 is not the Owner it pauses its VPG
$vpgIdentifier2 = getVpgIdentifierByName $node2vpgname
$CheckpointUrl = $BASEURL + "vpgs/" + $vpgIdentifier2 + "/Checkpoints"
$CheckpointBody = '{ "checkpointName": "NOT Cluster Owner - Auto Paused" }'
Invoke-RestMethod -Uri $CheckpointUrl -TimeoutSec 100 -Headers $zertSessionHeader -Body $CheckpointBody -ContentType "application/json" -method POST
Start-Sleep 10
$PauseVPGUrl = $BASEURL + "vpgs/" + $vpgIdentifier2 + "/pause"
Invoke-RestMethod -Uri $PauseVPGUrl -TimeoutSec 100 -Headers $zertSessionHeader -ContentType "application/json" -method POST
}

else {write-host "Nothing to do for Node 2"}