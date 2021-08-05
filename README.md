# Legal Disclaimer
This script is an example script and is not supported under any Zerto support program or service. The author and Zerto further disclaim all implied warranties including, without limitation, any implied warranties of merchantability or of fitness for a particular purpose.

In no event shall Zerto, its authors or anyone else involved in the creation, production or delivery of the scripts be liable for any damages whatsoever (including, without limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary loss) arising out of the use of or the inability to use the sample scripts or documentation, even if the author or Zerto has been advised of the possibility of such damages. The entire risk arising out of the use or performance of the sample scripts and documentation remains with you.

# Automating protection for MSSQL MSCS Clusters when role owner changes
This script is designed for MSSQL MSCS clusters using shared RDMs where both the active and passive nodes are protected in their own VPGs. The active node VPG replicating while the passive node VPG is paused. When the Active node changes this script will alter the replicating/paused VPGs

# Getting Started
The first step to utilizing this script is to create two VPGs. One protecting the current active node only and a second protecting the current passive node only. 

The script should then be scheduled to be run directly on both SQL nodes every 1 minute. Its purpose is to check the active SQL node is the node protected by Zerto and automatically perform a force-sync if this is ever changed. The script will pause the VPG if the database is in an inconsistent state to clearly indicate the VPG can no longer be failed over until a force-sync has been performed. 

# Prerequisites
## Environment Requirements:

- PowerCLI 5.5+
- PowerShell 5.0+
- ZVR 6.0u2
- Failoverclusters PowerShell Module

- v2 script - requires Zerto.ZVM.Commandlets module from Powershell Gallery, which requires Powershell 6.1+

## In-Script Variables:

- Cluster Node 1 Name
- VPG name for Node 1
- Cluster Node 2 Name
- VPG name for Node 2
- Clustered SQL Instance Name
- ZVM IP
- ZVM User / Password

# Running Script
Once the necessary requirements have been completed select an appropriate host to run the script from. To run the script type the following from the directory the script is located in:

.\MSSQL_MSCS_Failover.ps1

v2 script - .\mssql_mscs_failover_v2.ps1
