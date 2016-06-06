function Get-TargetResource
{
    param
    (
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential] $Credential,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$LBName,     
        
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$LBAddress,
        
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DNSServerName,
                
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DomainName
    )

   $retVal = @{
        LBName=$LBName
        LBAddress=$LBAddress
        DomainName=$DomainName 
        DNSServerName=$DNSServerName     
    }
    $retVal
}

function Set-TargetResource
{
    param
    (
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential] $Credential,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$LBName,     
        
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$LBAddress,
         
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DNSServerName,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DomainName
    )

    $DNSServerFQName="${DNSServerName}.${DomainName}"
    Invoke-command -ScriptBlock ${Function:Update-DNS} -ArgumentList $LBName,$LBAddress,$DomainName -ComputerName $DNSServerFQName -Credential $Credential
   
}

function Test-TargetResource
{
    param
    (
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential] $Credential,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$LBName,     
        
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$LBAddress,
        
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DNSServerName,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DomainName
    )

    $false
    
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

Export-ModuleMember -Function *-TargetResource


