```powershell
# ABPPR-ssh.ps1
# Starts SSH tunnel, opens HeidiSQL, and closes the tunnel on exit.

$ErrorActionPreference = "Stop"

$SshExe    = "$env:WINDIR\System32\OpenSSH\ssh.exe"
$SshKey    = "$env:USERPROFILE\.ssh\heidisql_vps"
$SshTarget = "armbp@78.128.43.212"
$SshPort   = 6543

$LocalPort = 3307
$DbTarget  = "127.0.0.1:3306"

$Session   = "ABPPR_ssh"
$HeidiExe  = "C:\Program Files\HeidiSQL\heidisql.exe"

$sshProcess = $null
$heidiProcess = $null

try {
    # Validate required files
    if (-not (Test-Path $SshExe)) {
        throw "OpenSSH executable not found: $SshExe"
    }

    if (-not (Test-Path $SshKey)) {
        throw "Private SSH key not found: $SshKey"
    }

    if (-not (Test-Path $HeidiExe)) {
        throw "HeidiSQL not found: $HeidiExe"
    }

    # Avoid closing an existing HeidiSQL instance accidentally
    if (Get-Process -Name "heidisql" -ErrorAction SilentlyContinue) {
        throw "Close all HeidiSQL windows before running this script."
    }

    # Ensure the local port is available
    $existingListener = Get-NetTCPConnection `
        -LocalPort $LocalPort `
        -State Listen `
        -ErrorAction SilentlyContinue

    if ($existingListener) {
        throw "Local port $LocalPort is already in use."
    }

    Write-Host "Starting SSH tunnel..."

    $sshArgs = @(
        "-p", "$SshPort",
        "-i", "`"$SshKey`"",
        "-N",
        "-o", "ExitOnForwardFailure=yes",
        "-o", "ServerAliveInterval=30",
        "-o", "ServerAliveCountMax=3",
        "-L", "127.0.0.1:${LocalPort}:${DbTarget}",
        $SshTarget
    )

    $sshProcess = Start-Process `
        -FilePath $SshExe `
        -ArgumentList $sshArgs `
        -PassThru `
        -NoNewWindow

    # Wait up to 15 seconds for the local tunnel listener
    $deadline = (Get-Date).AddSeconds(15)
    $tunnelReady = $false

    while ((Get-Date) -lt $deadline) {
        if ($sshProcess.HasExited) {
            throw "SSH exited unexpectedly (code $($sshProcess.ExitCode))."
        }

        $tcp = $null

        try {
            $tcp = [System.Net.Sockets.TcpClient]::new()
            $connect = $tcp.BeginConnect(
                "127.0.0.1",
                $LocalPort,
                $null,
                $null
            )

            if ($connect.AsyncWaitHandle.WaitOne(500)) {
                $tcp.EndConnect($connect)
                $tunnelReady = $true
                break
            }
        }
        catch {
            # Tunnel is not ready yet
        }
        finally {
            if ($tcp) {
                $tcp.Dispose()
            }
        }

        Start-Sleep -Milliseconds 250
    }

    if (-not $tunnelReady) {
        throw "Tunnel did not become available on local port $LocalPort."
    }

    Write-Host "Tunnel is listening on 127.0.0.1:$LocalPort."
    Write-Host "Opening HeidiSQL session '$Session'..."

    $heidiProcess = Start-Process `
        -FilePath $HeidiExe `
        -ArgumentList @("-d=$Session") `
        -PassThru

    # Keep the tunnel alive while HeidiSQL remains open
    while (-not $heidiProcess.HasExited) {
        if ($sshProcess.HasExited) {
            throw "SSH tunnel terminated while HeidiSQL was open."
        }

        Start-Sleep -Seconds 1
        $heidiProcess.Refresh()
    }

    Write-Host "HeidiSQL closed."
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    # Always terminate the SSH tunnel started by this script
    if ($sshProcess -and -not $sshProcess.HasExited) {
        Write-Host "Closing SSH tunnel..."
        Stop-Process -Id $sshProcess.Id -Force -ErrorAction SilentlyContinue
    }

    Write-Host "Finished."
}
```