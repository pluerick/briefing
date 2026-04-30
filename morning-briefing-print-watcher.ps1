<#
.SYNOPSIS
    Watches for morning-briefing.pdf across all Claude sessions and prints it.
    Event-driven (FileSystemWatcher) — zero polling, zero spooler hammering.

.USAGE
    Register in Task Scheduler to run at logon:
      Program : pwsh.exe
      Args    : -WindowStyle Hidden -NonInteractive -File "C:\...\morning-briefing-print-watcher.ps1"
      Settings: "Run whether user is logged on or not" = NO (needs desktop session for printing)
               "Run only when user is logged on" = YES
#>

param(
    [string]$PrinterName     = "Brother HL-L2300D series (Copy 1)",
    [string]$WatchRoot       = "$env:APPDATA\Claude\local-agent-mode-sessions",
    [string]$LogFile         = "$env:APPDATA\Claude\Logs\morning-print.log",
    [int]   $DebounceSeconds = 60,
    [int]   $WriteWaitSecs   = 5
)

# ── Logging setup ──────────────────────────────────────────────────────────────
$null = New-Item -ItemType Directory -Force -Path (Split-Path $LogFile)
function Log($m) { Add-Content $LogFile "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $m" }

Log "=== Morning Briefing Print Watcher starting"
Log "    Printer : $PrinterName"
Log "    Watching: $WatchRoot (recursive, filter: morning-briefing.pdf)"

if (-not (Test-Path $WatchRoot)) {
    Log "ERROR: Watch root not found — $WatchRoot"; exit 1
}

# ── Shared state (synchronized hashtable so event thread can read/write it) ───
$state = [hashtable]::Synchronized(@{
    LastPath        = ""
    LastTime        = [DateTime]::MinValue
    DebounceSeconds = $DebounceSeconds
    WriteWaitSecs   = $WriteWaitSecs
    PrinterName     = $PrinterName
    LogFile         = $LogFile
})

# ── Action block — runs in the event thread ────────────────────────────────────
$printAction = {
    $s       = $Event.MessageData
    $pdfPath = $Event.SourceEventArgs.FullPath
    $now     = [DateTime]::Now

    function ELog($m) { Add-Content $s.LogFile "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $m" }

    # Debounce: FileSystemWatcher often fires Changed twice for one write
    if ($pdfPath -eq $s.LastPath -and
        ($now - $s.LastTime).TotalSeconds -lt $s.DebounceSeconds) {
        ELog "Debounced duplicate event: $pdfPath"
        return
    }
    $s.LastPath = $pdfPath
    $s.LastTime = $now

    ELog "Detected: $pdfPath — waiting $($s.WriteWaitSecs)s for write to finish..."
    Start-Sleep $s.WriteWaitSecs

    # Verify the file is real and complete
    if (-not (Test-Path $pdfPath)) { ELog "File gone after wait, skipping."; return }
    $size = (Get-Item $pdfPath).Length
    if ($size -lt 1024) { ELog "File too small ($size bytes), skipping."; return }

    $printer = $s.PrinterName
    ELog "Sending to printer: $printer"

    # Method 1: SumatraPDF — most reliable silent PDF printing, no spooler quirks
    $sumatra = @(
        "$env:LOCALAPPDATA\SumatraPDF\SumatraPDF.exe",
        "C:\Program Files\SumatraPDF\SumatraPDF.exe",
        "C:\Program Files (x86)\SumatraPDF\SumatraPDF.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($sumatra) {
        ELog "Method: SumatraPDF ($sumatra)"
        $p = Start-Process $sumatra `
            -ArgumentList "-print-to `"$printer`" -silent `"$pdfPath`"" `
            -Wait -PassThru -WindowStyle Hidden
        ELog "SumatraPDF finished. Exit code: $($p.ExitCode)"
        return
    }

    # Method 2: Windows ShellExecute PrintTo verb (uses default PDF viewer)
    ELog "Method: ShellExecute PrintTo (SumatraPDF not found)"
    try {
        $p = Start-Process -FilePath $pdfPath `
            -Verb PrintTo `
            -ArgumentList "`"$printer`"" `
            -Wait -PassThru -WindowStyle Hidden
        ELog "ShellExecute finished. Exit code: $($p.ExitCode)"
    } catch {
        ELog "ERROR during ShellExecute: $_"
    }
}

# ── Create FileSystemWatcher ───────────────────────────────────────────────────
$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path                  = $WatchRoot
$watcher.Filter                = "morning-briefing.pdf"
$watcher.IncludeSubdirectories = $true
$watcher.NotifyFilter          = [IO.NotifyFilters]::FileName -bor [IO.NotifyFilters]::LastWrite
$watcher.EnableRaisingEvents   = $true

Register-ObjectEvent $watcher "Created" -SourceIdentifier MB_Created `
    -MessageData $state -Action $printAction | Out-Null
Register-ObjectEvent $watcher "Changed" -SourceIdentifier MB_Changed `
    -MessageData $state -Action $printAction | Out-Null

Log "Watcher active. Waiting for morning-briefing.pdf to appear anywhere under $WatchRoot ..."

# ── Keep the script alive forever (lightweight — just sleeps) ─────────────────
try {
    while ($true) { Start-Sleep 30 }
} finally {
    Unregister-Event MB_Created -ErrorAction SilentlyContinue
    Unregister-Event MB_Changed -ErrorAction SilentlyContinue
    $watcher.Dispose()
    Log "Watcher stopped."
}
