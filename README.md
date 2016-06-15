# Create a SQL Server 2014 Always On Availability Group with Multiple Listeners

This template will create a SQL Server 2014 Always On Availability Group with Multiple Listeners.  It creates the following resources:

+	A Virtual Network
+	Four Storage Accounts
+	One external load balancer for NAT'd access to RDP
+	One internal load balancer for SQL AG Listeners
+	Two VMs configured as Domain Controllers for a new forest with a single domain
+	Three VMs in a Windows Server Cluster, two VMs run SQL Server 2014 with an availability group and the third is a File Share Witness for the Cluster
+	Two Availability Sets one for the AD VMs, the other for the SQL and Witness VMs, the second Availability Set is configured with three Update Domains and three Fault Domains

The external load balancer creates an RDP NAT rule to allow connectivity to the first VM created, in order to access other VMs in the deployment this VM should be used as a jumpbox.

## Notes

+	The default settings for storage are to deploy using **premium storage**, the AD VMs use a P10 Disk and the SQL VMs use two P30 disks each, these sizes can be changed by changing the relevant variables. In addition there is a P10 Disk used for each VMs OS Disk.

+ 	In default settings for compute require that you have at least 11 cores of free quota to deploy.

+ 	The images used to create this deployment are
	+ 	AD - Latest Windows Server 2012 R2 Image
	+ 	SQL Server - Latest SQL Server 2014 SP1 on Windows Server 2012 R2 Image
	+ 	Witness - Latest Windows Server 2012 R2 Image

+ 	The image configuration is defined in variables - but the scripts that configure this deployment have only been tested with these versions and may not work on other images.


Click the button below to deploy from the portal

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Frobotechredmond%2FSQLAlwaysOnMultiListener%2Fmaster%2Fazuredeploy.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png"/>
</a>
<a href="http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2Frobotechredmond%2FSQLAlwaysOnMultiListener%2Fmaster%2Fazuredeploy.json" target="_blank">
    <img src="http://armviz.io/visualizebutton.png"/>
</a>

## Deploying from PowerShell

For details on how to install and configure Azure Powershell see [here].(https://azure.microsoft.com/en-us/documentation/articles/powershell-install-configure/)

Launch a PowerShell console

Change working folder to the folder containing this template

```PowerShell

New-AzureRmResourceGroupDeployment -ResourceGroupName "<new resourcegroup name>" -Location "<new resourcegroup location>"  -TemplateParameterFile .\azuredeploy-parameters.json -TemplateFile .\azuredeploy.json
