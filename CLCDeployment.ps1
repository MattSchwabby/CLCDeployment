<#

CLCVMDeployment.ps1

PowerShell script to create multiple CenturyLink Cloud Servers and stagger their creation to batches of 5 servers at a time.

This script will monitor the status of VM creation requests and will automatically submit a new request if a server build fails
The operation will also monitor the number of available IP addresses for the specified network. A new network will be claimed if
available IP addresses fall to zero.

To run, execute the .ps1 file by right-clicking and selecting run in PowerShell, or open it in the PowerShell ISE and click the
play button (or, press f8 when the script is open in the ISE).

The user will be prompted to enter an API V1 Key, an API V1 password, as well as their control portal credentials (for API V2).

They will then be prompted for the sub account to create the servers in, as well as data center, desired server template to use,
server group to create the VMs in, which network to use, amount of RAM and CPU to assign to each server, as well as a name to use
for the Virtual Machines.

The operation will commence once all data is collected from the user. Status will be displayed in the PowerShell console, as well as
logged at C:\Users\Public\CLC. A spreadsheet containing information for each of the Virtual Machines will also be exported to the same
file path.

Author: Matt Schwabenbauer
Date Created: July 19, 2016
Contact: Matt.Schwabenbauer@ctl.io

#>

# API V1 Login to prompt for user creds
$APIKey = Read-Host 'Please enter your API Key'
$APIPass = Read-Host 'Please enter your API Password'
$body = @{APIKey = $APIKey; Password = $APIPass } | ConvertTo-Json
$restreply = Invoke-RestMethod -uri "https://api.ctl.io/REST/Auth/Logon/" -ContentType "Application/JSON" -Body $body -Method Post -SessionVariable session 
$global:session = $session

# API V2 Login to prompt for user creds
$global:CLCV2cred = Get-Credential -message "Please enter your Control portal Logon" -ErrorAction Stop 
$body = @{username = $CLCV2cred.UserName; password = $CLCV2cred.GetNetworkCredential().password} | ConvertTo-Json 
$global:resttoken = Invoke-RestMethod -uri "https://api.ctl.io/v2/authentication/login" -ContentType "Application/JSON" -Body $body -Method Post 
$HeaderValue = @{Authorization = "Bearer " + $resttoken.bearerToken}

# Functions
function createNetwork
{
    param(
    [Parameter(Mandatory=$true)][string]$alias,
    [Parameter(Mandatory=$false)][string]$dataCenter
    )

    $uri = "https://api.ctl.io/v2-experimental/networks/$alias/$dataCenter/claim"

    $networkResult = Invoke-RestMethod -Uri $uri -ContentType "Application/JSON" -Headers $HeaderValue -Method Post

    $networkInProgress = $false
    $newNetwork = $false
    $retry = 0
    $retries = 5
    while (-not $newNetwork)
    {
        if (-not $networkInProgress)
        {
            "Creating a new network in $dataCenter."
            $uri = "https://api.ctl.io/v2-experimental/networks/$alias/$dataCenter/claim"
            $networkResult = Invoke-RestMethod -Uri $uri -ContentType "Application/JSON" -Headers $HeaderValue -Method Post
            $operationID = $networkResult.operationId
            "API operation issued to create a new network with an Operation ID of $OperationID."
            $networkInProgress = $true
            start-sleep -s 10
        }

        $networkStatusURL = "https://api.ctl.io" + $networkResult.uri

        $networkStatusResult = Invoke-RestMethod -Uri $networkStatusURL -ContentType "Application/JSON" -Headers $HeaderValue -Method Get

        $operationStatus = $networkStatusResult.status

        if ($OperationStatus -eq "failed")
        {
            if ($retry -eq $retries)
            {
                "Reached the maximum amount of $retries retry attempts. Exiting the operation."
                Return "failed"
                $newNetwork = $true
                exit
            }
            $retry++
            "Network creation failed. Retrying attempt $retry out of $retries."
            "Creating a new network in $dataCenter."
            $networkInProgress = $false
        }
        elseif ($OperationStatus -eq "succeeded")
        {
            $networkID = $networkStatusresult.summary.links.id
            "Network operation successful."
            Return $networkID
            $newNetwork = $true
        }

        "The status of operation $OperationID is $operationStatus. Waiting 30 seconds and then will query again."
        Start-sleep -s 30
    }
}

# Create a name variable for logging purposes
$name = $CLCV2cred.UserName
if ($name = $null)
{
    $body = $body | ConvertFrom-Json
    $name = $body.username
}

#Create directory for log file
New-Item -ItemType Directory -Force -Path "C:\Users\Public\CLC"

# Create date for log file
$month = Get-Date -Uformat %b
$day = Get-Date -Uformat %d
$year = Get-Date -Uformat %Y
$hours = Get-Date -Uformat %H
$minutes = Get-Date -Uformat %M
$seconds = Get-Date -Uformat %S
$filename = "C:\Users\Public\CLC\CLCDeploymentLog-$month-$day-$year-$hours-$minutes-$seconds.txt"
$csvfilename = "C:\Users\Public\CLC\CLCDeploymentLog-$month-$day-$year-$hours-$minutes-$seconds.csv"
$time = Get-Date -Uformat %T
$datetime = "$month $day, $year - $time"

# Get account alias
$alias = Read-Host 'Please enter the alias of the account you wish to build the servers in. This is case sensitive' <# The alias of the account you are building the servers in #>
Start-Sleep -s 1

# Get which data center we will be working in from the user
$dataCenter = Read-Host "Please enter which data center you wish to build the servers in. EX. - VA1, UC1, WA1, NY1, CA3. A full list of available data centers can be found at status.ctl.io This is case sensitive"

# Get available templates
Start-Sleep -s 1
$url = "https://api.ctl.io/v2/datacenters/$alias/$dataCenter/deploymentCapabilities"
$result = Invoke-RestMethod -Uri $url -ContentType "Application/JSON" -Headers $HeaderValue -Method Get
$templates = $result.templates.name
Write-Verbose -message "The available server templates for $alias in $dataCenter are" -verbose
$templates

# Get user input for which template they want to use #>
$sourceServerID = Read-Host "Please copy and paste the Template ID for the type of server you wish to create from the list above. Ex. - WIN2012R2DTC-64"
Start-Sleep -s 1

# Get available groups
$JSON = @{AccountAlias = $alias; Location = $dataCenter} | ConvertTo-Json 
$result = Invoke-RestMethod -uri "https://api.ctl.io/REST/Server/GetAllServersForAccountHierarchy/" -ContentType "Application/JSON" -Method Post -WebSession $session -Body $JSON 
$HardwareGroups = $result.AccountServers.Servers.HardWareGroupUUID
Write-Verbose -message "The available server groups for $alias in $dataCenter are" -verbose
Start-Sleep -s 1
$HardwareGroups = $HardWareGroups | Select-Object -unique
Foreach ($i in $HardwareGroups)
{
    $url = "https://api.ctl.io/v2/groups/$alias/$i"
    $result = Invoke-RestMethod -Uri $url -ContentType "Application/JSON" -Headers $HeaderValue -Method Get
    $result
}

# Get desired group
Write-Verbose "NOTE: Only groups with existing VMs in them will be listed. The group ID for other groups can be retrieved from the URL while in the control portal UI for a desired group. Example: control.ctl.io/manage#/uc1/group/GROUPID." -verbose
$groupID = Read-Host "Please copy and paste the ID of the server group you wish to create these servers in from the list above"

# Get desired network
$url = "https://api.ctl.io/v2-experimental/networks/$alias/$dataCenter"
$result = Invoke-RestMethod -Uri $url -ContentType "Application/JSON" -Headers $HeaderValue -Method Get
$networks = $result.id

Write-Verbose "The available networks in $datacenter are:" -Verbose
$result

foreach ($i in $networks)
{
    $network = $i+"?ipaddresses=free"
    $url = "https://api.ctl.io/v2-experimental/networks/$alias/$dataCenter/$network"
    $result = Invoke-RestMethod -Uri $url -ContentType "Application/JSON" -Headers $HeaderValue -Method Get
    $ipcount = $result.ipAddresses.count
    Write-Verbose "Network $i has $ipcount IP addresses available." -Verbose
}
$networkID = Read-Host "Please copy and paste the ID of the network you wish to create these servers in from the list above"

#Get desired CPU count
$cpu = Read-Host "Please enter the number of CPUs for the servers to have, up to 16"
if ($cpu -gt 16)
{
    DO
    {
        $cpu = Read-Host "Please enter the number of CPUs for the servers to have, up to 16"
    } While ($cpu -gt 16)
}

# Get desired RAM amount
$memoryGB = Read-Host "Please enter the amount of RAM you wish the machines to have, up to 128 GB"
if ($memoryGB -gt 128)
{
    DO
    {
        $memoryGB = Read-Host "Please enter the amount of RAM you wish the machines to have, up to 128 GB"
    } While ($memoryGB -gt 128)
}

# Set server type to standard
$type = "standard"

# Get desired VM Name
$DNSName = Read-Host "Please enter a name for the servers to create. Alphanumeric characters and dashes only. Must be between 1-8 characters depending on the length of the account alias. The combination of account alias and server name here must be no more than 10 characters in length. (This name will be appended with a two digit number and prepended with the datacenter code and account alias to make up the final server name.)"
if ($DNSName.length -gt 6)
{
    DO
    {
        $DNSName = Read-Host "Please enter a name for the servers to create. Alphanumeric characters and dashes only. Must be between 1-8 characters depending on the length of the account alias. The combination of account alias and server name here must be no more than 10 characters in length. (This name will be appended with a two digit number and prepended with the datacenter code and account alias to make up the final server name.)"
    } While ($DNSName.length -gt 6)
} #end if $DNSName.length

# Create the JSON body

$JSON = @{name = $DNSName; description = "API server created by $name"; groupID = $groupID; networkID = $networkID; sourceServerId = $sourceServerID; cpu = $cpu; memoryGB = $memoryGB; type = $type} | ConvertTo-Json

# Set the URL for the server creation API Call. Don't change this.

$url = "https://api.ctl.io/v2/servers/$alias/"

# Code to stagger the server builds and divide them into groups, and track them all.
$total = 0
$total2 = 0

# Get the number of servers to build from the user.
$total = Read-Host "Please enter the number of servers to build"

# Validate the user input.
try
{
    $validate = $total/2
    $correctTotal = $true
}
catch
{
    "Input was not in the form of a number."
    $correctTotal = $false
}
while (-not $correctTotal)
{
    try
    {
        $total = Read-Host "Please enter the number of servers to build"
        $validate = $total/2
        $correctTotal = $true
    }
    catch
    {
        "Input was not in the form of a number."
        $correctTotal = $false
    }
}


$total = [int]$total
$total2 = $total + 1
$counter = 1

if ($total -gt 5)
{
    $numberOfGroups = $total/5

    if ($numberOfGroups % 2 -ne 0)
    {
        $numberOfGroups++
        $numberOfGroups = "{0:N0}" -f $numberOfGroups
        $numberOfGroups = [int]$numberOfGroups
    }
} # end if total
else
{
    $numberOfGroups = 1
}

$groups = @()
$groupcounter = 1
$resultURLS = @()
$result = $null
$statusResult = $null
$selfResult = $null
$serverName = $null

# Log the start of server creation operation
$time = Get-Date -Uformat %T
$datetime = "$month $day, $year - $time"
Add-Content $filename "$datetime - Creation of $total servers requested by $name - Template: $sourceServerID | Group: $groupID | CPUs: $cpu | RAM: $memoryGB | Name: $DNSName"

# Begin Main Operation
Write-Verbose "$datetime - Beginning creation of $total servers requested by $name - Template: $sourceServerID | Group: $groupID | CPUs: $cpu | RAM: $memoryGB | Name: $DNSName"

DO
{
    $retry = 0
    $retries = 5
    $statusURL = $null
    $selfURL = $null
    $secondsDelay = 10
    $completed = $false
    while (-not $completed)
    {
        try
        {
            while (-not $networkCheck)
            {
                try
                {
                    # Get desired network
                    $network = $i+"?ipaddresses=free"
                    $networkURL = "https://api.ctl.io/v2-experimental/networks/$alias/$dataCenter/$network"
                    $networkResult = Invoke-RestMethod -Uri $url -ContentType "Application/JSON" -Headers $HeaderValue -Method Get
                } #end try
                catch
                {
                    $networkCheck = $false
                } #end catch
                $networks = $networkResult.id
                $ipcount = $result.ipAddresses.count
                if ($ipcount -lt 1)
                {
                    $networkCheck = $true
                }
                else
                {
                    $dateTime = "$month $day, $year - $time"
                    "$dateTime Network $networkID is out of free IP addresses. Executing command to create a new network."
                    Add-Content $filename "$dateTime Network $networkID is out of free IP addresses. Executing command to create a new network."

                    $created = $false
                    while (-not $created)
                    {
                        $networkID = createnetwork -alias $alias -dataCenter $dataCenter
                        if ($networkID -eq "failed")
                        {
                            "Network creation failed. Retrying."
                            $created = $false
                        } #end if failed
                        $dateTime = "$month $day, $year - $time"
                        "$dateTime Network $networkID is out of free IP addresses. Executing command to create a new network."
                        Add-Content $filename "$dateTime Network $networkID has been created."
                        $created = $true
                    } # end while not created
                    $networkCheck = $false
                }
            } # end while not networkcheck
            $JSON = @{name = $DNSName; description = "API server created by $name"; groupID = $groupID; networkID = $networkID; sourceServerId = $sourceServerID; cpu = $cpu; memoryGB = $memoryGB; type = $type} | ConvertTo-Json
            $result = Invoke-RestMethod -Uri $url -ContentType "Application/JSON" -Headers $HeaderValue -Body $JSON -Method Post
            $completed = $true
            $statusURL = "https://api.ctl.io" + $result.links.href[0]
            $selfURL = "https://api.ctl.io" + $result.links.href[1]
            $URLS = @{status=$statusURL;self=$selfURL}
            $targetURLS = new-object PSObject -property $URLS
            $resultURLS += $targetURLS
            $selfResult = Invoke-RestMethod -Uri $selfURL -ContentType "Application/JSON" -Headers $HeaderValue -Method Get
            $serverName = $selfResult.name
            $time = Get-Date -Uformat %T
            $dateTime = "$month $day, $year - $time"
            "$dateTime Command to create server $counter executed. Name: $serverName"
            Add-Content $filename "$dateTime Command to create server $counter executed. Name: $serverName"
        }
        catch
        {
            $dateTime = "$month $day, $year - $time"
            "$dateTime Unable to execute command to create server $counter. Retrying in $secondsDelay seconds."
            Add-Content $filename "$dateTime Unable to execute command to create server $counter. Retrying in $secondsDelay seconds."
            Start-Sleep $secondsDelay
        }
    } # end while not completed

    $targetProperties = @{$groupcounter=$servername}
    $targetObject = New-Object PSObject -Property $TargetProperties
    $groups += $targetObject

    if ($counter % 5 -eq 0 -or $counter -eq $total)
    {
        $count = $groups.$groupcounter | measure
        $completeTarget = $count.count
        "$counter server creation commands executed, beginning completion status monitoring operation of last batch."
        DO
        {
            $selfResults = @()
            forEach ($i in $resultURLS)
            {
                $statusURL = $i.status
                $selfURL = $i.self
                $statusResult = Invoke-RestMethod -Uri $statusURL -ContentType "Application/JSON" -Headers $HeaderValue -Method Get
                $selfResult = Invoke-RestMethod -Uri $selfURL -ContentType "Application/JSON" -Headers $HeaderValue -Method Get
                $serverName = $selfResult.name
                $status = $statusResult.status

                #Create replacement server if a build has failed.
                if ($status -eq "failed")
                {
                    "$datetime Command to create server $serverName failed."
                    Add-Content $filename "$datetime Command to create server $serverName failed."
                    $newURLS = $resultURLS | Where-Object {$_.status -ne $i.status}
                    $resultURLS = $newURLS
                    $statusURL = $null
                    $selfURL = $null

                    $completed = $false
                    while (-not $completed)
                    {
                        try
                        {
                            while (-not $networkCheck)
                            {
                                try
                                {
                                    # Get desired network
                                    $network = $i+"?ipaddresses=free"
                                    $networkURL = "https://api.ctl.io/v2-experimental/networks/$alias/$dataCenter/$network"
                                    $networkResult = Invoke-RestMethod -Uri $url -ContentType "Application/JSON" -Headers $HeaderValue -Method Get
                                } #end try
                                catch
                                {
                                    $networkCheck = $false
                                } #end catch
                                $networks = $networkResult.id
                                $ipcount = $result.ipAddresses.count
                                if ($ipcount -lt 1)
                                {
                                    $networkCheck = $true
                                }
                                else
                                {
                                    $dateTime = "$month $day, $year - $time"
                                    "$dateTime Network $networkID is out of free IP addresses. Executing command to create a new network."
                                    Add-Content $filename "$dateTime Network $networkID is out of free IP addresses. Executing command to create a new network."

                                    $created = $false
                                    while (-not $created)
                                    {
                                        $networkID = createnetwork -alias $alias -dataCenter $dataCenter
                                        if ($networkID -eq "failed")
                                        {
                                            "Network creation failed. Retrying."
                                            $created = $false
                                        } #end if failed
                                        $dateTime = "$month $day, $year - $time"
                                        "$dateTime Network $networkID is out of free IP addresses. Executing command to create a new network."
                                        Add-Content $filename "$dateTime Network $networkID has been created."
                                        $created = $true
                                    } # end while not created
                                    $networkCheck = $false
                                }
                            } # end while not networkcheck
                            $JSON = @{name = $DNSName; description = "API server created by $name"; groupID = $groupID; networkID = $networkID; sourceServerId = $sourceServerID; cpu = $cpu; memoryGB = $memoryGB; type = $type} | ConvertTo-Json

                            $result = Invoke-RestMethod -Uri $url -ContentType "Application/JSON" -Headers $HeaderValue -Body $JSON -Method Post
                            $completed = $true
                            $statusURL = "https://api.ctl.io" + $result.links.href[0]
                            $selfURL = "https://api.ctl.io" + $result.links.href[1]
                            $URLS = @{status=$statusURL;self=$selfURL}
                            $targetURLS = new-object PSObject -property $URLS
                            $resultURLS += $targetURLS
                            $selfResult = Invoke-RestMethod -Uri $selfURL -ContentType "Application/JSON" -Headers $HeaderValue -Method Get
                            $serverName = $selfResult.name
                            $time = Get-Date -Uformat %T
                            $datetime = "$month $day, $year - $time"
                            "$datetime Command to create replacement server executed. Name: $servername"
                            Add-Content $filename "$datetime Command to create replacement server executed. Name: $servername"
                        }
                        catch
                        {
                            $dateTime = "$month $day, $year - $time"
                            "$dateTime Unable to execute command to create replacement server for $serverName. Retrying in $secondsDelay seconds."
                            Add-Content $filename "$dateTime Unable to execute command to create replacement server for $serverName. Retrying in $secondsDelay seconds."
                            Start-Sleep $secondsDelay
                        }
                    } # end while not completed

                }
                $serverStatus = $selfResult.status
                $selfResults += $selfResult.status
                "Server $serverName currently has a status of $serverStatus."
            } # end forEach StatusURLS
            $complete = 0
            forEach ($i in $selfResults)
            {
                if ($i -eq "active")
                {
                    $complete++
                } # end if underConstruction
                <#elseif ($i -eq "failed")
                {
                    "A server build failed. Terminating Operation."
                    exit
                }#>
                # THIS IS WHERE YOU WOULD ADD AN ELSE IF FAILURE
            } # end foreach $statusResults
            if ($complete -lt $completeTarget)
            {
                "Not creating any further servers due to a previous request still being under construction."
                "Pausing for thirty seconds."
                Start-Sleep -s 30
            }
        } while ($complete -lt $completeTarget)
        $time = Get-Date -Uformat %T
        $datetime = "$month $day, $year - $time"

        $selfURLS = $resultURLS.self
        forEach ($i in $selfURLS)
        {
            $selfResult = Invoke-RestMethod -Uri $i -ContentType "Application/JSON" -Headers $HeaderValue -Method Get
            $selfResults += $selfResult.status
            $serverName = $selfResult.name
            $serverStatus = $selfResult.status
            "$datetime Command to create server $serverName completed | Group: $groupID | CPUs: $cpu | RAM: $memoryGB | Template: $sourceServerID | Network: $networkID | Status: $serverStatus"
            Add-Content $filename "$datetime Command to create server $serverName completed | Group: $groupID | CPUs: $cpu | RAM: $memoryGB | Template: $sourceServerID | Network: $networkID | Status: $serverStatus"

            #export server details to CSV
            $row = new-object PSOBJECT
            $row | Add-Member -MemberType NoteProperty -name "Server Name" -value $selfResult.name
            $row | Add-Member -MemberType NoteProperty -name "Location" -value $selfResult.locationID
            $row | Add-Member -MemberType NoteProperty -name "Operating System" -value $selfResult.osType
            $row | Add-Member -MemberType NoteProperty -name "CPUs" -value $selfResult.details.cpu
            $row | Add-Member -MemberType NoteProperty -name "RAM" -value $selfResult.details.memoryMB
            $row | Add-Member -MemberType NoteProperty -name "Storage" -value $selfResult.details.storageGB
            $row | Add-Member -MemberType NoteProperty -name "Group ID" -value $selfResult.groupID
            $row | Add-Member -MemberType NoteProperty -name "IP Address" -value $selfResult.details.ipAddresses.internal
            $row | Add-Member -MemberType NoteProperty -name "Created Datetime" -value $selfResult.changeinfo.createddate
            $row | Add-Member -MemberType NoteProperty -name "Created By" -value $selfResult.changeinfo.createdby
            $row | Add-Member -MemberType NoteProperty -name "Description" -value $selfResult.description
            $row | export-csv $csvfilename -append -notypeinformation -force

        } # end forEach StatusURLS 
        $resultURLS = @()
        $groupcounter++
    } # end if $counter % 5 -eq 0
    $counter++
} while ($counter -lt $total2)
$groupcounter=1
$numberOfGroups2 = $numberofGroups+1
do
{
    "Group $groupcounter"
    $groups.$groupcounter
    $groupcounter++
}while ($groupcounter -lt $numberofGroups2)

# Log the completion of the operation
Add-Content $filename "$datetime - Completed creation of $total servers requested by $name - Template: $sourceServerID | Group: $groupID | CPUs: $cpu | RAM: $memoryGB | Name: $DNSName"