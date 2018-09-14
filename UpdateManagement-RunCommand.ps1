<#
.SYNOPSIS
 Stop a service on an AzureRM using RunCommand

.DESCRIPTION
  This script is intended to be run as a part of Update Management Pre/Post scripts. 
  It uses RunCommand to execute a PowerShell script to stop a service

.PARAMETER SoftwareUpdateConfigurationRunContext
  This is a system variable which is automatically passed in by Update Management during a deployment.
#>

param(
    [string]$SoftwareUpdateConfigurationRunContext
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
$vmIds = $context.SoftwareUpdateConfigurationSettings.AzureVirtualMachines
$runId = $context.SoftwareUpdateConfigurationRunId

#The script you wish to run on each VM
$scriptBlock = @"
Stop-Service -Name "AudioSvc"
"@

#The cmdlet only accepts a file, so temporarily write the script to disk using runID as a unique name
Out-File -FilePath "$runID.ps1" -InputObject $scriptBlock

#Start script on each machine
$vmIds | ForEach-Object {
    $vmId =  $_
    
    $split = $vmId -split "/";
    $subscriptionId = $split[2]; 
    $rg = $split[4];
    $name = $split[8];
    Write-Output ("Subscription Id: " + $subscriptionId)
    $mute = Select-AzureRmSubscription -Subscription $subscriptionId
    Write-Output "Invoking command on '$($name)' ..."
    Invoke-AzureRmVMRunCommand -ResourceGroupName $rg -Name $name -CommandId 'RunPowerShellScript' -ScriptPath "$runID.ps1" -AsJob
}

Write-Output "Waiting for machines to finish executing..."
Get-Job | Wait-Job
#Clean up our variables:
Remove-Item -Path "$runID.ps1"