<#
.SYNOPSIS
 Stop a service on an AzureRM using RunCommand

.DESCRIPTION
  This script is intended to be run as a part of Update Management Pre/Post scripts. 
  It uses RunCommand to execute a PowerShell script to stop a service

.PARAMETER SoftwareUpdateConfigurationRunContext
  This is a system variable which is automatically passed in by Update Management during a deployment.
#>
#requires -Modules ThreadJob
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

if (!$vmIds) 
{
    #Workaround: Had to change JSON formatting
    $Settings = ConvertFrom-Json $context.SoftwareUpdateConfigurationSettings
    #Write-Output "List of settings: $Settings"
    $VmIds = $Settings.AzureVirtualMachines
    #Write-Output "Azure VMs: $VmIds"
    if (!$vmIds) 
    {
        Write-Output "No Azure VMs found"
        return
    }
}

#The script you wish to run on each VM
$scriptBlock = @"
Stop-Service -Name "AudioSvc"
"@
$scriptPath = "$runID.ps1"
#The cmdlet only accepts a file, so temporarily write the script to disk using runID as a unique name
Out-File -FilePath $scriptPath -InputObject $scriptBlock
$scriptFile = get-item $scriptpath
$fullPath = $scriptfile.fullname

$jobIDs= New-Object System.Collections.Generic.List[System.Object]

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
    $newJob = Start-ThreadJob -ScriptBlock { param($resourceGroup, $vmName, $scriptPath) Invoke-AzureRmVMRunCommand -ResourceGroupName $resourceGroup -Name $VmName -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath} -ArgumentList $rg, $name, $fullPath
    $jobIDs.Add($newJob.Id)
    
}

$jobsList = $jobIDs.ToArray()
if ($jobsList)
{
    Write-Output "Waiting for machines to finish executing..."
    Wait-Job -Id $jobsList
}

foreach($id in $jobsList)
{
    $job = Get-Job -Id $id
    if ($job.Error)
    {
        Write-Output $job.Error
    }

}

#Clean up our variables:
Remove-Item -Path "$runID.ps1"