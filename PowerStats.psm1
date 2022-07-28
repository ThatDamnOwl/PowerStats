
# Module Variables plus getters/setters

## Default Variables
$StatServer = "server"
$StatAPIRoot = "/api/v2.1"
$StatProtocol = "http"
$StatAPIPath = "$($StatProtocol)://$($StatServer)$($StatAPIRoot)"
$StatCredential = $null
$StatAPIToken = ""
$StatAuthType = "Basic"
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
            foreach ($DataObject in $BaseReply.data.Objects.data)
            {

                $ignore = $TempList.add((Merge-ObjectData ($TempList | where {$_.id -eq $DataObject.id}) $DataObject))
            }

            Write-Verbose "Merging Second array of size $($MergeReply.data.Objects.data.count)"
            
            foreach ($DataObject in $MergeReply.data.Objects.data)
            {
                $ignore = $TempList.add((Merge-ObjectData ($TempList | where {$_.id -eq $DataObject.id}) $DataObject))
            }

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
        $ContentType = "application/x-www-form-urlencoded",
        $AuthType = "basic",
        $Credential,
        $APIToken
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

    if ($AuthType = "Basic")
    {
        $offset = 0
        do 
        {
            Write-Debug "Getting $uri"
            $PageReturn = Invoke-RestMethod -URI $uri                 `
                                            -Method $Method           `
                                            -ContentType $ContentType `
                                            -Credential $Credential 


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
    }
    else
    {
        ## Sorry, this part hasn't been implemented yet, I only have a basic auth testing version
        if ($APIToken = $null)
        {
            Invoke-StatAuthentication $Credential
        }
    }

    return $FullReturn
}

Function Invoke-StatAuthentication
{
    param
    (
        $Creds
    )

    ## TODO
    $Body = @{
        user=$Creds.Username
        password=$Creds.GetNetworkCredential().Password
    }
    $URI = "$($StatProtocol)://$($StatServer)/ss-auth?user=$($Body["user"])&password=$($Body["password"])"
    Write-Verbose $URI
    $Return = Invoke-RestMethod -Method Post -Uri $URI -ContentType "application/x-www-form-urlencoded"
    return $Return
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
    Invoke-StatRequest -uri "$StatAPIPath/discover/execute/?mode=single"
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

        $properties = Get-StatDevicePropertyLinks "dummy"
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
                                                                              where {$_ -ne "id"}
}

Function Get-StatDevicePropertyLinks
{
    param
    (
        $Device
    )

    return (Get-StatPropertyLinks "cdt_device" $Device)
}

##Load any saved variables
Invoke-StatVariableLoad