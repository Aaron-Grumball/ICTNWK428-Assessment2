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