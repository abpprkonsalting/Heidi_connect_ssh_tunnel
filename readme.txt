ABPPR SSH Tunnel Launcher - Version 1.0
=======================================

PURPOSE
-------
Starts an SSH local port forward, opens a saved HeidiSQL session, and stops
the SSH process started by the script when HeidiSQL closes.

The default tunnel is:
  Local endpoint:  127.0.0.1:3307
  Remote endpoint: 127.0.0.1:3306 as seen from the VPS

Keep MariaDB bound to localhost on the VPS. Do not expose TCP/3306 publicly.

FILES
-----
ABPPR-ssh.ps1   PowerShell launcher.
.env            Local configuration. Keep beside the script.
.env.example    Sanitized template for publishing/sharing.
readme.txt      This document.
todo.txt        Future improvements.

REQUIREMENTS
------------
- Windows PowerShell.
- OpenSSH client (ssh.exe).
- HeidiSQL installed.
- SSH access to the VPS using the configured private key.
- A saved HeidiSQL session matching HEIDI_SESSION.

INSTALLATION
------------
1. Keep ABPPR-ssh.ps1 and .env in the same directory.
2. Edit .env and verify the SSH host, user, port, private key path, and the
   actual path to heidisql.exe.
3. In HeidiSQL, edit the saved session named in HEIDI_SESSION:
   - Network type: MariaDB or MySQL (TCP/IP)
   - Host: the value of LOCAL_HOST (127.0.0.1 by default)
   - Port: the value of LOCAL_PORT (3307 by default)
   - User/password: your MariaDB credentials
4. Close HeidiSQL before starting the launcher.
5. Run from PowerShell:

   powershell.exe -ExecutionPolicy Bypass -File "C:\path\to\ABPPR-ssh.ps1"

SERVER-SIDE SSH SETUP (DEBIAN / UBUNTU)
-------------------------------------

The VPS must accept SSH connections from the Windows client using public-key
authentication. The following steps describe a basic OpenSSH server setup.

1. Install and enable the SSH server:

   sudo apt update
   sudo apt install openssh-server
   sudo systemctl enable --now ssh

2. Create a dedicated SSH account if one does not already exist:

   sudo adduser <SSH_USERNAME>

   Replace <SSH_USERNAME> with the intended Linux account name. An existing,
   appropriately secured account may be used instead. Do not use the root
   account for routine tunnel access.

3. Configure public-key authentication:

   On the Windows client, generate an SSH key pair if necessary. Keep the
   private key on Windows and install only the public key on the VPS.

   Create the SSH directory and authorized_keys file for the account.
   Replace <SSH_USERNAME> and <SSH_HOME> with the account name and its actual
   home directory:

   sudo install -d -m 700 -o <SSH_USERNAME> -g <SSH_USERNAME> <SSH_HOME>/.ssh
   sudo touch <SSH_HOME>/.ssh/authorized_keys
   sudo chown <SSH_USERNAME>:<SSH_USERNAME> <SSH_HOME>/.ssh/authorized_keys
   sudo chmod 600 <SSH_HOME>/.ssh/authorized_keys

   Add the public key to authorized_keys without overwriting existing keys.
   Confirm that the account's home directory and SSH files have the correct
   ownership and permissions.

4. Verify the SSH server configuration:

   Check /etc/ssh/sshd_config and any applicable files under
   /etc/ssh/sshd_config.d/. Ensure public-key authentication is enabled and
   that the configuration permits the intended account to connect.

   Validate the configuration before applying changes:

   sudo sshd -t

   If the configuration is valid, reload the SSH service:

   sudo systemctl reload ssh

5. Configure the firewall:

   Allow inbound connections to the configured SSH port from the intended
   client IP addresses, where practical.

   If changing the SSH port, ensure the SSH server configuration, firewall
   rules, and SSH_PORT in .env all match. Keep an existing SSH session open
   while making changes, so you can recover if the new configuration fails.

6. Test the connection from Windows:

   ssh -p <SSH_PORT> -i "<PRIVATE_KEY_PATH>" <SSH_USERNAME>@<SSH_HOST>

   Replace the placeholders with the actual SSH port, private-key path,
   username, and server hostname or IP address.

   Verify the server's host-key fingerprint before trusting the connection.
   Do not blindly accept an unexpected host key.

7. Keep the database private:

   For a database accessed through a local SSH tunnel, configure the database
   to listen on the appropriate loopback interface on the VPS. Confirm that
   the configured REMOTE_DB_HOST and REMOTE_DB_PORT in .env match the actual
   database endpoint as seen from the VPS.

   Do not expose the database port to the public internet merely to enable
   remote access. The SSH tunnel should provide the required access.

SECURITY NOTES
--------------
- Keep the private key on the Windows client; install only its public key
  on the VPS.
- Protect the SSH account and private key.
- Restrict SSH access through the firewall where practical.
- Do not disable password authentication until key-based access has been
  tested successfully and an alternative recovery method is available.
- Preserve an existing SSH session while changing SSH configuration.
- Back up configuration files before modifying them.

CONFIGURATION
-------------
The launcher reads operational settings from .env. It accepts KEY=VALUE lines,
ignores blank lines and lines starting with #, and removes one matching pair
of surrounding single or double quotes. This is a deliberately small .env
format, not a full implementation of every .env dialect.

Path values may contain Windows environment variables such as %USERPROFILE%.

Important settings:
- SSH_EXE, SSH_KEY: SSH client and private key paths.
- SSH_HOST, SSH_USER, SSH_PORT: remote SSH endpoint.
- LOCAL_HOST, LOCAL_PORT: local tunnel listener. Keep LOCAL_HOST at 127.0.0.1
  to prevent other computers from using the forwarded port.
- REMOTE_DB_HOST, REMOTE_DB_PORT: database endpoint as seen by the VPS.
- HEIDI_EXE, HEIDI_SESSION, HEIDI_PROCESS_NAME: HeidiSQL program, saved
  session name, and Windows process name.
- HEIDI_SESSION_ARGUMENT_PREFIX: command-line prefix used to open a saved
  HeidiSQL session (default -d=).
- CHECK_EXISTING_HEIDISQL: refuse to start if HeidiSQL is already running.
- TUNNEL_START_TIMEOUT_SECONDS: maximum time to wait for the local listener.
- TCP_CONNECT_TIMEOUT_MS: timeout for an individual startup TCP probe.
- POLL_INTERVAL_MS: interval between startup/runtime checks.
- SSH_KEEPALIVE_INTERVAL_SECONDS, SSH_KEEPALIVE_COUNT_MAX:
  OpenSSH liveness settings.
- SSH_EXIT_ON_FORWARD_FAILURE: OpenSSH ExitOnForwardFailure option (yes/no).
- SSH_BATCH_MODE: if true, disables interactive SSH prompts. Use only after
  host-key verification and authentication are ready for unattended use.
- SSH_STRICT_HOST_KEY_CHECKING: yes, no, or accept-new. For normal secure use,
  verify the server fingerprint and prefer yes after the key is in known_hosts.
- SSH_SERVER_ALIVE_ENABLED: enables/disables SSH server-alive probes.
- SSH_PROCESS_NAME: informational setting for the SSH process executable name.
- STOP_SSH_ON_EXIT: terminate the SSH process started by this script on exit.
- SHOW_MESSAGES: show routine status messages.

RUN
===

OPTION 1: RUN FROM POWERSHELL

Open PowerShell and run the following command, replacing the example path with the actual location of ABPPR-ssh.ps1:

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\path\to\ABPPR-ssh.ps1"

Keep the console window open while HeidiSQL is running. Closing HeidiSQL ends the SSH tunnel started by this script.


OPTION 2: CREATE A WINDOWS DESKTOP SHORTCUT

1. Right-click an empty area of the Windows desktop.
2. Select New > Shortcut.
3. In the location field, enter the following command, replacing the example path with the actual folder containing ABPPR-ssh.ps1 and .env:

powershell.exe -NoProfile -NoExit -ExecutionPolicy Bypass -File "C:\path\to\ABPPR_ssh_v1.0\ABPPR-ssh.ps1"

4. Click Next.
5. Name the shortcut ABPPR SSH Tunnel.
6. Click Finish.

The .env file must remain in the same directory as ABPPR-ssh.ps1.

To modify the shortcut later, right-click it, select Properties, and edit the Target field. Keep the script path inside double quotes.

SECURITY
--------
- Do not store MariaDB passwords in .env.
- Protect the SSH private key and never publish it.
- Verify the SSH host-key fingerprint before trusting a new server.
- Do not open the VPS firewall for public TCP port 3306.
- Do not publish your personal .env. Use .env.example as a sanitized template.

CURRENT CHECKS / LIMITATIONS
----------------------------
- Validates configured executable and private key paths.
- Optionally refuses to run if HeidiSQL is already open.
- Refuses to use a local port that is already listening.
- Asks SSH to exit if requested forwarding cannot be established.
- Waits up to TUNNEL_START_TIMEOUT_SECONDS for the local TCP listener.
- Monitors the SSH and HeidiSQL processes.
- Attempts to stop the SSH process started by the script after HeidiSQL exits.

The TCP readiness probe confirms a local TCP listener; it does not authenticate
to MariaDB or execute SQL. Use HeidiSQL to confirm database availability.

TROUBLESHOOTING
---------------
SSH executable/key/HeidiSQL not found:
  Correct the matching path in .env.

Local port is already in use:
  Close the old tunnel or choose another LOCAL_PORT, then update the saved
  HeidiSQL session to use the same port.

Tunnel fails to start:
  Check SSH_HOST, SSH_PORT, SSH_USER, SSH_KEY, host-key confirmation, and
  whether the VPS permits TCP forwarding.

HeidiSQL opens but cannot connect:
  Confirm the saved session uses TCP/IP, LOCAL_HOST, LOCAL_PORT, and valid
  MariaDB credentials.

Two HeidiSQL sessions at the same time:
  To use an existing HeidiSQL connection alongside the SSH tunnel connection:

  1. Open HeidiSQL.
  2. Go to Tools > Preferences and locate the "Allow multiple instances"
     setting. Enable it so the launcher can open a separate HeidiSQL instance
     without interfering with the existing session.
  3. Keep the existing HeidiSQL session open.
  4. Open PowerShell manually and run the launcher explicitly, replacing the
     example path with the actual location of ABPPR-ssh.ps1:

     powershell.exe -NoProfile -NoExit -ExecutionPolicy Bypass -File "C:\path\to\ABPPR-ssh.ps1"

  5. If the launcher refuses to start because HeidiSQL is already running,
     check CHECK_EXISTING_HEIDISQL in .env. Set it to false only if you want
     to allow the launcher to start while another HeidiSQL instance is open.
  6. Ensure the ABPPR_ssh saved session connects to 127.0.0.1 using the
     configured LOCAL_PORT (3307 by default).

  Keep the existing connection settings unchanged. When the SSH-connected
  HeidiSQL instance closes, the launcher should stop only the SSH process
  it started.