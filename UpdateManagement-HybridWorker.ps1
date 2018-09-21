
<#PSScriptInfo

.VERSION 1.0

.GUID b5eb0470-89af-4302-8200-144d19c454a8

.AUTHOR zachal

.COMPANYNAME Microsoft

.COPYRIGHT 

.TAGS UpdateManagement, Automation

.LICENSEURI 

.PROJECTURI 

.ICONURI 

.EXTERNALMODULEDEPENDENCIES 

.REQUIREDSCRIPTS 

.EXTERNALSCRIPTDEPENDENCIES 

.RELEASENOTES


.PRIVATEDATA 

#>

<# 

.DESCRIPTION 
 This script is intended to be run as a part of Update Management Pre/Post scripts. 
 It requires hybrid workers to be configured on the machines which need to run scripts locally.
 Runs a child Automation Runbook on a hybrid worker

#> 


<#
.SYNOPSIS
 Runs a child Automation Runbook on a hybrid worker

.DESCRIPTION
  This script is intended to be run as a part of Update Management Pre/Post scripts. 
  It requires hybrid workers to be configured on the machines which need to run scripts locally.

.PARAMETER RunbookName
  The name of the Azure Automation runbook you wish to execute on the hybrid workers in a local context
  
.PARAMETER HybridWorkerGroups
  A hybrid worker group which should run another runbook from a local context.
  To guarantee execution on the right machine, each hybrid worker group should contain only one machine.
  KNOWN ISSUE: Pre/Post scripts will not accept arrays or objects as arguments. 

.PARAMETER SoftwareUpdateConfigurationRunContext
  This is a system variable which is automatically passed in by Update Management during a deployment.

#>

param(
    [parameter(Mandatory=$true)] [string]$RunbookName,
    [parameter(Mandatory=$true)] [string]$HybridWorkerGroups,
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

$runStatus = New-Object System.Collections.Generic.List[System.Object]
$finalStatus = New-Object System.Collections.Generic.List[System.Object]

#If you wish to use the run context, it must be converted from JSON
$context = ConvertFrom-Json  $SoftwareUpdateConfigurationRunContext

#https://github.com/azureautomation/runbooks/blob/master/Utility/ARM/Find-WhoAmI
# In order to prevent asking for an Automation Account name and the resource group of that AA,
# search through all the automation accounts in the subscription 
# to find the one with a job which matches our job ID
$AutomationResource = Get-AzureRmResource -ResourceType Microsoft.Automation/AutomationAccounts

foreach ($Automation in $AutomationResource)
{
    $Job = Get-AzureRmAutomationJob -ResourceGroupName $Automation.ResourceGroupName -AutomationAccountName $Automation.Name -Id $PSPrivateMetadata.JobId.Guid -ErrorAction SilentlyContinue
    if (!([string]::IsNullOrEmpty($Job)))
    {
        $ResourceGroup = $Job.ResourceGroupName
        $AutomationAccount = $Job.AutomationAccountName
        break;
    }
}

#Start script on each machine
foreach($machine in $HybridWorkerGroups)
{
    $output = Start-AzureRmAutomationRunbook -Name $RunbookName -ResourceGroupName $ResourceGroup  -AutomationAccountName $AutomationAccount -RunOn $machine
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
