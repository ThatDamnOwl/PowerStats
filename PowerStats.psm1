## Required Module imports

Import-module CommonFunctions -force

# Module Variables plus getters/setters

## Default Variables
$StatServer = "server"
$StatAPIRoot = "/api/v2.1"
$StatProtocol = "http"
$StatAPIPath = "$($StatProtocol)://$($StatServer)$($StatAPIRoot)"
$StatCredential = $null
$StatAPIToken = ""
$StatAuthType = "token"
$StatStoredJuniperCredentials = @()
$StatStoredPaloCredentials = @()
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

Function Set-StatApiToken
{
    param (
        $NewAPIToken
    )

    set-variable -scope 1 -name StatAPIToken -value $NewAPIToken
}

Function Set-StatStoredJuniperCredentials
{
    param
    (
        $NewStatStoredJuniperCredentials
    )

    set-variable -scope 1 -name StatStoredJuniperCredentials -value $NewStatStoredJuniperCredentials
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

Function Get-StatStoredJuniperCredentials
{
    $StatStoredJuniperCredentials
}

Function Invoke-StatVariableSave 
{
    $AllVariables = Get-Variable -scope 1 | where {$_.name -match "Stat"}
    $SavePath = "$ModuleFolder\$($ENV:Username)-Variables.json"

    Write-Debug "Starting save job to $SavePath"

    Invoke-VariableJSONSave -ModuleName "PowerStats" -SavePath $SavePath -Variables $AllVariables -verbosepreference:$VerbosePreference
}

Function Invoke-StatVariableLoad
{
    $VariablePath = "$ModuleFolder\$($ENV:Username)-Variables.json"
    if (test-path $VariablePath)
    {
        Write-Verbose "Importing variables from $VariablePath"
        $Variables = Invoke-VariableJSONLoad $VariablePath

        foreach ($Variable in $Variables)
        {
            Write-Debug "Importing variable $($Variable.name)"
            set-variable -name $Variable.name -Value $Variable.Value -scope 1
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

    $offset = [int]0
    do 
    {
        try {
            Write-Debug "Getting $uri"

            if ($StatAuthType -eq "Token")
            {   
                ##Write-Verbose $StatAPIToken
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

            if ($uri -match "limit")
            {
                $ignore = $uri -match "limit=(\d{1,5})"
                $offset += [int]$matches[1]
            }
            else
            {
                $offset += 50
            }

            $MoreData = (($PageReturn.Links | where {$_.rel -eq "Last"}) -ne $null)

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
        catch{
            if ($Error[0].Exception -match "\(401\) Unauthorized")
            {
                Write-Verbose "Session may have expired, trying to reauthenticate"
                $MoreData = Invoke-StatAuthentication
            }
            else
            {
                Write-Verbose "Error encountered, exiting and dumping all data"
                if ($Error[0].Exception)
                {

                    $Error[0].Exception.tostring() | Write-Debug
                }
                $MoreData = $false
            }
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
        $Basic,
        [switch]
        $DesignatedOnly
    )

    if ($Creds -eq $null)
    {
        $Creds = $StatCredential
    }
    else {
        
    }

    if ($StatAuthType.tolower() -eq "token" -or $Token)
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

            if (-not $DesignatedOnly)
            {       
                if (Invoke-StatAuthentication $Creds -Basic -DesignatedOnly)
                {
                    Write-Verbose "HINT - Try basic authentication"
                }
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
            if (-not $DesignatedOnly)
            {  
                if (Invoke-StatAuthentication $Creds -Token -DesignatedOnly)
                {
                    Write-Verbose "HINT - Try token authentication"
                }
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
        $GroupIDs,
        $filterstring,
        $properties,
        [switch]
        $all,
        [switch]
        $allProperties,
        [switch]
        $RawData
    )

    if ($GroupIDs)
    {
        if (-not $filterstring)
        {
            $filterstring = "?"
        }

        $tofs = $ofs
        $ofs = ","

        $filterstring += "groups=$GroupIDs&"

        $ofs = $tofs
    }

    Return Get-StatResource -all:$all -resource "cdt_device" -object $DeviceID -filterstring $filterstring -properties $properties -allproperties:$allProperties -RawData:$RawData
}

Function Get-StatDevicePorts
{
    param
    (
        $DeviceID,
        $PortID,
        $filterstring,
        $properties,
        [switch]
        $all,
        [switch]
        $allProperties,
        [switch]
        $RawData
    )
    $filterstring = "?"
    if ($PortID)
    {
        $filterstring += "id_filter=IN($PortID)&"
    }

    if ($DeviceID)
    {
        $filterstring += "deviceid_filter=IN($DeviceID)&"
    }

    $filterstring += "limit=500&"

    Return Get-StatResource -all:$all -resource "cdt_port" -filterstring $filterstring -properties $properties -allproperties:$allProperties -RawData:$RawData
}

Function Get-StatIPPortInfo
{
    param
    (
        $DeviceID,
        $PortID,
        $filterstring,
        $properties,
        [switch]
        $all,
        [switch]
        $allProperties,
        [switch]
        $RawData
    )
    $filterstring = "?"
    if ($PortID)
    {
        $filterstring += "connected_port_filter=IN($PortID)&"
    }

    if ($DeviceID)
    {
        $filterstring += "connected_device_filter=IN($DeviceID)&"
    }

    $filterstring += "limit=5000&"

    $return = Get-StatResource -all:$all -resource "mis_record" -filterstring $filterstring -properties $properties -allproperties:$allProperties -RawData:$RawData
    if ($DeviceID -or $PortID)
    {
        Return $Return | where {$_.connected_port -eq $PortID -or $_.connected_device -eq $DeviceID}
    }
    else {
        return $Return
    }
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

Function Get-StatDeviceGroups
{
    param
    (
        $DeviceID,
        $PortID,
        $filterstring,
        [switch]
        $all,
        [switch]
        $RawData
    )

    return Get-StatResource -all:$all -resource "group" -filterstring $filterstring -properties @("id","name") -allproperties:$allProperties -RawData:$RawData
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
        $DeviceID,
        [switch]
        $all,
        [switch]
        $allProperties,
        [switch]
        $RawData
    )

    if (-not $DeviceID)
    {
        $filterstring += "limit=5000&"
    }

    Return Get-StatResource -all:$all -resource "cdt_ip_address" -object $IPID -filterstring $filterstring -properties $properties -allproperties:$allProperties -RawData:$RawData
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

    Return Get-StatResource -all:$all -resource "cdt_ip_addr" -object $IPID -filterstring $filterstring -properties $properties -allproperties:$allProperties -RawData:$RawData
}

Function Import-StatMap
{
    param
    (
        $MapPath
    )

    $Map = get-content $MapPath | convertfrom-json

    return $Map
}

Function New-StatDrilldownObject
{
    param (
        $dashuri = $null,
        $dashboard = $null,
        $includeVers = $null,
        $keepTime = $False, 
        $params = $null,
        $targetBlank = $False,
        $title = $null,
        $type = "disabled",
        $url = $null,
        $url_params = $null
    )
    $Return = [pscustomobject]@{
        "dashuri" = $dashuri
        "dashboard" = $dashboard
        "includeVers" = $includeVers
        "keepTime" = $keepTime
        "params" = $params
        "targetBlank" = $targetBlank
        "title" = $title
        "type" = $type
        "url" = $url
        "url_params" = $url_params
    }

    return $Return
}

Function New-StatColoringObject
{
    param (
        $color = "rgba(50,172,43,0.97)",
        $from = $null,
        $mode = "bg",
        $text = "up",
        $to = $null,
        $type = "regex"
    )

    return $null
}

Function New-StatColoringArray
{    
    return @((New-StatColoringObject -color "rgba(50,172,43,0.97)"), (New-StatColoringObject -color "#bf1b00" -text down))
}

Function New-StatLatLng
{
    param (
        $lat = 0,
        $lng = 0
    )

    return [pscustomobject]@{
        "lat" = $lat
        "lng" = $lng
    }
}

Function New-StatBGImage
{
    param
    (
        $edit = $false,
        $shared = $false,
        $value = $null
    )

    return [pscustomobject]@{
        "edit" = $edit
        "shared" = $shared
        "value" = $value
    }
}

Function New-StatMapBounds
{
    param 
    (
        $x1 = 0,
        $x2 = 0,
        $y1 = 0,
        $y2 = 2000
    )

    return @(@($x1, $y1), @($x2, $y2))
}

Function New-Stat2DGridRef
{
    param
    (
        $h = 16,
        $w = 24,
        $x = 0,
        $y = 0
    )

    return [pscustomobject]@{
        "h" = $h
        "w" = $w
        "x" = $x
        "y" = $y
    }
}

Function New-StatMapLegend
{
    param
    (
        $bgColor = "#FFFFFF",
        $fontSize = 11,
        $link = @(),
        $node = @(),
        $pos = $null,
        $textColor = "#000000"
    )

    return [pscustomobject]@{
        "bgColor" = $bgColor
        "fontSize" = $fontSize
        "link" = $link
        "node" = $node
        "pos" = $pos
        "textColor" = $textColor
    }
}

Function New-StatMapObject
{
    param
    (
        $bgColor = "#FFFFFF",
        $bgimage = (New-StatBGImage),
        $bounds  = (New-StatMapBounds),
        $boxZoom = $true,
        $center = $null,
        $colorMappingMap = @(),
        $colorMappings = @(),
        $fontSize = 11,
        $gridPos = (New-Stat2DGridRef),
        $id = 1,
        $imgType = "color",
        $isLocked = $false,
        $legends = (New-StatMapLegend),
        $lineWeight = 3,
        $linkFontSize = 11,
        $links = @(),
        $mapFit = $Disabled,
        $maxZoom = 10,
        $minZoon = -10,
        $mouseWheelZoom = $false,
        $nodeSize = 50,
        $realbgimage = $null,
        $saveCurView = $false,
        $sensors = @{},
        $series = @(),
        $showEditControl = $true,
        $showLegend = $false,
        $showZoomControl = $true,
        $targets = @(),
        $title = "Default",
        $type = "imagemap-panel",
        $valueMappings = @(),
        $version = 2,
        $zoom = $null
    )

    return [pscustomobject]@{
        "bgColor" = $bgColor 
        "bgimage" = $bgimage 
        "bounds" = $bounds  
        "boxZoom" = $boxZoom 
        "center" = $center 
        "colorMappingMap" = $colorMappingMap 
        "colorMappings" = $colorMappings 
        "fontSize" = $fontSize 
        "gridPos" = $gridPos 
        "id" = $id 
        "imgType" = $imgType 
        "isLocked" = $isLocked 
        "legends" = $legends 
        "lineWeight" = $lineWeight 
        "linkFontSize" = $linkFontSize 
        "links" = $links 
        "mapFit" = $mapFit 
        "maxZoom" = $maxZoom 
        "minZoom" = $minZoom 
        "mouseWheelZoom" = $mouseWheelZoom 
        "nodeSize" = $nodeSize 
        "realbgimage" = $realbgimage 
        "saveCurView" = $saveCurView 
        "sensors" = $sensors 
        "series" = $series 
        "showEditControl" = $showEditControl 
        "showLegend" = $showLegend 
        "showZoomControl" = $showZoomControl 
        "targets" = $targets 
        "title" = $title
        "type" = $type 
        "valueMappings" = $valueMappings 
        "version" = $version 
        "zoom" = $zoom 
    }
}

Function New-StatMapSensorObject 
{
    param
    (
        $bgColor = "rgba(64,64,64,1.000)",
        $coloring = (New-StatColoringArray),
        $dateFormat = "YYYY-MM-DD HH:mm:ss",
        $decimals = 2,
        $displayName = "default",
        $drilldown = (new-statdrilldown),
        $entity = $null,
        $fontColor = "rgba(255,255,255,1.000)",
        $fontSize = $null,
        $icon = $null,
        $id = $null,
        $index = $null,
        $labelPos = "bottom",
        $labelbgColor = "rgba(64,64,64,1.000)",
        $layerid = $null,
        $location = (New-StatLatLng),
        $markerType = "text",
        $metric = "ifOperStatus - Stage",
        $metricType = "string",
        $name = "interface",
        $nameOverride = $null,
        $nodeSize = $null,
        $refId = "B",
        $renderLabel = $False,
        $renderValue = $true,
        $showLabel = $False,
        $type = "node",
        $unitFormat = "none",
        $valueMappingIds = @(),
        $valuePreUnit = "",
        $valueUnit = $null,
        $visible = $true
    )

    return [pscustomobject]@{
        "bgColor" = $bgColor
        "coloring" = $coloring
        "dateFormat" = $dateFormat
        "decimals" = $decimals
        "displayName" = $displayName
        "drilldown" = $drilldown
        "entity" = $entity
        "fontColor" = $fontColor
        "fontSize" = $fontSize
        "icon" = $icon
        "id" = $id
        "index" = $index
        "labelPos" = $labelPos
        "labelbgColor" = $labelbgColor
        "layerid" = $layerid
        "location" = $location
        "markerType" = $markerType
        "metric" = $metric
        "metricType" = $metricType
        "name" = $name
        "nameOverride" = $nameOverride
        "nodeSize" = $nodeSize
        "refId" = $refId
        "renderLabel" = $renderLabel
        "renderValue" = $renderValue
        "showLabel" = $showLabel
        "type" = $type
        "unitFormat" = $unitFormat
        "valueMappingIds" = $valueMappingIds
        "valuePreUnit" = $valuePreUnit
        "valueUnit" = $valueUnit
        "visible" = $visible
    }
}

Function New-StatTargetField 
{
    param
    (
        $alias = "",
        $aliasOverride = $false,
        $datatype = "",
        $format = @{},
        $id = "",
        $options = @{},
        $polltype = "",
        $statsExpand = $false,
        $text = "",
        $value = ""
    )

    return [pscustomobject]@{
        "alias" = $alias
        "aliasOverride" = $aliasOverride
        "datatype" = $datatype
        "format" = $format
        "id" = $id
        "options" = $options
        "polltype" = $polltype
        "statsExpand" = $statsExpand 
        "text" = $text
        "value" = $value
    }
}

Function New-StatFieldFormat
{
    param 
    (
        $alias = "",
        $datatype = "",
        $value = ""
    )

    return [pscustomobject]@{
        "alias" = $alias
        "datatype" = $datatype
        "value" = $value
    }
}

Function New-StatFieldOptions
{
    param
    (
        $states = @{},
        $stats = @{}
    )

    return [pscustomobject]@{
        "states" = $states
        "stats" = $stats
    }
}

Function New-StatFieldFilter
{
    param
    (
        $action = "",
        $field = @{},
        $value = ""
    )

    return [pscustomobject]@{
        "action" = $action
        "field" = $field
        "value" = $value
    }
}

Function New-StatWidgetTarget
{
    param 
    (
        $field,
        $fields = @(),
        $filters = @(),
        $group_by = @{},
        $groups = @(),
        $hide = $false,
        $interval = $null,
        $label = @(),
        $limit = $null,
        $object = $null,
        $panelType = $null,
        $queryType = $null,
        $refId = $null,
        $sort = @(),
        $summary = $null,
        $version = 1 
    )

    return [pscustomobject]@{
        "field" = $field
        "fields" =  $fields
        "filters" = $filters
        "group_by" = $group_by
        "groups" = $groups
        "hide" = $hide
        "interval" = $interval
        "label" = $label
        "limit" = $limit
        "object" = $object
        "panelType" = $panelType
        "queryType" = $queryType
        "refId" = $refId
        "sort" = $sort
        "summary" = $summary
        "version" = $version
    }
}

Function Invoke-StatMapGenerationFromGroup
{
    param
    (
        $RootObjects,
        $GroupIDs,
        $GroupingMode = "OR"
    )

    if ($GroupIDs)
    {
        $tofs = $ofs

        $ofs = ","
        $filterstring = "groups=$GroupIDs&"

        $ofs = $tofs
    }

    $AllDevices = Get-StatDevice -allproperties

    $AllIPAddresses = Get-StatIpAddress -allproperties

    $AllGroupDevices = Get-StatDevice -allproperties -filterstring $filterstring

    Check-ModuleDependencies @("PowerJuniper", "PowerMist", "PowerPalo")

    foreach ($RootObject in $RootObjects)
    {
        $ConnectedDevices = @()
        $ConnectedDevices += Find-StatConnectedDevices -device $RootObject
        if ($RootObject.Vendor -match "(Juniper|Unknown)")
        {
            try
            {

                $JuniperConnectedDevices = Find-StatConnectedJuniperDevices -device $RootObject

                return $JuniperConnectedDevices

                $ConnectedDevices += $JuniperConnectedDevices
            }   
            catch
            {

            }

            try
            {
                $ConnectedDevices += Find-StatConnectedMistDevices -device $RootObject
            }
            catch
            {

            }
        }
        if ($RootObject.Vendor -match "(Palo|Unknown)")
        {
            try 
            {
                $ConnectedDevices += Find-StatConnectedPaloDevices -device $RootObject
            }
            catch
            {

            }
        }

        foreach ($ConnectedDevice in $ConnectedDevices)
        {
            
        }
    }

    return $AllDevices
}

Function Find-StatConnectedJuniperDevices
{
    param
    (
        $Device,
        $DeviceList
    )

    $IPAddresses = Get-StatIpAddress -allProperties | where {$_.deviceid -eq $Device.deviceid}
    $ManagementInterface = $null
    $IPAddressIndex = 0
    do
    {
        $IPAddressTemp = $IPAddresses[$IPAddressIndex]

        Write-Verbose "Trying IP $($IPAddressTemp.ipaddress)"

        $IPAddressIndex++

        try 
        {
            if (Test-HostStatus $IPAddressTemp.ipaddress -timeout 2000)
            {
                Write-Verbose "Host is alive"
                foreach ($StoredCredential in $StatStoredJuniperCredentials)
                {
                    try 
                    {
                        $ConnectedStatDevices = @()
                        $Result = (Get-JuniperLLDPNeighbors $IPAddressTemp.ipaddress `
                                                                          $StoredCredential)


                        $ConnectedDevices = $Result.'lldp-neighbors-information'.'lldp-neighbor-information'
                        

                        foreach ($ConnectedDevice in $ConnectedDevices)
                        {
                            $ConnectedDevice = ($ConnectedDeviceName -split "\.")[0]
                            $StatDevice = $DeviceList | where {$_.name -match $ConnectedDevice}
                            $Ports = Get-statdeviceports -deviceid $StatDevice.deviceid -allproperties

                            $ConnectedStatDevices += 
                        }

                        return $ConnectedStatDevices
                    }
                    catch
                    {

                    }
                }
            }
            else 
            {
                Write-Verbose "Host is offline"
                
            }
        }
        catch
        {

        }

        $SearchingForValidManagementInterface = ($ManagementInterface -eq $null) -and ($IPAddressIndex -lt $IPAddresses.Count)
    }
    while ($SearchingForValidManagementInterface)
}

Function Find-StatConnectedPaloDevices
{
    param
    (
        $Device
    )

}

Function Find-StatConnectedMistDevices
{
    param
    (
        $Device
    )

}

Function Optimize-StatMapNodeNeighbors
{
    param
    (
        $StatMapObject,
        $RootNode,
        $RecurseDepth,
        $XStep = 100,
        $YStep = 75,
        [switch]
        $reverse,
        $MovedNodes,
        $RootNodes,
        [switch]
        $Nested
    )

    Write-Debug "StatMapObject sensor count - $(($StatMapObject.sensors | gm | select -expandproperty name | where {$_ -match "_"}).count)"

    
    Write-Debug "RecurseDepth - $RecurseDepth"

    #$Sensors = $StatMapObject.sensors | gm | select -expandproperty name | where {$_ -match "_"}
    
    Write-Debug "Sensor count is $(($StatMapObject.sensors | gm | select -expandproperty name | where {$_ -match "_"}).count)"

    if ($MovedNodes -eq $Null)
    {
        Write-Debug "No moved nodes provided, fixing the root node in place"
        $MovedNodes = @($RootNode)
    }
    else {
        Write-Debug "there are $($MovedNodes.count) moved nodes"
    }

    if ($RootNodes -eq $Null)
    {
        Write-Debug "RootNode ID - $($RootNode.id)"
        $RootNodes = @($RootNode)
    }
    else
    {
        Write-Debug "RootNode Count - $($RootNodes.count)"
    }

    $NewlyMovedNodes = @()
    foreach ($CurrRootNode in $RootNodes)
    {

        $MoveableNodes = (Get-StatMapConnectedNodes $StatMapObject $CurrRootNode | where {$_.id -notin ($MovedNodes).id} | sort nameOverride,name)

        Write-Debug "There are $($MoveableNodes.count) moveable nodes attached to this one"

        $MoveableNodeCount = 0

        foreach ($MoveableNode in $MoveableNodes)
        {
            $MoveableNodeCount++
            if ($MoveableNode.nameOverride -ne "")
            {
                $NodeName = $MoveableNode.nameOverride
            }
            elseif ($MoveableNode.name -ne "") {
                $NodeName = $MoveableNode.name
            }
            else{
                $NodeName = $MoveableNode.id
            }

            $FindingFit = $false

            $Left = ($CurrRootNode.location.lng -le $RootNode.location.lng) -or ($MoveableNodeCount -eq 1)

            $iter = 0

            $MoveableNode.location.lat = [int]($CurrRootNode.location.lat + ($YStep * -1)) 

            do
            {

                if ($Left)
                {
                    $X = $XStep * $Iter * -1
                }
                else
                {
                    $X = $XStep * $Iter
                }

                $Iter++
                if (($MoveableNodes.count -ne $null) -or $FindingFit)
                {
                    Write-Debug "more than one node in interation or second iteration"
                    $MoveableNode.location.lng = [int]($RootNode.location.lng + $X)
                }
                else {
                    Write-Debug "Only one node in interation"
                    $MoveableNode.location.lng = [int]($CurrRootNode.location.lng)
                }
                
                Write-Debug "Checking if $NodeName fits at location X - $($MoveableNode.location.lng) - Y - $($MoveableNode.location.lat)"

                if (-not (Check-StatMapNodeCollision $MoveableNode ($MovedNodes + $NewlyMovedNodes) ($XStep/2) ($YStep/2)))
                {
                    $NewlyMovedNodes += $MoveableNode
                    $FindingFit = $false
                }
                else
                {
                    $FindingFit = $True
                }
            }
            while ($FindingFit)
        }
        $MovedNodes = $NewlyMovedNodes + $MovedNodes
    }

    foreach ($MovedNode in $NewlyMovedNodes)
    {
        $StatMapObject.sensors."$($MovedNode.id)" = $MovedNode
    }


    if ($RecurseDepth -gt 1)
    {

        $NewDepth = ($RecurseDepth - 1)
        Write-Verbose "depth is $RecurseDepth, going one layer deeper - $NewDepth"
        Write-Debug "Normal ordering for next layer"
        $Return = Optimize-StatMapNodeNeighbors -StatMapObject $StatMapObject `
                                                       -RootNode $RootNode `
                                                       -RootNodes $NewlyMovedNodes `
                                                       -RecurseDepth $NewDepth `
                                                       -MovedNodes $MovedNodes `
                                                       -Nested

        if ($Return -ne $null)
        {
            $StatMapObject = $Return.SMO
            $MovedNodes = $Return.Moved
        }
    }
    else {
        
    }


    if ($Nested)
    {
        Write-Debug "Returning SMO and moved info"
        return [pscustomobject]@{"SMO" = $StatMapObject; "Moved" = $MovedNodes}
    }
    else {
        Write-Debug "Returning only SMO"
        return $StatMapObject
    }
}

Function Check-StatMapNodeCollision
{
    param
    (
        $Node,
        $CheckNodes,
        $ToleranceX = 25,
        $ToleranceY = 10
    )

    $Collision = $false

    foreach ($CheckNode in $CheckNodes)
    {
        $Collision =(($Node.location.lat -lt ($CheckNode.location.lat + $ToleranceX)) -and `
                     ($Node.location.lat -gt ($CheckNode.location.lat - $ToleranceX)) -and `
                     ($Node.location.lng -lt ($CheckNode.location.lng + $ToleranceY)) -and `
                     ($Node.location.lng -gt ($CheckNode.location.lng - $ToleranceY))) -or `
                     $Collision

    }

    Write-Debug "$($Node.id) Collision is $Collision"

    return $Collision
}

Function Get-StatMapGridSnap
{
    param
    (
        $StatMapObject,
        $GridSize = 25
    )

}

Function Get-StatMapConnectedNodes
{
    param
    (
        $StatMapObject,
        $Node,
        $Depth = 1
    )

    $ConnectedNodes = @($Node)

    for ($x = 0; $x -lt $Depth; $x++)
    {
        foreach ($ConnectedNode in $ConnectedNodes)
        {
            $ConnectedLines = Get-StatMapConnectedLines $StatMapObject $ConnectedNode
            #$ConnectedLines
            $ConnectedNodes = ($ConnectedNodes + ($ConnectedLines | %{Get-StatMapLineNodeConnections $StatMapObject $_} `
                                                                  | where {$_.id -notin $ConnectedNodes.id})) `
                                                                  | where {($_.id -ne $Node.id)}
        }
    }

    return $ConnectedNodes
}

Function Get-StatMapConnectedLines
{
    param
    (
        $StatMapObject,
        $Node
    )

    $PropertyString = 'snapPoints | %{if ($_ -ne $null){$_ | gm | select -expandproperty name}}'
    $FindValue = $Node.id
    $Operator = "-eq"

    $Conditions = @(
        [pscustomobject]@{
            "Property" = $PropertyString
            "FindValue" = """$FindValue"""
            "Operator" = $Operator
        }
    )

    return Get-StatMapSensorsFiltered $StatMapObject $Conditions
}

Function Get-StatMapLineNodeConnections
{
    param
    (
        $StatMapObject,
        $Line
    )

    $LineConnections = $Line.snapPoints | gm | select -expandproperty name | where {$_ -match "_"}

    $tofs = $ofs
    $ofs = ""","""

    $Return = $LineConnections | %{
        $StatMapObject.Sensors."$_"
    }

    $ofs = $tofs

    return $Return
}

Function Get-StatMapSensorsFiltered
{
    param
    (
        $StatMapObject,
        $Conditions,
        $ConditionLink = "or"
    )

    $Sensors = $StatMapObject.sensors | gm | where {$_.MemberType -eq "NoteProperty"} | select -expandproperty name 

    $MatchingNodes = @()

    foreach ($Condition in $Conditions)
    {
        $ConditionMatchNodes = @()

        foreach ($Sensor in $Sensors)
        {
            $ExpressionString =  '($StatMapObject'
            $ExpressionString += ".sensors.'$($Sensor)'.$($Condition.Property)) "
            $ExpressionString += "$($Condition.Operator) "
            $ExpressionString += "$($Condition.FindValue)"
            if (invoke-expression $ExpressionString)
            {
                $ConditionMatchNodes += $StatMapObject.sensors."$Sensor"
            }
        }

        if ($ConditionLink -eq "or")
        {
            $MatchingNodes += $ConditionMatchNodes
        }
        elseif ($ConditionLink -eq "and")
        {
            ##Not implemented because lazy
        }
    }

    return $MatchingNodes
}

Function Find-StatConnectedDevices
{
    param
    (
        $deviceid,
        $layer = 2
    )

    $AllIPAddresses = Get-StatIpAddress -allproperties

    if ($layer -eq 2)
    {
        $ConnectedIPs = Get-StatIPPortInfo -deviceid $deviceid -allproperties
        return $AllIPAddresses | where {$_.ipaddress -in $ConnectedIPs.ip} | select -expandproperty deviceid
    }
    elseif ($layer -eq 3)
    {
        return $null
    }
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