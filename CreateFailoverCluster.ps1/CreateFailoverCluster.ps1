#
# Copyright="� Microsoft Corporation. All rights reserved."
#

configuration PrepareForSQLAlwaysOn
{
    param
    (

        [Int]$RetryCount=20,
        
        [Int]$RetryIntervalSec=30

    )

    Import-DscResource -ModuleName cDisk,xDisk

    xWaitforDisk Disk2
        {
             DiskNumber = 2
             RetryIntervalSec =$RetryIntervalSec
             RetryCount = $RetryCount
        }

        cDiskNoRestart DataDisk
        {
            DiskNumber = 2
            DriveLetter = "F"
            DependsOn = "[xWaitforDisk]Disk2"
        }

        xWaitforDisk Disk3
        {
             DiskNumber = 3
             RetryIntervalSec =$RetryIntervalSec
             RetryCount = $RetryCount
        }

        cDiskNoRestart LogDisk
        {
            DiskNumber = 3
            DriveLetter = "G"
            DependsOn = "[xWaitforDisk]Disk3"
        }

        WindowsFeature FC
        {
            Name = "Failover-Clustering"
            Ensure = "Present"
        }
      
        WindowsFeature FCPS
        {
            Name = "RSAT-Clustering-PowerShell"
            Ensure = "Present"
        }

        WindowsFeature ADPS
        {
            Name = "RSAT-AD-PowerShell"
            Ensure = "Present"
        }
}

configuration CreateFailoverCluster
{
    param
    (
        [Parameter(Mandatory)]
        [String]$DomainName,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$Admincreds,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$SQLServiceCreds,

        [Parameter(Mandatory)]
        [String]$ClusterName,

        [Parameter(Mandatory)]
        [String]$SharePath,

        [Parameter(Mandatory)]
        [String[]]$Nodes,

        [Parameter(Mandatory)]
        [String]$SqlAlwaysOnAvailabilityGroupName1,
        
        [Parameter(Mandatory)]
        [String]$SqlAlwaysOnAvailabilityGroupName2,

        [Parameter(Mandatory)]
        [String]$SqlAlwaysOnAvailabilityGroupListenerName1,

        [UInt32]$SqlAlwaysOnAvailabilityGroupListenerPort1=1433,
        
        [UInt32]$sqlAlwaysOnAvailabilityGroupListenerProbePort1=59999,
        
        [Parameter(Mandatory)]
        [String]$SqlAlwaysOnAvailabilityGroupListenerName2,

        [UInt32]$SqlAlwaysOnAvailabilityGroupListenerPort2=1434,
        
        [UInt32]$sqlAlwaysOnAvailabilityGroupListenerProbePort2=59998,

        [Parameter(Mandatory)]
        [String]$LBName,

        [Parameter(Mandatory)]
        [String]$LBAddress1,
               
        [Parameter(Mandatory)]
        [String]$LBAddress2,

        [Parameter(Mandatory)]
        [String]$PrimaryReplica,

        [Parameter(Mandatory)]
        [String]$SecondaryReplica,

        [Parameter(Mandatory)]
        [String]$SqlAlwaysOnEndpointName,

        [String]$DNSServerName='dc-pdc',

        [String]$DomainNetbiosName=(Get-NetBIOSName -DomainName $DomainName),

        [Int]$RetryCount=20,
        
        [Int]$RetryIntervalSec=30

    )

    Import-DscResource -ModuleName xComputerManagement,xFailOverCluster,xActiveDirectory,xSqlPs,xNetworking,xSql,xSQLServer

    [System.Management.Automation.PSCredential]$DomainCreds = New-Object System.Management.Automation.PSCredential ("${DomainNetbiosName}\$($Admincreds.UserName)", $Admincreds.Password)
    [System.Management.Automation.PSCredential]$DomainFQDNCreds = New-Object System.Management.Automation.PSCredential ("${DomainName}\$($Admincreds.UserName)", $Admincreds.Password)
    [System.Management.Automation.PSCredential]$SQLCreds = New-Object System.Management.Automation.PSCredential ("${DomainNetbiosName}\$($SQLServiceCreds.UserName)", $SQLServiceCreds.Password)
    
    [string]$SQLAGListenerFQDN1="${SqlAlwaysOnAvailabilityGroupListenerName1}.${DomainName}"
    [string]$SQLAGListenerFQDN2="${SqlAlwaysOnAvailabilityGroupListenerName2}.${DomainName}"

    Enable-CredSSPNTLM -DomainName $DomainName

    WaitForSqlSetup

    Node localhost
    {

        PrepareForSQLAlwaysOn BaseNodeConfig {}

        xComputer DomainJoin
        {
            Name = $env:COMPUTERNAME
            DomainName = $DomainName
            Credential = $DomainCreds
        }

        xCluster FailoverCluster
        {
            Name = $ClusterName
            DomainAdministratorCredential = $DomainCreds
            Nodes = $Nodes
            DependsOn = "[xComputer]DomainJoin"
        }

        xClusterQuorum FailoverClusterQuorum
        {
            Name = $ClusterName
            SharePath = $SharePath
            DomainAdministratorCredential = $DomainCreds
            DependsOn = "[xCluster]FailoverCluster"
        }

        Script DisableStorageClustering
        {
            SetScript =  "Get-StorageSubsystem -FriendlyName 'Clustered Storage Spaces*' | Set-StorageSubSystem -AutomaticClusteringEnabled `$False"
            TestScript = "!(Get-StorageSubsystem -FriendlyName 'Clustered Storage Spaces*').AutomaticClusteringEnabled"
            GetScript = "@{Ensure = if (!(Get-StorageSubsystem -FriendlyName 'Clustered Storage Spaces*').AutomaticClusteringEnabled) {'Present'} else {'Absent'}}"
        }

        Script IncreaseClusterTimeouts
        {
            SetScript = "(Get-Cluster).SameSubnetDelay = 2000; (Get-Cluster).SameSubnetThreshold = 15; (Get-Cluster).CrossSubnetDelay = 3000; (Get-Cluster).CrossSubnetThreshold = 15"
            TestScript = "(Get-Cluster).SameSubnetDelay -eq 2000 -and (Get-Cluster).SameSubnetThreshold -eq 15 -and (Get-Cluster).CrossSubnetDelay -eq 3000 -and (Get-Cluster).CrossSubnetThreshold -eq 15"
            GetScript = "@{Ensure = if ((Get-Cluster).SameSubnetDelay -eq 2000 -and (Get-Cluster).SameSubnetThreshold -eq 15 -and (Get-Cluster).CrossSubnetDelay -eq 3000 -and (Get-Cluster).CrossSubnetThreshold -eq 15) {'Present'} else {'Absent'}}"
        }

        xFirewall DatabaseEngineFirewallRule1
        {
            Direction = "Inbound"
            Name = "SQL-Server-Database-Engine-TCP-In-1"
            DisplayName = "SQL Server Database Engine (TCP-In)"
            Description = "Inbound rule for SQL Server to allow TCP traffic for the Database Engine."
            DisplayGroup = "SQL Server"
            State = "Enabled"
            Access = "Allow"
            Protocol = "TCP"
            LocalPort = $SqlAlwaysOnAvailabilityGroupListenerPort1 -as [String]
            Ensure = "Present"
        }
        
        xFirewall DatabaseEngineFirewallRule2
        {
            Direction = "Inbound"
            Name = "SQL-Server-Database-Engine-TCP-In-2"
            DisplayName = "SQL Server Database Engine (TCP-In)"
            Description = "Inbound rule for SQL Server to allow TCP traffic for the Database Engine."
            DisplayGroup = "SQL Server"
            State = "Enabled"
            Access = "Allow"
            Protocol = "TCP"
            LocalPort = $SqlAlwaysOnAvailabilityGroupListenerPort2 -as [String]
            Ensure = "Present"
        }

        xFirewall DatabaseMirroringFirewallRule
        {
            Direction = "Inbound"
            Name = "SQL-Server-Database-Mirroring-TCP-In"
            DisplayName = "SQL Server Database Mirroring (TCP-In)"
            Description = "Inbound rule for SQL Server to allow TCP traffic for the Database Mirroring."
            DisplayGroup = "SQL Server"
            State = "Enabled"
            Access = "Allow"
            Protocol = "TCP"
            LocalPort = "5022"
            Ensure = "Present"
        }

        xFirewall ListenerProbeFirewallRule1
        {
            Direction = "Inbound"
            Name = "SQL-Server-Availability-Group-Probe-TCP-In-1"
            DisplayName = "SQL Server Availability Group Listener (TCP-In)"
            Description = "Inbound rule for SQL Server to allow TCP traffic for the Availability Group listener."
            DisplayGroup = "SQL Server"
            State = "Enabled"
            Access = "Allow"
            Protocol = "TCP"
            LocalPort = $sqlAlwaysOnAvailabilityGroupListenerProbePort1 -as [String]
            Ensure = "Present"
        }

        xFirewall ListenerProbeFirewallRule2
        {
            Direction = "Inbound"
            Name = "SQL-Server-Availability-Group-Probe-TCP-In-2"
            DisplayName = "SQL Server Availability Group Listener (TCP-In)"
            Description = "Inbound rule for SQL Server to allow TCP traffic for the Availability Group listener."
            DisplayGroup = "SQL Server"
            State = "Enabled"
            Access = "Allow"
            Protocol = "TCP"
            LocalPort = $sqlAlwaysOnAvailabilityGroupListenerProbePort2 -as [String]
            Ensure = "Present"
        }

        xSqlLogin AddDomainAdminAccountToSysadminServerRole
        {
            Name = $DomainCreds.UserName
            LoginType = "WindowsUser"
            ServerRoles = "sysadmin"
            Enabled = $true
            Credential = $Admincreds
            DependsOn = "[xComputer]DomainJoin"
        }

        xADUser CreateSqlServerServiceAccount
        {
            DomainAdministratorCredential = $DomainCreds
            DomainName = $DomainName
            UserName = $SQLServicecreds.UserName
            Password = $SQLServicecreds
            Ensure = "Present"
            DependsOn = "[xComputer]DomainJoin"
        }

        xSqlLogin AddSqlServerServiceAccountToSysadminServerRole
        {
            Name = $SQLCreds.UserName
            LoginType = "WindowsUser"
            ServerRoles = "sysadmin"
            Enabled = $true
            Credential = $Admincreds
            DependsOn = @("[xADUser]CreateSqlServerServiceAccount","[xSqlLogin]AddDomainAdminAccountToSysadminServerRole")
        }

        xSqlServer ConfigureSqlServerWithAlwaysOn
        {
            InstanceName = $env:COMPUTERNAME
            SqlAdministratorCredential = $Admincreds
            ServiceCredential = $SQLCreds
            Hadr = "Enabled"
            MaxDegreeOfParallelism = 1
            FilePath = "F:\DATA"
            LogPath = "G:\LOG"
            DomainAdministratorCredential = $DomainFQDNCreds
            DependsOn = "[xSqlLogin]AddSqlServerServiceAccountToSysadminServerRole"
        }

        xSqlEndpoint SqlAlwaysOnEndpoint
        {
            InstanceName = $env:COMPUTERNAME
            Name = $SqlAlwaysOnEndpointName
            PortNumber = 5022
            AllowedUser = $SQLServiceCreds.UserName
            SqlAdministratorCredential = $SQLCreds
            DependsOn = "[xSqlServer]ConfigureSqlServerWithAlwaysOn"
        }

        xSqlServer ConfigureSqlServerSecondaryWithAlwaysOn
        {
            InstanceName = $SecondaryReplica
            SqlAdministratorCredential = $Admincreds
            Hadr = "Enabled"
            DomainAdministratorCredential = $DomainFQDNCreds
	        DependsOn = "[xSqlEndPoint]SqlAlwaysOnEndpoint"
        }

        xSqlEndpoint SqlSecondaryAlwaysOnEndpoint
        {
            InstanceName = $SecondaryReplica
            Name = $SqlAlwaysOnEndpointName
            PortNumber = 5022
            AllowedUser = $SQLServiceCreds.UserName
            SqlAdministratorCredential = $SQLCreds
            DependsOn = "[xSqlServer]ConfigureSqlServerSecondaryWithAlwaysOn"
        }

        xSqlAvailabilityGroup SqlAG1
        {
            Name = $SqlAlwaysOnAvailabilityGroupName1
            ClusterName = $ClusterName
            InstanceName = $env:COMPUTERNAME
            PortNumber = 5022
            DomainCredential =$DomainCreds
            SqlAdministratorCredential = $Admincreds
	        DependsOn = "[xSqlEndpoint]SqlSecondaryAlwaysOnEndpoint"
        }
        
        xSqlAvailabilityGroup SqlAG2
        {
            Name = $SqlAlwaysOnAvailabilityGroupName2
            ClusterName = $ClusterName
            InstanceName = $env:COMPUTERNAME
            PortNumber = 5022
            DomainCredential =$DomainCreds
            SqlAdministratorCredential = $Admincreds
	        DependsOn = "[xSqlAvailabilityGroup]SqlAG1"
        }

        xSQLAddListenerIPToDNS UpdateDNSServer1
        {
            Credential =$DomainCreds
            LBName=$SqlAlwaysOnAvailabilityGroupListenerName1
            LBAddress=$LBAddress1
            DomainName=$DomainName
            DNSServerName=$DNSServerName
            DependsOn = "[xSqlAvailabilityGroup]SqlAG2"
        }
        
        xSQLAddListenerIPToDNS UpdateDNSServer2
        {
            Credential =$DomainCreds
            LBName=$SqlAlwaysOnAvailabilityGroupListenerName2
            LBAddress=$LBAddress2
            DomainName=$DomainName
            DNSServerName=$DNSServerName
            DependsOn = "[xSQLAddListenerIPToDNS]UpdateDNSServer1"
        }

        xSqlAvailabilityGroupListener SqlAGListener1
        {
            Name = $SqlAlwaysOnAvailabilityGroupListenerName1
            AvailabilityGroupName = $SqlAlwaysOnAvailabilityGroupName1
            DomainNameFqdn = $SQLAGListenerFQDN1
            LBAddress=$LBAddress1
            ListenerPortNumber = $SqlAlwaysOnAvailabilityGroupListenerPort1
            ProbePortNumber = $sqlAlwaysOnAvailabilityGroupListenerProbePort1
            InstanceName = $env:COMPUTERNAME
            DomainCredential =$DomainCreds
            SqlAdministratorCredential = $Admincreds
            DependsOn = "[xSQLAddListenerIPToDNS]UpdateDNSServer2"
        }

        xSqlAvailabilityGroupListener SqlAGListener2
        {
            Name = $SqlAlwaysOnAvailabilityGroupListenerName2
            AvailabilityGroupName = $SqlAlwaysOnAvailabilityGroupName2
            DomainNameFqdn = $SQLAGListenerFQDN2
            LBAddress=$LBAddress2
            ListenerPortNumber = $SqlAlwaysOnAvailabilityGroupListenerPort2
            ProbePortNumber = $sqlAlwaysOnAvailabilityGroupListenerProbePort2
            InstanceName = $env:COMPUTERNAME
            DomainCredential =$DomainCreds
            SqlAdministratorCredential = $Admincreds
            DependsOn = "[xSqlAvailabilityGroupListener]SqlAGListener1"
        }

        LocalConfigurationManager
        {
            RebootNodeIfNeeded = $True
        }

    }

}

function Update-DNS
{
    param(
        [string]$LBName,
        [string]$LBAddress,
        [string]$DomainName

        )

        $ARecord=Get-DnsServerResourceRecord -Name $LBName -ZoneName $DomainName -ErrorAction SilentlyContinue -RRType A
        if (-not $Arecord)
        {
            Add-DnsServerResourceRecordA -Name $LBName -ZoneName $DomainName -IPv4Address $LBAddress
        }
}

function WaitForSqlSetup
{
    # Wait for SQL Server Setup to finish before proceeding.
    while ($true)
    {
        try
        {
            Get-ScheduledTaskInfo "\ConfigureSqlImageTasks\RunConfigureImage" -ErrorAction Stop
            Start-Sleep -Seconds 5
        }
        catch
        {
            break
        }
    }
}

function Get-NetBIOSName
{
    [OutputType([string])]
    param(
        [string]$DomainName
    )

    if ($DomainName.Contains('.')) {
        $length=$DomainName.IndexOf('.')
        if ( $length -ge 16) {
            $length=15
        }
        return $DomainName.Substring(0,$length)
    }
    else {
        if ($DomainName.Length -gt 15) {
            return $DomainName.Substring(0,15)
        }
        else {
            return $DomainName
        }
    }
}

function Enable-CredSSPNTLM
{
    param(
        [Parameter(Mandatory=$true)]
        [string]$DomainName
    )

    # This is needed for the case where NTLM authentication is used

    Write-Verbose 'STARTED:Setting up CredSSP for NTLM'

    Enable-WSManCredSSP -Role client -DelegateComputer localhost, *.$DomainName -Force -ErrorAction SilentlyContinue
    Enable-WSManCredSSP -Role server -Force -ErrorAction SilentlyContinue

    if(-not (Test-Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation -ErrorAction SilentlyContinue))
    {
        New-Item -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows -Name '\CredentialsDelegation' -ErrorAction SilentlyContinue
    }

    if( -not (Get-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation -Name 'AllowFreshCredentialsWhenNTLMOnly' -ErrorAction SilentlyContinue))
    {
        New-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation -Name 'AllowFreshCredentialsWhenNTLMOnly' -value '1' -PropertyType dword -ErrorAction SilentlyContinue
    }

    if (-not (Get-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation -Name 'ConcatenateDefaults_AllowFreshNTLMOnly' -ErrorAction SilentlyContinue))
    {
        New-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation -Name 'ConcatenateDefaults_AllowFreshNTLMOnly' -value '1' -PropertyType dword -ErrorAction SilentlyContinue
    }

    if(-not (Test-Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowFreshCredentialsWhenNTLMOnly -ErrorAction SilentlyContinue))
    {
        New-Item -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation -Name 'AllowFreshCredentialsWhenNTLMOnly' -ErrorAction SilentlyContinue
    }

    if (-not (Get-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowFreshCredentialsWhenNTLMOnly -Name '1' -ErrorAction SilentlyContinue))
    {
        New-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowFreshCredentialsWhenNTLMOnly -Name '1' -value "wsman/$env:COMPUTERNAME" -PropertyType string -ErrorAction SilentlyContinue
    }

    if (-not (Get-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowFreshCredentialsWhenNTLMOnly -Name '2' -ErrorAction SilentlyContinue))
    {
        New-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowFreshCredentialsWhenNTLMOnly -Name '2' -value "wsman/localhost" -PropertyType string -ErrorAction SilentlyContinue
    }

    if (-not (Get-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowFreshCredentialsWhenNTLMOnly -Name '3' -ErrorAction SilentlyContinue))
    {
        New-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowFreshCredentialsWhenNTLMOnly -Name '3' -value "wsman/*.$DomainName" -PropertyType string -ErrorAction SilentlyContinue
    }

    Write-Verbose "DONE:Setting up CredSSP for NTLM"
}
