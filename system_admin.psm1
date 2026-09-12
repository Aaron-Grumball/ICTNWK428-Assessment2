# ICTNWK428 Assessment 2
# Windows Server 2022 administration module
# Author: Aaron Grumball
#
# This module contains functions used to remotely configure
# and manage the Mick And Macks Pies Windows Server environment.
# Runs a PowerShell command on the target server
function Invoke-ServerCommand {
    param (
        [string]$ComputerName,
        [scriptblock]$ScriptBlock,
        [PSCredential]$Credential
    )

    try {
        Invoke-Command `
            -ComputerName $ComputerName `
            -Credential $Credential `
            -ScriptBlock $ScriptBlock `
            -ErrorAction Stop
    }
    catch {
        Write-Host "Unable to execute the command on $ComputerName."
        Write-Host $_.Exception.Message
    }
}

# Records an activity in the server log file
function Write-ServerLog {
    param (
        [string]$ComputerName,
        [string]$Task,
        [PSCredential]$Credential
    )

    try {
        Invoke-Command `
            -ComputerName $ComputerName `
            -Credential $Credential `
            -ArgumentList $Task `
            -ScriptBlock {
                param ($Task)

                $logDirectory = "C:\myLogs"
                $logFile = "C:\myLogs\system_admin.log"

                # Creates the log directory if it does not already exist
                if (!(Test-Path $logDirectory)) {
                    New-Item -ItemType Directory -Path $logDirectory
                }

                # Creates the log entry with the current date and time
                $dateTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                $logEntry = "$dateTime - $Task"

                Add-Content -Path $logFile -Value $logEntry
            } `
            -ErrorAction Stop
    }
    catch {
        Write-Host "Unable to write to the server log file."
        Write-Host $_.Exception.Message
    }
}

# Tests the remote connection and logging
function Test-ServerConnection {
    param (
        [string]$ComputerName,
        [PSCredential]$Credential
    )

    try {
        Invoke-Command `
            -ComputerName $ComputerName `
            -Credential $Credential `
            -ScriptBlock {
                Write-Output "Remote connection successful."
                Write-Output "Computer Name: $env:COMPUTERNAME"
            } `
            -ErrorAction Stop

        Write-ServerLog `
            -ComputerName $ComputerName `
            -Task "Test server connection" `
            -Credential $Credential
    }
    catch {
        Write-Host "Unable to connect to $ComputerName."
        Write-Host $_.Exception.Message
    }
}


# Promotes the target Windows Server to a Domain Controller
function Install-DomainController {
    param (
        [string]$ComputerName
    )

    # Prompts the user for administrator credentials
    $credential = Get-Credential

    try {
        Invoke-Command `
            -ComputerName $ComputerName `
            -Credential $credential `
            -ScriptBlock {

                $domainName = "AGmicksandmacks.local"

                # Checks whether the server is already a Domain Controller
                $domainController = Get-WindowsFeature AD-Domain-Services

                if ($domainController.Installed) {
                    Write-Output "Active Directory Domain Services is already installed."
                    Write-Output "Server may already be configured as a Domain Controller."
                }
                else {
                    # Installs the Active Directory Domain Services role
                    Install-WindowsFeature `
                        -Name AD-Domain-Services `
                        -IncludeManagementTools

                    Import-Module ADDSDeployment

                    # Prompts for the Directory Services Restore Mode password
                    $safeModePassword = Read-Host `
                        "Enter the Directory Services Restore Mode password" `
                        -AsSecureString

                    # Promotes the server and creates the required domain
                    Install-ADDSForest `
                        -DomainName $domainName `
                        -DomainNetbiosName "AGMICKSANDMACKS" `
                        -InstallDns:$true `
                        -SafeModeAdministratorPassword $safeModePassword `
                        -Force:$true
                }
            } `
            -ErrorAction Stop

        Write-ServerLog `
            -ComputerName $ComputerName `
            -Task "Domain Controller configuration checked or performed" `
            -Credential $credential
    }
    catch {
        Write-Host "Unable to configure $ComputerName as a Domain Controller."
        Write-Host $_.Exception.Message
    }
}

# Starts a PowerShell remote session with a target computer
function Start-PSSession {
    param (
        [string]$TargetIPAddress
    )

    # Prompts the user for administrator credentials
    $credential = Get-Credential

    try {
        Enter-PSSession `
            -ComputerName $TargetIPAddress `
            -Credential $credential `
            -ErrorAction Stop

        # Records the successful remote session in the server log
        Write-ServerLog `
            -ComputerName $TargetIPAddress `
            -Task "PowerShell remote session completed" `
            -Credential $credential
    }
    catch {
        Write-Host "Unable to connect to $TargetIPAddress."
        Write-Host $_.Exception.Message
    }
}

# Creates a new Organizational Unit in Active Directory
function Add-NewOrganizationalUnit {
    param (
        [string]$ComputerName,
        [string]$OUName,
        [PSCredential]$Credential
    )

    try {
        Invoke-Command `
            -ComputerName $ComputerName `
            -Credential $Credential `
            -ArgumentList $OUName `
            -ScriptBlock {
                param ($OUName)

                $domainPath = "DC=AGmicksandmacks,DC=local"
                $ouPath = "OU=$OUName,$domainPath"

                # Checks whether the OU already exists
                $existingOU = Get-ADOrganizationalUnit `
                    -Filter "DistinguishedName -eq '$ouPath'" `
                    -ErrorAction SilentlyContinue

                if ($existingOU) {
                    Write-Output "OU '$OUName' already exists."
                }
                else {
                    New-ADOrganizationalUnit `
                        -Name $OUName `
                        -Path $domainPath `
                        -ProtectedFromAccidentalDeletion $true

                    Write-Output "OU '$OUName' created successfully."
                }
            } `
            -ErrorAction Stop

        Write-ServerLog `
            -ComputerName $ComputerName `
            -Task "Checked or created OU $OUName" `
            -Credential $Credential
    }
    catch {
        Write-Host "Unable to create OU $OUName."
        Write-Host $_.Exception.Message
    }
}

# Creates Active Directory users from a CSV file
function Add-UsersFromCSV {
    param (
        [string]$ComputerName,
        [string]$CSVPath,
        [string]$OUName,
        [PSCredential]$Credential
    )

    try {
        # Reads the CSV file from the client
        $users = Import-Csv -Path $CSVPath

        Invoke-Command `
            -ComputerName $ComputerName `
            -Credential $Credential `
            -ArgumentList $users, $OUName `
            -ScriptBlock {
                param (
                    $users,
                    $OUName
                )

                $domainPath = "DC=AGmicksandmacks,DC=local"
                $ouPath = "OU=$OUName,$domainPath"

                foreach ($user in $users) {
                    $firstName = $user.FirstName
                    $lastName = $user.LastName
                    $samAccountName = ($firstName + "." + $lastName).ToLower()

                    # Checks whether the user already exists
                    $userExists = Get-ADUser `
                        -Filter "SamAccountName -eq '$samAccountName'" `
                        -ErrorAction SilentlyContinue

                    if ($userExists) {
                        Write-Output "User '$samAccountName' already exists."
                    }
                    else {
                        $password = ConvertTo-SecureString `
                            "Password1" `
                            -AsPlainText `
                            -Force

                        New-ADUser `
                            -Name "$firstName $lastName" `
                            -GivenName $firstName `
                            -Surname $lastName `
                            -SamAccountName $samAccountName `
                            -UserPrincipalName "$samAccountName@AGmicksandmacks.local" `
                            -Path $ouPath `
                            -AccountPassword $password `
                            -Enabled $true

                        Write-Output "User '$samAccountName' created successfully in OU '$OUName'."
                    }
                }
            } `
            -ErrorAction Stop

        Write-ServerLog `
            -ComputerName $ComputerName `
            -Task "Added users from CSV to OU $OUName" `
            -Credential $Credential
    }
    catch {
        Write-Host "Unable to add users from CSV."
        Write-Host $_.Exception.Message
    }
}

# Joins a target computer to the Active Directory domain
function Add-ComputerToDomain {
    param (
        [string]$ComputerName,
        [string]$TargetComputer
    )

    # Prompts the user for administrator credentials
    $credential = Get-Credential

    try {
        Invoke-Command `
            -ComputerName $ComputerName `
            -Credential $credential `
            -ArgumentList $TargetComputer, $credential `
            -ScriptBlock {
                param (
                    $TargetComputer,
                    $Credential
                )

                # Checks that the target computer can be contacted
                $connectionTest = Test-Connection `
                    -ComputerName $TargetComputer `
                    -Count 2 `
                    -Quiet

                if ($connectionTest) {
                    Write-Output "$TargetComputer is contactable."

                    # Checks whether the computer already exists in Active Directory
                    $computerExists = Get-ADComputer `
                        -Identity $TargetComputer `
                        -ErrorAction SilentlyContinue

                    if ($computerExists) {
                        Write-Output "$TargetComputer already exists in Active Directory."
                    }
                    else {
                        Add-Computer `
                            -ComputerName $TargetComputer `
                            -DomainName "AGmicksandmacks.local" `
                            -Credential $Credential `
                            -Restart

                        Write-Output "$TargetComputer has been added to the domain."
                    }
                }
                else {
                    Write-Output "$TargetComputer could not be contacted."
                }
            } `
            -ErrorAction Stop

        Write-ServerLog `
            -ComputerName $ComputerName `
            -Task "Checked or joined computer $TargetComputer to the domain" `
            -Credential $credential
    }
    catch {
        Write-Host "Unable to join $TargetComputer to the domain."
        Write-Host $_.Exception.Message
    }
}

# Configures the DHCP service on the target Windows Server
function Set-DHCPService {
    param (
        [string]$ComputerName,
        [PSCredential]$Credential
    )

    try {
        Invoke-Command `
            -ComputerName $ComputerName `
            -Credential $Credential `
            -ScriptBlock {

                $scopeID = "10.1.1.0"
                $subnetMask = "255.255.255.0"
                $startRange = "10.1.1.150"
                $endRange = "10.1.1.200"
                $domainName = "AGmicksandmacks.local"

                # Checks whether the DHCP role is installed
                $dhcpFeature = Get-WindowsFeature -Name DHCP

                if (!$dhcpFeature.Installed) {
                    Install-WindowsFeature `
                        -Name DHCP `
                        -IncludeManagementTools

                    Write-Output "DHCP role installed successfully."
                }
                else {
                    Write-Output "DHCP role is already installed."
                }

                # Checks whether the DHCP server is authorised in Active Directory
                $serverIP = (
                    Get-NetIPAddress `
                        -AddressFamily IPv4 |
                    Where-Object {
                        $_.InterfaceAlias -notlike "*Loopback*"
                    }
                ).IPAddress

                $authorisedServer = Get-DhcpServerInDC |
                    Where-Object {
                        $_.IPAddress -eq $serverIP
                    }

                if (!$authorisedServer) {
                    Add-DhcpServerInDC `
                        -DnsName "$env:COMPUTERNAME.$domainName" `
                        -IPAddress $serverIP

                    Write-Output "DHCP server authorised in Active Directory."
                }
                else {
                    Write-Output "DHCP server is already authorised."
                }

                # Checks whether the required DHCP scope already exists
                $existingScope = Get-DhcpServerv4Scope `
                    -ScopeId $scopeID `
                    -ErrorAction SilentlyContinue

                if ($existingScope) {
                    Write-Output "DHCP scope $scopeID already exists."
                }
                else {
                    Add-DhcpServerv4Scope `
                        -Name "MickAndMacks" `
                        -StartRange $startRange `
                        -EndRange $endRange `
                        -SubnetMask $subnetMask `
                        -State Active

                    Write-Output "DHCP scope $scopeID created successfully."
                }

                # Configures the DNS and domain options for the scope
                Set-DhcpServerv4OptionValue `
                    -ScopeId $scopeID `
                    -DnsServer $serverIP `
                    -DnsDomain $domainName

                Restart-Service DHCPServer
            } `
            -ErrorAction Stop

        Write-ServerLog `
            -ComputerName $ComputerName `
            -Task "Configured DHCP service for 10.1.1.0/24" `
            -Credential $Credential
    }
    catch {
        Write-Host "Unable to configure the DHCP service."
        Write-Host $_.Exception.Message
    }
}

# Retrieves the top ten System errors from a target computer
function Get-TopSystemErrors {
    param (
        [string]$TargetIPAddress
    )

    # Prompts the user for administrator credentials
    $credential = Get-Credential

    try {
        Invoke-Command `
            -ComputerName $TargetIPAddress `
            -Credential $credential `
            -ScriptBlock {

                $logDirectory = "C:\myLogs"
                $outputFile = "C:\myLogs\toptenerrors.txt"

                # Creates the log directory if it does not already exist
                if (!(Test-Path $logDirectory)) {
                    New-Item `
                        -ItemType Directory `
                        -Path $logDirectory |
                    Out-Null
                }

                # Gets the ten most recent errors from the System event log
                $systemErrors = Get-WinEvent `
                    -FilterHashtable @{
                        LogName = "System"
                        Level = 2
                    } `
                    -MaxEvents 10

                # Displays the errors and saves them to the text file
                $systemErrors |
                    Select-Object `
                        TimeCreated,
                        Id,
                        ProviderName,
                        Message |
                    Format-Table -Wrap |
                    Out-String |
                    Tee-Object -FilePath $outputFile
            } `
            -ErrorAction Stop

        Write-ServerLog `
            -ComputerName $TargetIPAddress `
            -Task "Retrieved top ten System errors" `
            -Credential $credential
    }
    catch {
        Write-Host "Unable to retrieve System errors from $TargetIPAddress."
        Write-Host $_.Exception.Message
    }
}

# Creates a scheduled disk cleanup task on a target computer
function New-DiskCleanupTask {
    param (
        [string]$TargetIPAddress = "localhost"
    )

    # Prompts the user for administrator credentials
    $credential = Get-Credential

    try {
        Invoke-Command `
            -ComputerName $TargetIPAddress `
            -Credential $credential `
            -ScriptBlock {

                # Creates the scheduled task action
                $action = New-ScheduledTaskAction `
                    -Execute "cleanmgr.exe" `
                    -Argument "/verylowdisk"

                # Creates a daily trigger for 6:00 AM
                $trigger = New-ScheduledTaskTrigger `
                    -Daily `
                    -At 6:00AM

                # Runs the task using SYSTEM with administrator privileges
                $principal = New-ScheduledTaskPrincipal `
                    -UserId "SYSTEM" `
                    -RunLevel Highest

                # Combines the task settings
                $task = New-ScheduledTask `
                    -Action $action `
                    -Trigger $trigger `
                    -Principal $principal

                # Registers the scheduled task
                Register-ScheduledTask `
                    -TaskName "DailyDiskCleanup" `
                    -InputObject $task `
                    -Force

                Write-Output "Daily disk cleanup task created successfully."
            } `
            -ErrorAction Stop

        Write-ServerLog `
            -ComputerName $TargetIPAddress `
            -Task "Created daily disk cleanup scheduled task" `
            -Credential $credential
    }
    catch {
        Write-Host "Unable to create the disk cleanup scheduled task."
        Write-Host $_.Exception.Message
    }
}

# Maps the Mick And Macks shared directory as drive S
function Add-MickAndMacksDrive {
    try {
        New-PSDrive `
            -Name "S" `
            -PSProvider FileSystem `
            -Root "\\Server1\mickandmacks_share" `
            -Persist `
            -Scope Global `
            -ErrorAction Stop

        Write-Output "Drive S mapped successfully."
    }
    catch {
        Write-Host "Unable to map drive S."
        Write-Host $_.Exception.Message
    }
}