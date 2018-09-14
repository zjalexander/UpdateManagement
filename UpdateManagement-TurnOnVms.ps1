<#
.SYNOPSIS
 Start VMs as part of an Update Management deployment

.DESCRIPTION
  This script is intended to be run as a part of Update Management Pre/Post scripts. 
  It requires a RunAs account.
  This script will ensure all Azure VMs in the Update Deployment are running so they recieve updates.
  This script will store the names of machines that were started in an Automation variable so only those machines
  are turned back off when the deployment is finished (UpdateManagement-TurnOffVMs.ps1)

.PARAMETER SoftwareUpdateConfigurationRunContext
  This is a system variable which is automatically passed in by Update Management during a deployment.
 
 .PARAMETER ResourceGroup
  The resource group of the Automation account. This is used to store progress. 

.PARAMETER AutomationAccount
  The name of the Automation account. This is used to store progress. 
#>

param(
    [string]$SoftwareUpdateConfigurationRunContext,
    [parameter(Mandatory=$true)] [string]$ResourceGroup,
    [parameter(Mandatory=$true)] [string]$AutomationAccount
)

#If you wish to use the run context, it must be converted from JSON
$context = ConvertFrom-Json  $SoftwareUpdateConfigurationRunContext
$vmIds = $context.SoftwareUpdateConfigurationSettings.AzureVirtualMachines
$runId = "PrescriptContext" + $context.SoftwareUpdateConfigurationRunId

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

#This is used to store the state of VMs
New-AzureRmAutomationVariable -ResourceGroupName $ResourceGroup –AutomationAccountName $AutomationAccount –Name $runId -Value "" –Encrypted $false

$updatedMachines = @()
$startableStates = "stopped" , "stopping", "deallocated", "deallocating"

#TODO: Fire off all Start commands in parallel
#Parse the list of VMs and start those which are stopped
#Azure VMs are expressed by:
# subscription/$subscriptionID/resourcegroups/$resourceGroup/providers/microsoft.compute/virtualmachines/$name
$vmIds | ForEach-Object {
    $vmId =  $_
    
    $split = $vmId -split "/";
    $subscriptionId = $split[2]; 
    $rg = $split[4];
    $name = $split[8];
    Write-Output ("Subscription Id: " + $subscriptionId)
    $mute = Select-AzureRmSubscription -Subscription $subscriptionId

    $vm = Get-AzureRmVM -ResourceGroupName $rg -Name $name -Status 

    #Query the state of the VM to see if it's already running or if it's already started
    $state = ($vm.Statuses[1].DisplayStatus -split " ")[1]
    if($state -in $startableStates) {
        Write-Output "Starting '$($name)' ..."
        #Store the VM we started so we remember to shut it down later
        $updatedMachines += $vmId
        Start-AzureRmVM -ResourceGroupName $rg -Name $name -AsJob
    }else {
        Write-Output ($name + ": no action taken. State: " + $state) 
    }
}

$updatedMachinesCommaSeperated = $updatedMachines -join ","
#Wait until all machines have finished starting before proceeding to the Update Deployment
Write-Output "Waiting for machines to finish starting..."
Get-Job | Wait-Job
Write-output $updatedMachinesCommaSeperated
#Store output in the automation variable
Set-AutomationVariable –Name $runId -Value $updatedMachinesCommaSeperated
