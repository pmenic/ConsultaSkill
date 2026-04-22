# ConsultaSkill Watcher — monitors an inbox for new JSON messages
# Usage: powershell -NoProfile -File watcher.ps1 -InboxDir <path> -ReadyFile <path> [-PollSeconds 3] [-HeartbeatSeconds 30]
#
# Output: one line "NEW:<filename>" for each new file detected
# The .ready file is created at startup and removed on exit
# The .ready timestamp is updated every HeartbeatSeconds

param(
    [Parameter(Mandatory=$true)][string]$InboxDir,
    [Parameter(Mandatory=$true)][string]$ReadyFile,
    [int]$PollSeconds = 3,
    [int]$HeartbeatSeconds = 30
)

$ErrorActionPreference = 'SilentlyContinue'

# Create directories if they don't exist
if (-not (Test-Path $InboxDir)) {
    New-Item -ItemType Directory -Path $InboxDir -Force | Out-Null
}
$readyDir = Split-Path $ReadyFile -Parent
if (-not (Test-Path $readyDir)) {
    New-Item -ItemType Directory -Path $readyDir -Force | Out-Null
}

# Determine agent name from inbox path
$agentName = 'unknown'
if ($InboxDir -match 'claude') { $agentName = 'claude' }
elseif ($InboxDir -match 'gemini') { $agentName = 'gemini' }

# Register presence
$readyContent = @{
    agent = $agentName
    pid = $PID
    started_at = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    session_mode = 'active'
    listening_inbox = $InboxDir
} | ConvertTo-Json -Compress
Set-Content -Path $ReadyFile -Value $readyContent -Encoding UTF8

# Catalog files already present
$known = @{}
Get-ChildItem -Path $InboxDir -Filter '*.json' -File -ErrorAction SilentlyContinue | ForEach-Object {
    $known[$_.Name] = $true
}

$lastHeartbeat = Get-Date

Write-Output "WATCHER:STARTED:${agentName}:${PID}"

try {
    while ($true) {
        Start-Sleep -Seconds $PollSeconds

        # Heartbeat: update .ready timestamp
        $now = Get-Date
        if (($now - $lastHeartbeat).TotalSeconds -ge $HeartbeatSeconds) {
            (Get-Item $ReadyFile -ErrorAction SilentlyContinue).LastWriteTime = $now
            $lastHeartbeat = $now
        }

        # Check for new files
        $current = Get-ChildItem -Path $InboxDir -Filter '*.json' -File -ErrorAction SilentlyContinue
        foreach ($file in $current) {
            if (-not $known.ContainsKey($file.Name)) {
                # Wait for file to be fully written (valid JSON)
                $retries = 0
                $valid = $false
                while ($retries -lt 5 -and -not $valid) {
                    try {
                        $content = Get-Content -Path $file.FullName -Raw -ErrorAction Stop
                        $null = $content | ConvertFrom-Json -ErrorAction Stop
                        $valid = $true
                    } catch {
                        Start-Sleep -Milliseconds 300
                        $retries++
                    }
                }
                Write-Output "NEW:$($file.Name)"
                $known[$file.Name] = $true
            }
        }
    }
} finally {
    # Cleanup: remove presence file
    if (Test-Path $ReadyFile) { Remove-Item $ReadyFile -Force -ErrorAction SilentlyContinue }
}
