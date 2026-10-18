# PiracyBlocker - blocks unwanted sites using the Windows hosts file.
#
# Every file named blocklist*.txt in this folder is used (piracy sites, propaganda sites, ...),
# plus the online lists in sources.txt once they have been downloaded with -Action Update.
# Sites in allowlist.txt are never blocked, even if they appear in a block list.
#
# Usage (from an administrator PowerShell, or just use the .bat files):
#   .\PiracyBlocker.ps1 -Action Install    # copy to Program Files + update automatically at startup and daily
#   .\PiracyBlocker.ps1 -Action Uninstall  # remove the automatic update and unblock everything
#   .\PiracyBlocker.ps1 -Action Update     # download the online lists, then block
#   .\PiracyBlocker.ps1 -Action Block      # block using the lists already on this PC
#   .\PiracyBlocker.ps1 -Action Unblock    # remove everything this tool added
#   .\PiracyBlocker.ps1 -Action Status     # show how many sites are blocked

param(
    [ValidateSet('Block', 'Unblock', 'Status', 'Update', 'Install', 'Uninstall')]
    [string]$Action = 'Block',

    # Only change this for testing; the real hosts file is the default.
    [string]$HostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
)

$ErrorActionPreference = 'Stop'

$StartMarker = '# >>> PiracyBlocker START (managed automatically, do not edit by hand)'
$EndMarker   = '# <<< PiracyBlocker END'
$AllowPath   = Join-Path $PSScriptRoot 'allowlist.txt'
$SourcesPath = Join-Path $PSScriptRoot 'sources.txt'
$CacheDir    = Join-Path $PSScriptRoot 'downloaded'
$LogPath     = Join-Path $PSScriptRoot 'update.log'
$InstallDir  = Join-Path $env:ProgramFiles 'PiracyBlocker'
$TaskName    = 'PiracyBlocker Auto-Update'

function Write-Log([string]$message) {
    Write-Host $message
    try {
        $old = @()
        if (Test-Path -LiteralPath $LogPath) { $old = @(Get-Content -LiteralPath $LogPath -Tail 300) }
        Set-Content -LiteralPath $LogPath -Value ($old + "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $message") -Encoding UTF8
    } catch { }
}

function Assert-Admin {
    $id = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $id.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Please run this as Administrator (use the .bat files, or right-click > Run as administrator).'
    }
}

# Returns the hosts file lines with any previous PiracyBlocker section removed.
function Get-HostsWithoutOurSection {
    $result = New-Object System.Collections.Generic.List[string]
    if (Test-Path -LiteralPath $HostsPath) {
        $inside = $false
        foreach ($line in Get-Content -LiteralPath $HostsPath) {
            if ($line -eq $StartMarker) { $inside = $true;  continue }
            if ($line -eq $EndMarker)   { $inside = $false; continue }
            if (-not $inside) { $result.Add($line) }
        }
    }
    while ($result.Count -gt 0 -and $result[$result.Count - 1].Trim() -eq '') {
        $result.RemoveAt($result.Count - 1)
    }
    return $result.ToArray()
}

# Reads a list file and returns the clean domain names in it. Understands plain domains,
# hosts-file lines ("0.0.0.0 example.com") and adblock lines ("||example.com^").
function Read-DomainList([string]$path, [switch]$Quiet) {
    foreach ($raw in Get-Content -LiteralPath $path) {
        $d = ($raw -replace '#.*$', '').Trim().ToLower()
        if ($d -eq '' -or $d.StartsWith('!')) { continue }
        $d = $d -replace '^(0\.0\.0\.0|127\.0\.0\.1|::1?)\s+', ''
        $d = $d -replace '^\|\|', '' -replace '\^.*$', ''
        $d = $d -replace '^[a-z]+://', ''   # strip http:// or https://
        $d = $d -replace '[/:\s].*$', ''    # strip paths, ports and anything after a space
        $d = $d -replace '^www\.', ''
        # Must look like a domain whose last part contains a letter (skips IPs and "localhost").
        if ($d -notmatch '^[a-z0-9.-]+\.[a-z0-9-]*[a-z][a-z0-9-]*$') {
            if (-not $Quiet) { Write-Warning "Skipping invalid entry in $(Split-Path $path -Leaf): $raw" }
            continue
        }
        $d
    }
}

# Returns the allowlist entry covering $domain (itself or a parent domain), or $null.
function Find-Allowed([string]$domain, $allowed) {
    $parts = $domain.Split('.')
    for ($i = 0; $i -lt $parts.Count - 1; $i++) {
        $candidate = $parts[$i..($parts.Count - 1)] -join '.'
        if ($allowed.Contains($candidate)) { return $candidate }
    }
    return $null
}

# Reads every local blocklist*.txt and downloaded list and returns the domains to block
# (plus www. variants), leaving out anything covered by allowlist.txt.
function Get-BlockedDomains {
    $lists = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter 'blocklist*.txt')
    if (Test-Path -LiteralPath $CacheDir) { $lists += @(Get-ChildItem -LiteralPath $CacheDir -Filter '*.txt') }
    if ($lists.Count -eq 0) {
        throw "Cannot find any blocklist*.txt files in $PSScriptRoot"
    }
    $allowed = New-Object System.Collections.Generic.HashSet[string]
    if (Test-Path -LiteralPath $AllowPath) {
        foreach ($a in Read-DomainList $AllowPath) { [void]$allowed.Add($a) }
    }

    $domains = New-Object System.Collections.Generic.SortedSet[string]
    foreach ($list in $lists) {
        $downloaded = $list.DirectoryName -eq $CacheDir
        Write-Host "Reading $($list.Name)"
        foreach ($d in Read-DomainList $list.FullName -Quiet:$downloaded) {
            # Never block an allowed site or any of its subdomains (e.g. news.mail.ru).
            $hit = Find-Allowed $d $allowed
            if ($hit) {
                Write-Log "Not blocking $d because $hit is in allowlist.txt"
                continue
            }
            [void]$domains.Add($d)
            [void]$domains.Add("www.$d")
        }
    }
    return @($domains)
}

# Downloads every URL in sources.txt into the downloaded folder. If a download fails,
# the copy from the last successful update is kept so nothing gets unblocked.
function Update-Lists {
    if (-not (Test-Path -LiteralPath $SourcesPath)) { return }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null

    $urls = @(Get-Content -LiteralPath $SourcesPath | ForEach-Object { ($_ -replace '#.*$', '').Trim() } |
              Where-Object { $_ -match '^https://' })
    $keep = @()
    foreach ($url in $urls) {
        $sha  = [Security.Cryptography.SHA1]::Create()
        $hash = -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($url))[0..3] | ForEach-Object { $_.ToString('x2') })
        $file = Join-Path $CacheDir "list-$hash.txt"
        $keep += $file
        $temp = "$file.tmp"

        # At startup the internet connection may not be ready yet, so retry for a few minutes.
        $ok = $false
        for ($try = 1; $try -le 10 -and -not $ok; $try++) {
            try {
                Invoke-WebRequest -Uri $url -OutFile $temp -UseBasicParsing -TimeoutSec 60
                $count = @(Read-DomainList $temp -Quiet).Count
                if ($count -lt 10) { throw "only $count domains found, ignoring this download" }
                Move-Item -LiteralPath $temp -Destination $file -Force
                Write-Log "Downloaded $count domains from $url"
                $ok = $true
            } catch {
                Write-Log "Download attempt $try failed for ${url}: $($_.Exception.Message)"
                if ($try -lt 10) { Start-Sleep -Seconds 30 }
            }
        }
        Remove-Item -LiteralPath $temp -ErrorAction SilentlyContinue
        if (-not $ok -and (Test-Path -LiteralPath $file)) { Write-Log "Keeping the previous copy of $url" }
    }
    # Forget lists whose URL was removed from sources.txt.
    Get-ChildItem -LiteralPath $CacheDir -Filter '*.txt' | Where-Object { $keep -notcontains $_.FullName } |
        Remove-Item -Force
}

function Save-Hosts([string[]]$lines) {
    if (Test-Path -LiteralPath $HostsPath) {
        $backup = "$HostsPath.piracyblocker.bak"
        if (-not (Test-Path -LiteralPath $backup)) {
            Copy-Item -LiteralPath $HostsPath -Destination $backup
            Write-Host "Backup of the original hosts file saved to: $backup"
        }
        # The hosts file is sometimes marked read-only.
        $file = Get-Item -LiteralPath $HostsPath
        if ($file.IsReadOnly) { $file.IsReadOnly = $false }
    }
    try {
        Set-Content -LiteralPath $HostsPath -Value $lines -Encoding ASCII
    } catch [System.UnauthorizedAccessException] {
        throw 'Access denied. Please run this as Administrator (right-click > Run as administrator, or use Block.bat).'
    }
    ipconfig /flushdns | Out-Null
}

function Invoke-Block {
    $domains = Get-BlockedDomains
    $section = New-Object System.Collections.Generic.List[string]
    $section.Add('')
    $section.Add($StartMarker)
    foreach ($d in $domains) {
        $section.Add("0.0.0.0 $d")
        $section.Add(":: $d")
    }
    $section.Add($EndMarker)
    Save-Hosts (@(Get-HostsWithoutOurSection) + $section.ToArray())
    Write-Log "Done. $($domains.Count) site addresses are now blocked."
}

switch ($Action) {
    'Block' {
        Invoke-Block
        Write-Host 'Close and reopen the web browser for the change to take effect.'
    }
    'Update' {
        Update-Lists
        Invoke-Block
    }
    'Unblock' {
        Save-Hosts @(Get-HostsWithoutOurSection)
        Write-Host ''
        Write-Host 'Done. All sites added by PiracyBlocker have been unblocked.' -ForegroundColor Green
    }
    'Install' {
        Assert-Admin
        # Install into Program Files: only administrators can change files there, which matters
        # because the scheduled task runs this script with full system rights.
        New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
        if ($PSScriptRoot -ne $InstallDir) {
            Get-ChildItem -LiteralPath $PSScriptRoot -File |
                Where-Object { $_.Extension -in '.ps1', '.txt', '.bat' } |
                Copy-Item -Destination $InstallDir -Force
        }
        $script = Join-Path $InstallDir 'PiracyBlocker.ps1'
        $taskAction = New-ScheduledTaskAction -Execute 'powershell.exe' `
            -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`" -Action Update"
        $atStartup = New-ScheduledTaskTrigger -AtStartup
        $atStartup.Delay = 'PT1M'
        $daily = New-ScheduledTaskTrigger -Daily -At '12:00'
        $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
        Register-ScheduledTask -TaskName $TaskName -Action $taskAction -Trigger @($atStartup, $daily) `
            -Principal $principal -Settings $settings -Force | Out-Null

        Write-Host "Installed to $InstallDir"
        Write-Host 'The block lists will now update automatically at every startup and every day at 12:00.'
        Write-Host 'Running the first update now...'
        Write-Host ''
        & $script -Action Update
        Write-Host ''
        Write-Host 'Close and reopen the web browser for the change to take effect.' -ForegroundColor Green
    }
    'Uninstall' {
        Assert-Admin
        if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        }
        Save-Hosts @(Get-HostsWithoutOurSection)
        if ($PSScriptRoot -ne $InstallDir -and (Test-Path -LiteralPath $InstallDir)) {
            Remove-Item -LiteralPath $InstallDir -Recurse -Force
        }
        Write-Host ''
        Write-Host 'Done. Automatic updates are removed and all sites are unblocked.' -ForegroundColor Green
        if ($PSScriptRoot -eq $InstallDir) { Write-Host "You can now delete the folder $InstallDir" }
    }
    'Status' {
        $count = 0
        $inside = $false
        if (Test-Path -LiteralPath $HostsPath) {
            foreach ($line in Get-Content -LiteralPath $HostsPath) {
                if ($line -eq $StartMarker) { $inside = $true; continue }
                if ($line -eq $EndMarker)   { $inside = $false; continue }
                if ($inside -and $line -like '0.0.0.0 *') { $count++ }
            }
        }
        if ($count -gt 0) {
            Write-Host "PiracyBlocker is ON: $count site addresses blocked." -ForegroundColor Green
        } else {
            Write-Host 'PiracyBlocker is OFF: no sites blocked.' -ForegroundColor Yellow
        }
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($task) {
            $info = $task | Get-ScheduledTaskInfo
            Write-Host "Automatic updates are ON. Last update: $($info.LastRunTime)"
        } else {
            Write-Host 'Automatic updates are OFF (run Install.bat to turn them on).'
        }
    }
}
