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