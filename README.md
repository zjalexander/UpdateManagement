# UpdateManagement
PowerShell examples for UpdateManagement

## Using these scripts

These are samples intended for use with Update Management [pre/post scripts](https://docs.microsoft.com/azure/automation/pre-post-scripts). 

### Requirements

You will need:
* [An Automation Account + linked Log Analytics workspace with Update Management enabled](https://docs.microsoft.com/azure/automation/automation-update-management)
* [A RunAs account](https://docs.microsoft.com/azure/automation/manage-runas-account) for interacting with the Azure services used by these scripts
  * If you are using these scripts for VMs across multiple subscriptions, be sure to add the RunAs service principle to those subscriptions as a role with the correct permissions
* The [ThreadJob module](https://www.powershellgallery.com/packages/ThreadJob/2.0.0) imported into your Automation Account
* The [latest versions of the AzureRM modules](https://docs.microsoft.com/azure/automation/automation-update-azure-modules)
