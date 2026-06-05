#Requires -Version 5.1
<#
.SYNOPSIS
    Deploy VMware Tools su macchine Windows silenziosamente, senza riavvio.

.DESCRIPTION
    Scarica l'ultima versione di VMware Tools (o usa un installer locale),
    lo distribuisce sui target tramite PSSession e lo installa silenziosamente
    senza riavviare la macchina.

    Prerequisiti sui target:
      - WinRM abilitato (winrm quickconfig)
      - Utente con diritti di amministratore locale

.PARAMETER Targets
    Uno o piu' hostname o indirizzi IP su cui installare.

.PARAMETER Username
    Username per la connessione remota (es. "Administrator", "DOMAIN\user").

.PARAMETER Password
    Password come SecureString. Se omessa viene chiesta interattivamente.

.PARAMETER InstallerPath
    Percorso locale a un installer VMware Tools .exe. Se omesso, viene
    scaricata automaticamente l'ultima versione da packages.vmware.com.

.PARAMETER MaxParallel
    Numero massimo di installazioni parallele (default: 5).

.EXAMPLE
    .\deploy-vmtools-windows.ps1 -Targets "192.168.1.10","192.168.1.11" -Username "Administrator"

.EXAMPLE
    .\deploy-vmtools-windows.ps1 -Targets "srv01","srv02" -Username "DOMAIN\admin" -InstallerPath "C:\tools\VMware-tools.exe" -MaxParallel 10
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory, HelpMessage = "Hostname o IP dei target")]
    [string[]] $Targets,

    [Parameter(Mandatory, HelpMessage = "Username per la connessione remota")]
    [string] $Username,

    [Parameter(HelpMessage = "Password (richiesta interattivamente se omessa)")]
    [SecureString] $Password,

    [Parameter(HelpMessage = "Percorso installer locale; se omesso scarica l'ultima versione")]
    [string] $InstallerPath = "",

    [Parameter(HelpMessage = "Max installazioni parallele (1-20)")]
    [ValidateRange(1, 20)]
    [int] $MaxParallel = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ------------------------------------------------------------------------------
# Output helpers
# ------------------------------------------------------------------------------
function Write-Step { param($msg) Write-Host "[....] $msg" -ForegroundColor Cyan }
function Write-Ok   { param($msg) Write-Host "[ OK ] $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Fail { param($msg) Write-Host "[FAIL] $msg" -ForegroundColor Red }

# ------------------------------------------------------------------------------
# Credential
# ------------------------------------------------------------------------------
if (-not $PSBoundParameters.ContainsKey('Password')) {
    $Password = Read-Host "Password per $Username" -AsSecureString
}
$Credential = New-Object System.Management.Automation.PSCredential($Username, $Password)

# ------------------------------------------------------------------------------
# Download installer se non fornito
# ------------------------------------------------------------------------------
function Get-LatestInstaller {
    Write-Step "Ricerca ultima versione VMware Tools su packages.vmware.com..."
    $indexUrl = "https://packages.vmware.com/tools/releases/latest/windows/"
    try {
        $response = Invoke-WebRequest -Uri $indexUrl -UseBasicParsing -TimeoutSec 30
        $exeHref  = ($response.Links |
                     Where-Object { $_.href -match '\.exe$' } |
                     Select-Object -First 1).href

        if (-not $exeHref) { throw "Nessun file .exe trovato nella pagina index." }

        $downloadUrl = if ($exeHref -match '^https?://') {
            $exeHref
        } else {
            $indexUrl.TrimEnd('/') + '/' + $exeHref.TrimStart('/')
        }

        $fileName  = $exeHref -replace '.*/', ''
        $localPath = Join-Path $env:TEMP $fileName

        Write-Step "Download: $downloadUrl"
        Invoke-WebRequest -Uri $downloadUrl -OutFile $localPath -UseBasicParsing -TimeoutSec 600
        Write-Ok "Installer scaricato: $localPath"
        return $localPath

    } catch {
        throw "Download automatico fallito: $_`nSpecifica -InstallerPath per usare un installer locale."
    }
}

$localInstaller = if ($InstallerPath -and (Test-Path $InstallerPath)) {
    Write-Ok "Uso installer locale: $InstallerPath"
    $InstallerPath
} else {
    if ($InstallerPath) { Write-Warn "InstallerPath '$InstallerPath' non trovato, scarico dal web." }
    Get-LatestInstaller
}

$installerName = Split-Path $localInstaller -Leaf
$installerSize = [Math]::Round((Get-Item $localInstaller).Length / 1MB, 1)
Write-Ok "Installer: $installerName ($installerSize MB)"

# ------------------------------------------------------------------------------
# Funzione di deploy su singolo host
# ------------------------------------------------------------------------------
function Install-OnHost {
    param(
        [string] $Target,
        [System.Management.Automation.PSCredential] $Cred,
        [string] $LocalFile,
        [string] $FileName
    )

    $result = [PSCustomObject]@{
        Host    = $Target
        Status  = "PENDING"
        Before  = ""
        After   = ""
        Message = ""
    }

    try {
        $sessionOpts = New-PSSessionOption `
            -SkipCACheck `
            -SkipCNCheck `
            -SkipRevocationCheck `
            -OperationTimeout 300000 `
            -OpenTimeout 30000

        $session = New-PSSession `
            -ComputerName $Target `
            -Credential $Cred `
            -SessionOption $sessionOpts `
            -ErrorAction Stop

        # Versione installata prima
        $result.Before = Invoke-Command -Session $session -ScriptBlock {
            $k = Get-ItemProperty "HKLM:\SOFTWARE\VMware, Inc.\VMware Tools" -ErrorAction SilentlyContinue
            if ($k) { $k.CurrentVersion } else { "non installato" }
        }

        # Copia installer sul target
        $remotePath = "C:\Windows\Temp\$FileName"
        Copy-Item -Path $LocalFile -Destination $remotePath -ToSession $session -Force

        # Installazione silenziosa senza riavvio
        $exitCode = Invoke-Command -Session $session -ScriptBlock {
            param($path)
            $proc = Start-Process -FilePath $path `
                                  -ArgumentList '/S /v"/qn REBOOT=ReallySuppress"' `
                                  -Wait -PassThru
            Remove-Item $path -Force -ErrorAction SilentlyContinue
            return $proc.ExitCode
        } -ArgumentList $remotePath

        # 0 = OK, 3010 = OK ma riavvio suggerito (soppresso)
        if ($exitCode -in 0, 3010) {
            $result.After = Invoke-Command -Session $session -ScriptBlock {
                $k = Get-ItemProperty "HKLM:\SOFTWARE\VMware, Inc.\VMware Tools" -ErrorAction SilentlyContinue
                if ($k) { $k.CurrentVersion } else { "N/A" }
            }
            $result.Status  = "OK"
            $result.Message = if ($exitCode -eq 3010) { "Installato (riavvio suggerito ma soppresso)" } else { "Installato" }
        } else {
            $result.Status  = "WARN"
            $result.Message = "Exit code inatteso: $exitCode"
        }

        Remove-PSSession $session -ErrorAction SilentlyContinue

    } catch {
        $result.Status  = "FAIL"
        $result.Message = $_.Exception.Message
    }

    return $result
}

# ------------------------------------------------------------------------------
# Esecuzione parallela
# ------------------------------------------------------------------------------
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  VMware Tools Deploy — Windows"              -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "Target     : $($Targets.Count) host"
Write-Host "Installer  : $installerName"
Write-Host "Parallelo  : $MaxParallel"
Write-Host ""

$jobs    = [System.Collections.Generic.List[hashtable]]::new()
$results = [System.Collections.Generic.List[object]]::new()
$queue   = [System.Collections.Generic.Queue[string]]::new($Targets)

while ($queue.Count -gt 0 -or $jobs.Count -gt 0) {

    # Riempi slot disponibili
    while ($queue.Count -gt 0 -and $jobs.Count -lt $MaxParallel) {
        $target = $queue.Dequeue()
        Write-Step "Avvio su $target..."
        $job = Start-Job -ScriptBlock ${function:Install-OnHost} `
                         -ArgumentList $target, $Credential, $localInstaller, $installerName
        $jobs.Add(@{ Target = $target; Job = $job })
    }

    # Raccolta job completati
    $completed = @($jobs | Where-Object { $_.Job.State -in 'Completed', 'Failed' })
    foreach ($item in $completed) {
        $r = Receive-Job -Job $item.Job
        Remove-Job -Job $item.Job -Force
        [void]$jobs.Remove($item)
        [void]$results.Add($r)

        switch ($r.Status) {
            "OK"   { Write-Ok   "$($r.Host) — $($r.Before) → $($r.After)" }
            "WARN" { Write-Warn "$($r.Host) — $($r.Message)" }
            "FAIL" { Write-Fail "$($r.Host) — $($r.Message)" }
        }
    }

    if ($jobs.Count -gt 0) { Start-Sleep -Milliseconds 500 }
}

# ------------------------------------------------------------------------------
# Riepilogo finale
# ------------------------------------------------------------------------------
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  RIEPILOGO"                                  -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

$nOk   = ($results | Where-Object Status -eq "OK").Count
$nWarn = ($results | Where-Object Status -eq "WARN").Count
$nFail = ($results | Where-Object Status -eq "FAIL").Count

Write-Host "OK  : $nOk"   -ForegroundColor Green
Write-Host "WARN: $nWarn" -ForegroundColor Yellow
Write-Host "FAIL: $nFail" -ForegroundColor Red
Write-Host ""

$results | Format-Table Host, Status, Before, After, Message -AutoSize

if ($nFail -gt 0) { exit 1 }
