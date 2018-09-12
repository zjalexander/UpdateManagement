<#
.SYNOPSIS
 Stop a service on a machine using a hybrid worker

.DESCRIPTION
  This script is intended to be run as a part of Update Management Pre/Post scripts. 
  It requires hybrid workers to be configured on the machines which need to run scripts locally.

.PARAMETER HybridWorkerGroups
  An array of hybrid worker groups which should run another runbook from a local context.
  To guarantee execution on the right machine, each hybrid worker group should contain only one machine.

.PARAMETER SoftwareUpdateConfigurationRunContext
  This is a system variable which is automatically passed in by Update Management during a deployment.

.PARAMETER ResourceGroup
  The resource group of the Automation account with the child job. 

.PARAMETER AutomationAccount
  The name of the Automation account with the child job. 
#>

param(
    [parameter(Mandatory=$true)] [string[]]$HybridWorkerGroups,
    [string]$SoftwareUpdateConfigurationRunContext,
    [parameter(Mandatory=$true)] [string]$ResourceGroup,
    [parameter(Mandatory=$true)] [string]$AutomationAccount 
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

$runStatus = New-Object System.Collections.Generic.List[System.Object]
$finalStatus = New-Object System.Collections.Generic.List[System.Object]

#If you wish to use the run context, it must be converted from JSON
$context = ConvertFrom-Json  $SoftwareUpdateConfigurationRunContext



#Start script on each machine
foreach($machine in $HybridWorkerGroups)
{
    $output = Start-AzureRmAutomationRunbook -Name "StartService" -ResourceGroupName $ResourceGroup  -AutomationAccountName $AutomationAccount -RunOn $machine
    $runStatus.Add($output)
}

#Determine status of all runs. 

foreach($job in $runStatus)
{
    #First, wait for each job to complete
    $currentStatus = Get-AzureRmAutomationJob -Id $job.jobid -ResourceGroupName $ResourceGroup  -AutomationAccountName $AutomationAccount
    while ($currentStatus.status -ne "Completed")
        {
            Start-Sleep -Seconds 5
            $currentStatus = Get-AzureRmAutomationJob -Id $job.jobid -ResourceGroupName $ResourceGroup  -AutomationAccountName $AutomationAccount
        }
    #Then, store the summary
    $summary = Get-AzureRmAutomationJobOutput -Id $job.jobid -ResourceGroupName $ResourceGroup  -AutomationAccountName $AutomationAccount
    $finalStatus.Add($summary)
}
#In this case, we want to terminate the patch job if any run fails.
#This logic might not hold for all cases - you might want to allow success as long as at least 1 run succeeds
foreach($summary in $finalStatus)
{
    if ($summary.Type -eq "Error")
    {
        #We must throw in order to fail the patch deployment. 
        throw $summary.Summary
    }
}
