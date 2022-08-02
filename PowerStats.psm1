
# Module Variables plus getters/setters

## Default Variables
$StatServer = "server"
$StatAPIRoot = "/api/v2.1"
$StatProtocol = "http"
$StatAPIPath = "$($StatProtocol)://$($StatServer)$($StatAPIRoot)"
$StatCredential = $null
$StatAPIToken = ""
$StatAuthType = "token"
$StatSkipProperties = @("id")

$ModuleFolder = (Get-Module PowerStats -ListAvailable).path -replace "PowerStats\.psm1"

Function Set-StatAPIRoot
{
    param (
        $NewRoot
    )
    set-variable -Scope 1 -Name StatAPIRoot -Value $NewRoot
    set-variable -Scope 1 -Name StatAPIPath -Value "$($StatProtocol)://$($StatServer)$($StatAPIRoot)"
}

Function Set-StatServer
{
    param (
        $NewServer
    )

    set-variable -Scope 1 -Name StatServer -Value $NewServer
    set-variable -Scope 1 -Name StatAPIPath -Value "$($StatProtocol)://$($StatServer)$($StatAPIRoot)"

}

Function Set-StatProtocol
{
    param(
        $NewProtocol
    )   

    set-variable -Scope 1 -Name StatProtocol -Value $NewProtocol
    set-variable -Scope 1 -Name StatAPIPath -Value "$($StatProtocol)://$($StatServer)$($StatAPIRoot)"
}

Function Set-StatCredential
{
    param (
        $NewCredentials
    )

    set-variable -Scope 1 -Name StatCredential -Value $NewCredentials
}

Function Set-StatAuthType
{
    param (
        $NewAuthType
    )

    set-variable -scope 1 -name StatAuthType -Value $NewAuthType
}

Function Get-StatServer
{
    $StatServer
}

Function Get-StatAPIRoot
{
    $StatAPIRoot
}

Function Get-StatProtocol
{
    $StatProtocol
}

Function Get-StatAPIPath
{
    $StatAPIPath
}

function Get-StatCredential
{
    $StatCredential
}

function Get-StatAuthType
{
    $StatAuthType
}

Function Get-StatApiToken
{
    $StatAPIToken
}

Function Invoke-StatVariableSave 
{
    $AllVariables = Get-Variable -scope 1 | where {$_.name -match "Stat"}
    $VariableStore = @{}
    foreach ($Variable in $AllVariables)
    {
        if ($Variable.value.GetType().name -eq "PSCredential")
        {
            $VariableStore += @{
                                   "username" = $Variable.value.username
                                   "securepass" = ($Variable.value.Password | ConvertFrom-SecureString)
                               }
        }
        else {
            $VariableStore += @{$Variable.name = $Variable.Value}
        }
    }

    $VariableStore.GetEnumerator() | export-csv "$ModuleFolder\$($ENV:Username)-Variables.csv"
}

Function Invoke-StatVariableLoad
{
    $VariablePath = "$ModuleFolder\$($ENV:Username)-Variables.csv"
    if (test-path $VariablePath)
    {
        $VariableStore = import-csv $VariablePath

        foreach ($Variable in $VariableStore)
        {
            if ($Variable.name -match "(username|securepass)")
            {
                if ($Variable.name -eq "username")
                {
                    Write-Debug "Importing StatCredential"
                    $EncString = ($VariableStore | where {$_.name -eq "securepass"}).Value | ConvertTo-SecureString
                    $Credential = New-Object System.Management.Automation.PsCredential($Variable.Value, $EncString)
                    set-variable -scope 1 -name StatCredential -value $Credential
                }
            }
            else
            {
                Write-Debug "Importing $($Variable.name)"
                set-variable -scope 1 -name $Variable.Name -value $Variable.Value
            }
        }
    }

}

#Basic Functions

Function Read-StatArray
{
    param
    (
        $Array
    )

    for ($i = 0; $i -le $Array.count; $i++)
    {
        $Array[$i]
    }
}

Function Merge-ObjectData
{
    param
    (
        $BaseObject,
        $MergeObject
    )

    if ($BaseObject -eq $null)
    {
        return $MergeObject
    }
    else
    {
        $MergeProperties = $MergeObject | gm | where {$_.MemberType -eq "NoteProperty"} | `
                                               where { `
                                                   ($BaseObject | gm | where {$_.MemberType -eq "NoteProperty"}).name `
                                                   -notcontains `
                                                   $_.name `
                                               } `

        Foreach ($MergeProperty in $MergeProperties)
        {
            $BaseObject | add-member -type NoteProperty -name $MergeProperty.Name -value $MergeObject."$($MergeProperty.Name)" -force
        }
    }

    return $BaseObject
}

Function Merge-StatReturn
{
    param
    (
        $BaseReply,
        $MergeReply
    )
    if ($BaseReply)
    {
        if ($MergeReply.data.Objects)
        {
            $TempList = $null
            $TempList = New-Object System.Collections.ArrayList
            
            Write-Verbose "Merging First array of size $($BaseReply.data.Objects.data.count)"
            $TempList.AddRange($BaseReply.data.Objects.data)

            Write-Verbose "Merging Second array of size $($MergeReply.data.Objects.data.count)"
            $TempList.AddRange($MergeReply.data.Objects.data)

            $BaseReply.data.Objects | add-member -type NoteProperty -name data -value $TempList.ToArray() -force
        }

        try 
        {
            if ($BaseReply.links)
            {
                Write-Verbose "Merging Link values"
                $TempList = $null
                $TempList = New-Object System.Collections.ArrayList

                Write-Debug "Links in base object - $($BaseReply.links.count)"
                Write-Debug "Links in merge object - $($MergeReply.links.count)"
                $TempList.AddRange($BaseReply.links)
                $TempList.AddRange($MergeReply.links)

                $TempListArray = $TempList.ToArray()

                $BaseReply | add-member -type NoteProperty -name links -Value $TempListArray -force

                Write-Debug "Links in base object post add- $($BaseReply.links.count)"
            }
        }
        catch
        {
            Write-Debug "$($BaseReply.links.count)"
            Write-Debug "$($MergeReply.links.count)"
        }

    }
    else
    {
        $BaseReply = $MergeReply
    }
    return $BaseReply
}

Function Merge-ArrayToCSString
{
    param
    (
        $Array,
        $Prefix,
        $Suffix
    )

    $tofs = $ofs
    $ofs = ","

    $TempString = "$Array"

    $ofs = $tofs

    $TempString = $Prefix + $TempString + $Suffix

    $TempString
}

Function Invoke-StatRequest
{
    param
    (
        $uri,
        $Method = "Get",
        $ContentType = "application/json",
        $Credential
    )

    if ($Credential -eq $null)
    {
        if ($StatCredential -eq $null)
        {
            $Credential = Get-Credential

            set-variable -scope 1 -name StatCredentials -value $Credential         
        }
        else 
        {
            $Credential = $StatCredential
        }
    }

    if ($StatAuthType -eq "Token")
    {
        ##Yet to be implemented/completed
        if ($StatAPIToken -eq $null)
        {
            $Auth = Invoke-StatAuthentication $Credential
        }
    }
    else {

    }

    $offset = 0
    do 
    {
        Write-Debug "Getting $uri"

        if ($StatAuthType -eq "Token")
        {   
            Write-Verbose $StatAPIToken
            $Headers = @{"Authorization" = "Bearer $StatAPIToken"}
            $Headers.keys | Write-Debug
            $Headers.Values | Write-Debug 
            $PageReturn = Invoke-RestMethod -URI $uri                 `
                                            -Method $Method           `
                                            -ContentType $ContentType `
                                            -Headers $Headers
        }
        else {
            $PageReturn = Invoke-RestMethod -URI $uri                 `
                                            -Method $Method           `
                                            -ContentType $ContentType `
                                            -Credential $Credential
        } 


        $MoreData = (($PageReturn.Links | where {$_.rel -eq "Last"}) -ne $null)
        $offset += 50

        $FullReturn = Merge-StatReturn $FullReturn $PageReturn

        if ($uri -match "offset=")
        {
            $uri = $uri -replace "offset=\d*","offset=$offset"
        }
        elseif ($uri -match "\?")
        {
            $uri = "$($uri)&offset=$offset"
        }
        else {
            $uri = "$($uri)?&offset=$offset"
        }
    }
    while ($MoreData)

    return $FullReturn
}

Function Invoke-StatAuthentication
{
    param
    (
        $Creds,
        [switch]
        $Token,
        [switch]
        $Basic
    )

    if ($Creds -eq $null)
    {
        $Creds = $StatCredential
    }
    else {
        
    }

    if ($StatAuthType -eq "Token" -or $Token)
    {
        ## TODO
        $Body = @{
            user=$Creds.Username
            password=$Creds.GetNetworkCredential().Password
        }
        $URI = "$($StatProtocol)://$($StatServer)/ss-auth"

        try {
                
            $Return = Invoke-RestMethod -Method Post -Uri $URI -ContentType "application/x-www-form-urlencoded" `
                                        -body $Body

            $access_token = $Return.access_token.ToString()
        }
        catch
        {
            Write-Verbose "Authentication failed, please try again"

            if (Invoke-StatAuthentication $Creds -Basic)
            {
                Write-Verbose "HINT - Try basic authentication"
            }

            return $False
        }  


        set-variable -scope 1 -name StatAPIToken -value ($access_token) -force

        Write-Verbose $StatAPIToken

        Write-Verbose "Authentication successful"  

        set-variable -scope 1 -name StatCredential -value $Creds -force

        return $true          
    }
    elseif ($StatAuthType -eq "Basic" -or $Basic) {
        try {
            $Ignore = Invoke-StatRequest -uri $StatAPIPath -contenttype "application/json" -credential $Creds


        }
        catch
        {
            Write-Verbose "Authentication failed, please try again"

            if (Invoke-StatAuthentication $Creds -Token)
            {
                Write-Verbose "HINT - Try token authentication"
            }
            return $False
        }

        Write-Verbose "Authentication successful"  

        set-variable -scope 1 -name StatCredential -value $Creds -force

        return $True
    }
    else {
        Write-Error "Incorrect authentication method provided please select either ""Basic"" or ""Token"""
    }
}



#API Functions

Function Get-StatRoot
{
    Invoke-StatRequest -uri $StatAPIPath -contenttype "application/json" -credential $StatCredential
}

Function Invoke-StatDiscoverySingle
{
    param
    (
        $Address
    )

    if ($VerbosePreference -eq "Continue")
    {
        $Verbosity = 2
    }
    else
    {
        $Verbosity = 0    
    }

    Invoke-StatRequest -uri "$StatAPIPath/discover/execute/?mode=single&ip=$Address&verbose=$Verbosity"
}

Function Get-StatResource
{
    param
    (
        [string]
        $Resource,
        [string]
        $object,
        [string]
        $filterstring,
        [object[]]
        $properties,
        [switch]
        $all,
        [switch]
        $allProperties,
        [switch]
        $RawData
    )

    if ($allProperties)
    {
        Write-Verbose "All properties were requested"

        $properties = Get-StatPropertyLinks $Resource "dummy"
    }
    
    if ($properties)
    {
        $PropertyFilters = Merge-ArrayToCSString -array $properties -prefix "fields="

        $filterstring += $PropertyFilters
    }

    if ($filterstring[0] -ne "?")
    {
        $filterstring = "?" + $filterstring

        if ($filterstring[0] -eq "&")
        {
            $filterstring = $filterstring.Substring(1,$filterstring.length - 1)
        }
    }

    $ResourceData = (Invoke-StatRequest -uri "$StatAPIPath/$Resource/$($object)$filterstring")

    if (-not $RawData)
    {
        $ResourceData = $ResourceData.data.Objects.data
    }


    return $ResourceData
}

Function Get-StatDevice
{
    param
    (
        $DeviceID,
        $filterstring,
        $properties,
        [switch]
        $all,
        [switch]
        $allProperties,
        [switch]
        $RawData
    )

    Return Get-StatResource -all:$all -resource "cdt_device" -object $DeviceID -filterstring $filterstring -properties $properties -allproperties:$allProperties -RawData:$RawData
}

Function Get-StatPropertyLinks
{
    param
    (
        $Resource,
        $Object
    )

    return (Invoke-StatRequest -uri "$StatAPIPath/$Resource/$Object").links | where {$_.rel -eq "item"} | `
                                                                              %{$_.link -replace "$StatAPIRoot/$Resource/$Object/"} | `
                                                                              where {$_ -notin $StatSkipProperties} 
}

Function Get-StatDevicePropertyLinks
{
    param
    (
        $DeviceID,
        $filterstring,
        $properties,
        [switch]
        $all,
        [switch]
        $allProperties,
        [switch]
        $RawData
    )

    return (Get-StatPropertyLinks "cdt_device" $DeviceID)
}

Function Get-StatDeviceInventory
{
    param
    (
        $DeviceID,
        $filterstring,
        $properties,
        [switch]
        $all,
        [switch]
        $allProperties,
        [switch]
        $RawData
    )

    Return Get-StatResource -all:$all -resource "cdt_inventory_device" -object $DeviceID -filterstring $filterstring -properties $properties -allproperties:$allProperties -RawData:$RawData
}

Function Get-StatInventory
{
    param
    (
        $InventoryID,
        $filterstring,
        $properties,
        [switch]
        $all,
        [switch]
        $allProperties,
        [switch]
        $RawData
    )

    Return Get-StatResource -all:$all -resource "cdt_inventory" -object $InventoryID -filterstring $filterstring -properties $properties -allproperties:$allProperties -RawData:$RawData
}

Function Get-StatIpAddress
{
    param
    (
        $IPID,
        $filterstring,
        $properties,
        [switch]
        $all,
        [switch]
        $allProperties,
        [switch]
        $RawData
    )

    Return Get-StatResource -all:$all -resource "cdt_ipaddress" -object $IPID -filterstring $filterstring -properties $properties -allproperties:$allProperties -RawData:$RawData
}

Function Get-StatIpAddr
{
    param
    (
        $IPID,
        $filterstring,
        $properties,
        [switch]
        $all,
        [switch]
        $allProperties,
        [switch]
        $RawData
    )

    Return Get-StatResource -all:$all -resource "cdt_ipaddr" -object $IPID -filterstring $filterstring -properties $properties -allproperties:$allProperties -RawData:$RawData
}



##Load any saved variables
Invoke-StatVariableLoad

if ($StatCredential -ne $null)
{
    Invoke-StatAuthentication
}
else
{
    Write-Debug "No credentials stored"
}