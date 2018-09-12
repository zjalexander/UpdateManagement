<#
.SYNOPSIS
 Stop VMs that were started as part of an Update Management deployment

.DESCRIPTION
  This script is intended to be run as a part of Update Management Pre/Post scripts. 
  It requires a RunAs account.
  This script will turn off all Azure VMs that were started as part of TurnOnVMs.ps1.
  It retrieves the list of VMs that were started from an Automation Account variable.

.PARAMETER SoftwareUpdateConfigurationRunContext
  This is a system variable which is automatically passed in by Update Management during a deployment.

.PARAMETER ResourceGroup
  The resource group of the Automation account. This is used to store progress. 

.PARAMETER AutomationAccount
  The name of the Automation account. This is used to store progress. 
#>

param(
    [string]$SoftwareUpdateConfigurationRunContext,
    [string]$ResourceGroup,
    [string]$AutomationAccount
)

#region BoilerplateAuthentication
#This requires a RunAs account
$ServicePrincipalConnection = Get-AutomationConnection -Name 'AzureRunAsConnection'

Add-AzureRmAccount `
    -ServicePrincipal `
    -TenantId $ServicePrincipalConnection.TenantId `
    -ApplicationId $ServicePrincipalConnection.ApplicationId `
    -CertificateThumbprint $ServicePrincipalConnection.CertificateThumbprint

$AzureContext = Select-AzureRmSubscription -SubscriptionId $ServicePrincipalConnection.SubscriptionID
#endregion BoilerplateAuthentication

#If you wish to use the run context, it must be converted from JSON
$context = ConvertFrom-Json  $SoftwareUpdateConfigurationRunContext
$runId = $context.SoftwareUpdateConfigurationRunId

#Retrieve the automation variable, which we named using the runID from our run context. 
#See: https://docs.microsoft.com/en-us/azure/automation/automation-variables#activities
$variable = Get-AutomationVariable -Name $runId
$vmIds = $variable -split ","
$stoppableStates = "starting", "running"

#This script can run across subscriptions, so we need unique identifiers for each VMs
#Azure VMs are expressed by:
# subscription/$subscriptionID/resourcegroups/$resourceGroup/proveders/microsoft.compute/virtualmachines/$name
$vmIds | ForEach-Object {
    $vmId =  $_
    
    $split = $vmId -split "/";
    $subscriptionId = $split[2]; 
    $rg = $split[4];
    $name = $split[8];
    Write-Output ("Subscription Id: " + $subscriptionId)
    $mute = Select-AzureRmSubscription -Subscription $subscriptionId

    $vm = Get-AzureRmVM -ResourceGroupName $rg -Name $name -Status 

    $state = ($vm.Statuses[1].DisplayStatus -split " ")[1]
    if($state -in $stoppableStates) {
        Write-Output "Stopping '$($name)' ..."
        Stop-AzureRmVM -ResourceGroupName $rg -Name $name -Force;
    }else {
        Write-Output ($name + " already in a stopping State: " + $state) 
    }
}

#Clean up our variables:
Remove-AzureRmAutomationVariable -AutomationAccountName $aaname -ResourceGroupName $rg -name $runID