
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
                    $Credential
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
            $PageReturn = Invoke-RestMethod -URI $uri                 `
                                            -Method $Method           `
                                            -ContentType $ContentType `
                                            -Credential $Credential 
            if ($FullReturn)
            {
                if ($PageReturn.data.Objects)
                {
                    $TempList = New-Object System.Collections.ArrayList

                    $TempList.addrange((Read-StatArray $FullReturn.data.Objects.data))
                    $TempList.addrange((Read-StatArray $PageReturn.data.Objects.data))

                    $FullReturn.data.Objects | add-member -type NoteProperty -name data -value $TempList.ToArray() -force
                }
                $FullReturn.links += $PageReturn.Links
            }
            else
            {
                $FullReturn = $PageReturn
            }
            $MoreData = ($PageReturn.Links | where {$_.rel -eq "Last"}) -ne $null

            $offset += 50

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
    Write-Host $URI
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

Function Get-StatDevice
{
    param
    (
        [switch]
        $all,
        $filterstring,
        $properties
    )

    if ($all)
    {
        $DeviceData = Invoke-StatRequest -uri "$StatAPIPath/cdt_device"

    }
    else {
        $DeviceData = Invoke-StatRequest -uri "$StatAPIPath/cdt_device/?$filterstring"
    }

    if (-not $properties)
    {
        $DeviceData
    }

    foreach ($Device in $DeviceData.data.Objects.data)
    {
        #Invoke-StatRequest -uri "$StatAPIPath/cdt_device/$($Device.id)"
    }
}

##Load any saved variables
Invoke-StatVariableLoad