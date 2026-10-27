# Subst-Manager.ps1 - v2.0
# GUI per la gestione del comando SUBST (dischi virtuali)
# Auto-elevazione admin, log su file, persistenza affidabile
#Requires -Version 7.2

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:workDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$script:logFile = $null

# ============================================
# AUTO-ELEVAZIONE ADMIN
# ============================================
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    [System.Windows.Forms.MessageBox]::Show("Rilancio come Amministratore per gestire i dischi virtuali...", "Privilegi", "OK", "Information")
    $pwshPath = Join-Path $PSHOME "pwsh.exe"
    if (-not (Test-Path $pwshPath)) { $pwshPath = "pwsh.exe" }
    Start-Process $pwshPath -ArgumentList "-NoProfile -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# ============================================
# LOGGING
# ============================================
function Start-Log {
    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    $script:logFile = Join-Path $script:workDir "SubstManager_$ts.log"
    "--- SUBST MANAGER LOG ---" | Set-Content -Path $script:logFile -Encoding UTF8
}

function Write-LogMessage {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "HH:mm:ss"
    $formattedMessage = "[$timestamp] [$Level] $Message"
    
    if ($script:LogListBox) {
        $script:LogListBox.Items.Add($formattedMessage)
        $script:LogListBox.TopIndex = $script:LogListBox.Items.Count - 1
    }
    if ($script:logFile) {
        Add-Content -Path $script:logFile -Value $formattedMessage -Encoding UTF8
    }
}

# ============================================
# FUNZIONI CORE
# ============================================
$PersistenceScriptPath = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup\SubstPersistence.bat"

function Get-SubstMappings {
    $mappings = @()
    try {
        $substOutput = (cmd /c subst)
        if ($substOutput) {
            foreach ($line in $substOutput) {
                # Formato atteso: "S:\: => C:\Percorso" oppure "S: => C:\Percorso"
                if ($line -match "^\s*([A-Z]):\s*(?:\\:)?\s*=>\s*(.*)$") {
                    $drive = $matches[1] + ":"
                    $path = $matches[2].Trim()
                    $mappings += [PSCustomObject]@{Drive = $drive; Path = $path}
                }
            }
        }
    } catch {
        Write-LogMessage "Errore SUBST: $($_.Exception.Message)" "ERROR"
    }
    return $mappings
}

function Get-NetworkDriveMappings {
    $networkDrives = @()
    try {
        $netUseOutput = (cmd /c "net use") | Select-String -Pattern "^\s*\S+\s+(\w:)\s+\\"
        $netUseOutput | ForEach-Object {
            $networkDrives += $_.Matches[0].Groups[1].Value
        }
    } catch {
        Write-LogMessage "Errore NET USE: $($_.Exception.Message)" "ERROR"
    }
    return $networkDrives | Select-Object -Unique
}

function Get-AllUsedDriveLetters {
    $usedLetters = @()
    $usedLetters += (Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Name)
    $usedLetters += (Get-SubstMappings | ForEach-Object { ($_.Drive -replace ":", "") })
    $usedLetters += (Get-NetworkDriveMappings | ForEach-Object { ($_.Replace(":", "")) })
    return ($usedLetters | Select-Object -Unique | Sort-Object)
}

function Get-AvailableDriveLetters {
    $allLetters = [char[]]([char]'A'..[char]'Z') | ForEach-Object { "$_" }
    $usedLetters = Get-AllUsedDriveLetters
    $availableLetters = @()
    foreach ($letter in $allLetters) {
        if (-not ($usedLetters -contains $letter)) {
            $availableLetters += $letter
        }
    }
    return $availableLetters
}

function Refresh-AllLists {
    Refresh-MappingsListBox
    $script:AvailableLettersListBox.Items.Clear()
    $availableLetters = Get-AvailableDriveLetters
    if ($availableLetters.Count -gt 0) {
        $availableLetters | ForEach-Object {
            $script:AvailableLettersListBox.Items.Add($_)
        }
        Write-LogMessage "Lettere disponibili: $($availableLetters.Count)" "INFO"
    } else {
        Write-LogMessage "Nessuna lettera disponibile." "WARNING"
    }
}

function Refresh-MappingsListBox {
    $script:MappingsListBox.Items.Clear()
    $currentMappings = Get-SubstMappings
    if ($currentMappings.Count -gt 0) {
        $currentMappings | ForEach-Object {
            $script:MappingsListBox.Items.Add("$($_.Drive) => $($_.Path)")
        }
        Write-LogMessage "Associazioni SUBST: $($currentMappings.Count)" "INFO"
    } else {
        Write-LogMessage "Nessuna associazione SUBST." "INFO"
    }
    
    $script:NetworkDrivesListBox.Items.Clear()
    $currentNetworkDrives = Get-NetworkDriveMappings
    if ($currentNetworkDrives.Count -gt 0) {
        $currentNetworkDrives | ForEach-Object {
            $script:NetworkDrivesListBox.Items.Add($_)
        }
        Write-LogMessage "Mappature di rete: $($currentNetworkDrives.Count)" "INFO"
    } else {
        Write-LogMessage "Nessuna mappatura di rete." "INFO"
    }
}

function Add-SubstMapping {
    $driveLetter = $script:DriveLetterTextBox.Text.Trim().ToUpper()
    $folderPath = $script:FolderPathTextBox.Text.Trim()
    $makePersistent = $script:PersistenceCheckBox.Checked

    if (-not ($driveLetter -match "^[A-Z]$")) {
        [System.Windows.Forms.MessageBox]::Show("Inserisci una lettera valida (A-Z).", "Errore", "OK", "Warning")
        return
    }
    if ([string]::IsNullOrWhiteSpace($folderPath) -or -not (Test-Path $folderPath -PathType Container)) {
        [System.Windows.Forms.MessageBox]::Show("Seleziona una cartella valida.", "Errore", "OK", "Warning")
        return
    }

    $allUsedDrives = Get-AllUsedDriveLetters
    if ($allUsedDrives -contains $driveLetter) {
        [System.Windows.Forms.MessageBox]::Show("La lettera '$driveLetter' e gia in uso.", "Errore", "OK", "Error")
        return
    }

    try {
        Write-LogMessage "Aggiunta: $driveLetter => $folderPath" "INFO"
        $commandResult = (cmd /c subst "$driveLetter`:" "`"$folderPath`"")
        if ($LASTEXITCODE -eq 0) {
            Write-LogMessage "OK: $driveLetter => $folderPath" "SUCCESS"
            Refresh-AllLists
            $script:DriveLetterTextBox.Clear()
            $script:FolderPathTextBox.Clear()
            if ($makePersistent) {
                Set-SubstPersistence -DriveLetter ($driveLetter + ":") -Path $folderPath -Action "Add"
            }
        } else {
            Write-LogMessage "Errore SUBST: $commandResult" "ERROR"
        }
    } catch {
        Write-LogMessage "Eccezione: $($_.Exception.Message)" "ERROR"
    }
}

function Remove-SubstMapping {
    if ($script:MappingsListBox.SelectedItem -eq $null) {
        [System.Windows.Forms.MessageBox]::Show("Seleziona un'associazione.", "Nessuna selezione", "OK", "Warning")
        return
    }

    $selectedItem = $script:MappingsListBox.SelectedItem
    $driveToDelete = ($selectedItem.Split("=>")[0]).Trim()

    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Eliminare: `n`n$selectedItem ?",
        "Conferma",
        "YesNo", "Question"
    )

    if ($confirm -eq "Yes") {
        try {
            Write-LogMessage "Rimozione: $driveToDelete" "INFO"
            $commandResult = (cmd /c subst "$driveToDelete" /d)
            if ($LASTEXITCODE -eq 0) {
                Write-LogMessage "Rimosso: $driveToDelete" "SUCCESS"
                Refresh-AllLists
                Set-SubstPersistence -DriveLetter $driveToDelete -Action "Remove"
            } else {
                Write-LogMessage "Errore rimozione: $commandResult" "ERROR"
            }
        } catch {
            Write-LogMessage "Eccezione: $($_.Exception.Message)" "ERROR"
        }
    }
}

function Open-SubstFolder {
    if ($script:MappingsListBox.SelectedItem -eq $null) { return }
    $selectedItem = $script:MappingsListBox.SelectedItem
    $path = ($selectedItem.Split("=>")[1]).Trim()
    if (Test-Path $path) {
        Invoke-Item $path
    }
}

function Set-SubstPersistence {
    param (
        [string]$DriveLetter,
        [string]$Path = "",
        [string]$Action
    )

    $startupFolder = Split-Path $PersistenceScriptPath -Parent
    if (-not (Test-Path $startupFolder)) {
        New-Item -Path $startupFolder -ItemType Directory -Force | Out-Null
    }

    $existingLines = @()
    if (Test-Path $PersistenceScriptPath) {
        $existingLines = Get-Content -Path $PersistenceScriptPath -ErrorAction SilentlyContinue
    } else {
        @(
            "@echo off",
            "REM Persistenza SUBST - Generato da Fabry Toolbox",
            "REM Non modificare manualmente"
        ) | Set-Content -Path $PersistenceScriptPath -Force
    }

    $newLines = @()
    $lineToAdd = "subst $DriveLetter `"$Path`""

    foreach ($line in $existingLines) {
        if (-not ($line.TrimStart().StartsWith("REM")) -and -not ($line -like "*subst $DriveLetter*")) {
            $newLines += $line
        }
    }

    if ($Action -eq "Add") {
        $newLines += $lineToAdd
        Write-LogMessage "Persistenza: $lineToAdd" "INFO"
    } elseif ($Action -eq "Remove") {
        Write-LogMessage "Persistenza rimossa: $DriveLetter" "INFO"
    }

    try {
        $newLines | Set-Content -Path $PersistenceScriptPath -Force
    } catch {
        Write-LogMessage "Errore persistenza: $($_.Exception.Message)" "ERROR"
    }
}

# ============================================
# GUI
# ============================================
$form = New-Object System.Windows.Forms.Form
$form.Text = "Gestione SUBST - Disco Virtuale"
$form.Size = New-Object System.Drawing.Size(650, 750)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 245)

# --- Associazioni esistenti ---
$LabelExisting = New-Object System.Windows.Forms.Label
$LabelExisting.Text = "Associazioni SUBST esistenti:"
$LabelExisting.Location = New-Object System.Drawing.Point(20, 20)
$LabelExisting.AutoSize = $true
$form.Controls.Add($LabelExisting)

$script:MappingsListBox = New-Object System.Windows.Forms.ListBox
$script:MappingsListBox.Location = New-Object System.Drawing.Point(20, 45)
$script:MappingsListBox.Size = New-Object System.Drawing.Size(580, 80)
$script:MappingsListBox.Add_DoubleClick({ Open-SubstFolder })
$form.Controls.Add($script:MappingsListBox)

# --- Mappature di rete ---
$LabelNetworkDrives = New-Object System.Windows.Forms.Label
$LabelNetworkDrives.Text = "Lettere unita mappate a rete:"
$LabelNetworkDrives.Location = New-Object System.Drawing.Point(20, 140)
$LabelNetworkDrives.AutoSize = $true
$form.Controls.Add($LabelNetworkDrives)

$script:NetworkDrivesListBox = New-Object System.Windows.Forms.ListBox
$script:NetworkDrivesListBox.Location = New-Object System.Drawing.Point(20, 165)
$script:NetworkDrivesListBox.Size = New-Object System.Drawing.Size(580, 80)
$form.Controls.Add($script:NetworkDrivesListBox)

# --- Lettere disponibili ---
$LabelAvailableLetters = New-Object System.Windows.Forms.Label
$LabelAvailableLetters.Text = "Lettere di unita disponibili:"
$LabelAvailableLetters.Location = New-Object System.Drawing.Point(20, 260)
$LabelAvailableLetters.AutoSize = $true
$form.Controls.Add($LabelAvailableLetters)

$script:AvailableLettersListBox = New-Object System.Windows.Forms.ListBox
$script:AvailableLettersListBox.Location = New-Object System.Drawing.Point(20, 285)
$script:AvailableLettersListBox.Size = New-Object System.Drawing.Size(580, 80)
$form.Controls.Add($script:AvailableLettersListBox)

# --- Pulsanti ---
$RefreshButton = New-Object System.Windows.Forms.Button
$RefreshButton.Text = "Aggiorna Tutte le Liste"
$RefreshButton.Location = New-Object System.Drawing.Point(20, 380)
$RefreshButton.Size = New-Object System.Drawing.Size(160, 30)
$RefreshButton.FlatStyle = "Flat"
$RefreshButton.Add_Click({ Refresh-AllLists })
$form.Controls.Add($RefreshButton)

$DeleteButton = New-Object System.Windows.Forms.Button
$DeleteButton.Text = "Elimina Associazione"
$DeleteButton.Location = New-Object System.Drawing.Point(190, 380)
$DeleteButton.Size = New-Object System.Drawing.Size(160, 30)
$DeleteButton.FlatStyle = "Flat"
$DeleteButton.Add_Click({ Remove-SubstMapping })
$form.Controls.Add($DeleteButton)

$OpenButton = New-Object System.Windows.Forms.Button
$OpenButton.Text = "Apri Cartella"
$OpenButton.Location = New-Object System.Drawing.Point(360, 380)
$OpenButton.Size = New-Object System.Drawing.Size(120, 30)
$OpenButton.FlatStyle = "Flat"
$OpenButton.Add_Click({ Open-SubstFolder })
$form.Controls.Add($OpenButton)

# --- Nuova associazione ---
$GroupBoxAdd = New-Object System.Windows.Forms.GroupBox
$GroupBoxAdd.Text = "Aggiungi Nuova Associazione"
$GroupBoxAdd.Location = New-Object System.Drawing.Point(20, 430)
$GroupBoxAdd.Size = New-Object System.Drawing.Size(580, 190)
$form.Controls.Add($GroupBoxAdd)

$LabelDrive = New-Object System.Windows.Forms.Label
$LabelDrive.Text = "Lettera (es. S):"
$LabelDrive.Location = New-Object System.Drawing.Point(10, 30)
$LabelDrive.AutoSize = $true
$GroupBoxAdd.Controls.Add($LabelDrive)

$script:DriveLetterTextBox = New-Object System.Windows.Forms.TextBox
$script:DriveLetterTextBox.Location = New-Object System.Drawing.Point(130, 27)
$script:DriveLetterTextBox.Size = New-Object System.Drawing.Size(50, 20)
$script:DriveLetterTextBox.MaxLength = 1
$GroupBoxAdd.Controls.Add($script:DriveLetterTextBox)

$LabelConvention = New-Object System.Windows.Forms.Label
$LabelConvention.Text = "Suggerimento: O-S per SUBST, T-Z per rete"
$LabelConvention.Location = New-Object System.Drawing.Point(210, 30)
$LabelConvention.AutoSize = $true
$LabelConvention.ForeColor = [System.Drawing.Color]::Blue
$GroupBoxAdd.Controls.Add($LabelConvention)

$LabelFolder = New-Object System.Windows.Forms.Label
$LabelFolder.Text = "Cartella:"
$LabelFolder.Location = New-Object System.Drawing.Point(10, 60)
$LabelFolder.AutoSize = $true
$GroupBoxAdd.Controls.Add($LabelFolder)

$script:FolderPathTextBox = New-Object System.Windows.Forms.TextBox
$script:FolderPathTextBox.Location = New-Object System.Drawing.Point(130, 57)
$script:FolderPathTextBox.Size = New-Object System.Drawing.Size(330, 20)
$script:FolderPathTextBox.ReadOnly = $true
$GroupBoxAdd.Controls.Add($script:FolderPathTextBox)

$BrowseButton = New-Object System.Windows.Forms.Button
$BrowseButton.Text = "Sfoglia..."
$BrowseButton.Location = New-Object System.Drawing.Point(470, 55)
$BrowseButton.Size = New-Object System.Drawing.Size(80, 25)
$BrowseButton.FlatStyle = "Flat"
$BrowseButton.Add_Click({
    $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($folderBrowser.ShowDialog() -eq "OK") {
        $script:FolderPathTextBox.Text = $folderBrowser.SelectedPath
    }
})
$GroupBoxAdd.Controls.Add($BrowseButton)

$script:PersistenceCheckBox = New-Object System.Windows.Forms.CheckBox
$script:PersistenceCheckBox.Text = "Rendi persistente all'avvio"
$script:PersistenceCheckBox.Location = New-Object System.Drawing.Point(10, 95)
$script:PersistenceCheckBox.AutoSize = $true
$script:PersistenceCheckBox.Checked = $true
$GroupBoxAdd.Controls.Add($script:PersistenceCheckBox)

$AddButton = New-Object System.Windows.Forms.Button
$AddButton.Text = "Aggiungi Associazione"
$AddButton.Location = New-Object System.Drawing.Point(10, 125)
$AddButton.Size = New-Object System.Drawing.Size(160, 30)
$AddButton.FlatStyle = "Flat"
$AddButton.BackColor = [System.Drawing.Color]::LightGreen
$AddButton.Add_Click({ Add-SubstMapping })
$GroupBoxAdd.Controls.Add($AddButton)

# --- Log ---
$LabelLog = New-Object System.Windows.Forms.Label
$LabelLog.Text = "Log operazioni:"
$LabelLog.Location = New-Object System.Drawing.Point(20, 640)
$LabelLog.AutoSize = $true
$form.Controls.Add($LabelLog)

$script:LogListBox = New-Object System.Windows.Forms.ListBox
$script:LogListBox.Location = New-Object System.Drawing.Point(20, 665)
$script:LogListBox.Size = New-Object System.Drawing.Size(580, 60)
$script:LogListBox.Font = New-Object System.Drawing.Font("Consolas", 8)
$form.Controls.Add($script:LogListBox)

# --- Avvio ---
$form.Add_Shown({ Refresh-AllLists })
$form.Add_FormClosed({ $form.Dispose() })

Start-Log
Write-LogMessage "Subst Manager avviato" "INFO"
Write-LogMessage "Log: $script:logFile" "INFO"

[void]$form.ShowDialog()