# ABPPR-ssh.ps1
# Version 1.0
# Configuration is read from .env in this script's directory.

$ErrorActionPreference = "Stop"

function Read-EnvFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Configuration file not found: $Path"
    }

    $settings = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith("#")) { continue }

        $separator = $trimmed.IndexOf("=")
        if ($separator -lt 1) {
            throw "Invalid .env line (expected KEY=VALUE): $line"
        }

        $key = $trimmed.Substring(0, $separator).Trim()
        $value = $trimmed.Substring($separator + 1).Trim()

        if ($value.Length -ge 2) {
            if (($value.StartsWith('"') -and $value.EndsWith('"')) -or
                ($value.StartsWith("'") -and $value.EndsWith("'"))) {
                $value = $value.Substring(1, $value.Length - 2)
            }
        }

        if (-not $key) { throw "Empty setting name in .env line: $line" }
        $settings[$key] = $value
    }
    return $settings
}

function Get-RequiredSetting {
    param([hashtable]$Settings, [string]$Name)
    if (-not $Settings.ContainsKey($Name) -or
        [string]::IsNullOrWhiteSpace([string]$Settings[$Name])) {
        throw "Required setting '$Name' is missing or empty in .env."
    }
    return [string]$Settings[$Name]
}

function Get-IntegerSetting {
    param([hashtable]$Settings, [string]$Name, [int]$Minimum = 1)
    $raw = Get-RequiredSetting -Settings $Settings -Name $Name
    $number = 0
    if (-not [int]::TryParse($raw, [ref]$number) -or $number -lt $Minimum) {
        throw "Setting '$Name' must be an integer greater than or equal to $Minimum."
    }
    return $number
}

function Get-BooleanSetting {
    param([hashtable]$Settings, [string]$Name)
    $raw = (Get-RequiredSetting -Settings $Settings -Name $Name).ToLowerInvariant()
    if ($raw -notin @("true", "false")) {
        throw "Setting '$Name' must be true or false."
    }
    return ($raw -eq "true")
}

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$envPath = Join-Path $scriptDirectory ".env"

$sshProcess = $null
$heidiProcess = $null

try {
    $config = Read-EnvFile -Path $envPath

    # All operational settings are read from .env.
    $sshExe = Get-RequiredSetting $config "SSH_EXE"
    $sshKey = Get-RequiredSetting $config "SSH_KEY"
    $sshHost = Get-RequiredSetting $config "SSH_HOST"
    $sshUser = Get-RequiredSetting $config "SSH_USER"
    $sshPort = Get-IntegerSetting $config "SSH_PORT"
    $localHost = Get-RequiredSetting $config "LOCAL_HOST"
    $localPort = Get-IntegerSetting $config "LOCAL_PORT"
    $remoteDbHost = Get-RequiredSetting $config "REMOTE_DB_HOST"
    $remoteDbPort = Get-IntegerSetting $config "REMOTE_DB_PORT"
    $heidiExe = Get-RequiredSetting $config "HEIDI_EXE"
    $heidiSession = Get-RequiredSetting $config "HEIDI_SESSION"
    $heidiProcessName = Get-RequiredSetting $config "HEIDI_PROCESS_NAME"
    $checkExistingHeidi = Get-BooleanSetting $config "CHECK_EXISTING_HEIDISQL"
    $tunnelTimeoutSeconds = Get-IntegerSetting $config "TUNNEL_START_TIMEOUT_SECONDS"
    $tcpConnectTimeoutMs = Get-IntegerSetting $config "TCP_CONNECT_TIMEOUT_MS"
    $pollIntervalMs = Get-IntegerSetting $config "POLL_INTERVAL_MS"
    $sshKeepAliveIntervalSeconds = Get-IntegerSetting $config "SSH_KEEPALIVE_INTERVAL_SECONDS"
    $sshKeepAliveCountMax = Get-IntegerSetting $config "SSH_KEEPALIVE_COUNT_MAX"
    $exitOnForwardFailure = (Get-RequiredSetting $config "SSH_EXIT_ON_FORWARD_FAILURE").ToLowerInvariant()
    $sshBatchMode = Get-BooleanSetting $config "SSH_BATCH_MODE"
    $sshStrictHostKeyChecking = Get-RequiredSetting $config "SSH_STRICT_HOST_KEY_CHECKING"
    $sshServerAlive = Get-BooleanSetting $config "SSH_SERVER_ALIVE_ENABLED"
    $showMessages = Get-BooleanSetting $config "SHOW_MESSAGES"
    $stopSshOnExit = Get-BooleanSetting $config "STOP_SSH_ON_EXIT"
    $heidiSessionArgumentPrefix = Get-RequiredSetting $config "HEIDI_SESSION_ARGUMENT_PREFIX"

    if ($exitOnForwardFailure -notin @("yes", "no")) {
        throw "SSH_EXIT_ON_FORWARD_FAILURE must be yes or no."
    }
    if ($sshStrictHostKeyChecking -notin @("yes", "no", "accept-new")) {
        throw "SSH_STRICT_HOST_KEY_CHECKING must be yes, no, or accept-new."
    }
    if ($localHost -notin @("127.0.0.1", "localhost")) {
        throw "LOCAL_HOST must be 127.0.0.1 or localhost to keep the tunnel local-only."
    }

    # Expand Windows environment variables in configured paths.
    $sshExe = [Environment]::ExpandEnvironmentVariables($sshExe)
    $sshKey = [Environment]::ExpandEnvironmentVariables($sshKey)
    $heidiExe = [Environment]::ExpandEnvironmentVariables($heidiExe)

    foreach ($pathInfo in @(
        @{ Label = "SSH executable"; Path = $sshExe },
        @{ Label = "SSH private key"; Path = $sshKey },
        @{ Label = "HeidiSQL executable"; Path = $heidiExe }
    )) {
        if (-not (Test-Path -LiteralPath $pathInfo.Path -PathType Leaf)) {
            throw "$($pathInfo.Label) not found: $($pathInfo.Path)"
        }
    }

    if ($checkExistingHeidi -and (Get-Process -Name $heidiProcessName -ErrorAction SilentlyContinue)) {
        throw "HeidiSQL is already running. Close it before launching this script."
    }

    $existingListener = Get-NetTCPConnection -LocalPort $localPort -State Listen -ErrorAction SilentlyContinue
    if ($existingListener) {
        throw "Local port $localPort is already in use. Close the existing tunnel/service or change LOCAL_PORT in .env."
    }

    if ($showMessages) {
        Write-Host "Starting SSH tunnel to $sshUser@$sshHost on port $sshPort ..."
    }

    $sshArguments = @(
        "-p", "$sshPort",
        "-i", "$sshKey",
        "-N",
        "-o", "ExitOnForwardFailure=$exitOnForwardFailure",
        "-o", "StrictHostKeyChecking=$sshStrictHostKeyChecking",
        "-o", "ServerAliveInterval=$(if ($sshServerAlive) { $sshKeepAliveIntervalSeconds } else { 0 })",
        "-o", "ServerAliveCountMax=$sshKeepAliveCountMax"
    )

    if ($sshBatchMode) {
        $sshArguments += @("-o", "BatchMode=yes")
    }

    $sshArguments += @(
        "-L", "${localHost}:${localPort}:${remoteDbHost}:${remoteDbPort}",
        "$sshUser@$sshHost"
    )

    $sshProcess = Start-Process -FilePath $sshExe -ArgumentList $sshArguments -PassThru

    $deadline = (Get-Date).AddSeconds($tunnelTimeoutSeconds)
    $tunnelReady = $false

    while ((Get-Date) -lt $deadline) {
        $sshProcess.Refresh()
        if ($sshProcess.HasExited) {
            throw "SSH exited before the tunnel became available (exit code $($sshProcess.ExitCode)). Check SSH host, port, key, and host-key confirmation."
        }

        $tcp = $null
        try {
            $tcp = [System.Net.Sockets.TcpClient]::new()
            $asyncResult = $tcp.BeginConnect($localHost, $localPort, $null, $null)
            if ($asyncResult.AsyncWaitHandle.WaitOne($tcpConnectTimeoutMs)) {
                $tcp.EndConnect($asyncResult)
                $tunnelReady = $true
                break
            }
        }
        catch {
            # Retry until the configured startup deadline.
        }
        finally {
            if ($tcp) { $tcp.Dispose() }
        }

        Start-Sleep -Milliseconds $pollIntervalMs
    }

    if (-not $tunnelReady) {
        throw "Tunnel did not become available on ${localHost}:$localPort within $tunnelTimeoutSeconds seconds."
    }

    if ($showMessages) {
        Write-Host "Tunnel is listening on ${localHost}:$localPort."
        Write-Host "Opening HeidiSQL session '$heidiSession'..."
    }

    $sessionArgument = "$heidiSessionArgumentPrefix$heidiSession"
    $heidiProcess = Start-Process -FilePath $heidiExe -ArgumentList @($sessionArgument) -PassThru

    while ($true) {
        $heidiProcess.Refresh()
        $sshProcess.Refresh()

        if ($heidiProcess.HasExited) {
            if ($showMessages) { Write-Host "HeidiSQL closed." }
            break
        }

        if ($sshProcess.HasExited) {
            throw "SSH tunnel process exited while HeidiSQL was open (exit code $($sshProcess.ExitCode))."
        }

        Start-Sleep -Milliseconds $pollIntervalMs
    }
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    if ($stopSshOnExit -and $sshProcess) {
        try {
            $sshProcess.Refresh()
            if (-not $sshProcess.HasExited) {
                if ($showMessages) { Write-Host "Closing SSH tunnel..." }
                Stop-Process -Id $sshProcess.Id -Force -ErrorAction SilentlyContinue
                $sshProcess.WaitForExit(5000)
            }
        }
        catch {
            Write-Host "WARNING: Could not confirm SSH process cleanup: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    if ($showMessages) { Write-Host "Finished." }
}
