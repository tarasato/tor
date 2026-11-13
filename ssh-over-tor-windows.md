# SSH over Tor (Onion Service) — Windows server

Reach this PC's SSH server from anywhere through a Tor Onion Service — no router port forwarding, no public IP, and **no inbound firewall port**.

> Back to the main guide: [`readme.md`](./readme.md) (installing and verifying tor, `torrc` basics) · Arch Linux version: [`ssh-over-tor-arch.md`](./ssh-over-tor-arch.md)
> Tested on 2026-11-13: Windows 11 (build 26300), Win32-OpenSSH 10.4 (winget), Tor Expert Bundle 16.0.1

```
client ── tor (9050/9150) ══ Tor network ══ tor on server ── 127.0.0.1:22 ── sshd
```

**Which shell?** Every step says where to run it:
- **PowerShell (Admin)** — right-click Start → *Terminal (Admin)*. Needed for services, firewall, and anything under `C:\ProgramData\ssh\`.
- **Git Bash** — paths look like `/c/...` and `~/.ssh/...`; programs in the current folder need `./`.
- **cmd** — shown where it differs.

Where a command only works in one shell, the alternative is given right below it.

---

## 1. Server — install OpenSSH Server

**PowerShell (Admin):**

```powershell
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Get-Service sshd
```

If `Get-Service sshd` says **`Cannot find any service with service name 'sshd'`** even though `Add-WindowsCapability` reported success
(happens on Insider/preview builds — `C:\Windows\System32\OpenSSH\` then has `ssh.exe` but no `sshd.exe`), install Microsoft's build via winget instead:

```powershell
winget install Microsoft.OpenSSH.Preview
```

Accept the UAC prompt, **close and reopen PowerShell (Admin)**, then:

```powershell
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic
Get-Service sshd                # Status must be Running
```

- winget installs to `C:\Program Files\OpenSSH\`; the config is still `C:\ProgramData\ssh\sshd_config`.
- No winget? Download `OpenSSH-Win64-v*.msi` from <https://github.com/PowerShell/Win32-OpenSSH/releases> and run it.
- Check the service binary from **cmd / Git Bash**: `sc.exe qc sshd` → `BINARY_PATH_NAME`.

## 2. Server — configure `sshd_config`

Open it in **PowerShell (Admin)** (the file is admin-only, so Git Bash editors can't save it):

```powershell
notepad C:\ProgramData\ssh\sshd_config
```

It must contain these lines — **and the `Match` block must stay at the very end of the file**:

```text
ListenAddress 127.0.0.1
PasswordAuthentication no
PubkeyAuthentication yes

Match Group administrators
       AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys
```

- `ListenAddress 127.0.0.1` — sshd accepts only local connections; only tor (on the same machine) can reach it.
- ⚠️ **Don't replace the whole file with just the first three lines.** Without the `Match Group administrators` block, sshd looks for an admin's keys in
  `C:\Users\<you>\.ssh\authorized_keys` instead, and every login fails with `Permission denied (publickey,keyboard-interactive)`.
- Settings added later go **above** `Match` — anything below it only applies to that group.

To append the `Match` block without an editor (**PowerShell (Admin)**; the leading `` `r`n `` stops it gluing onto the last line):

```powershell
Add-Content C:\ProgramData\ssh\sshd_config "`r`nMatch Group administrators`r`n       AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys"
Get-Content C:\ProgramData\ssh\sshd_config
```

Leave `PasswordAuthentication no` for after §3 if you're not sure the key works yet — otherwise you can lock yourself out.

## 3. SSH keys — create, authorize, use, manage

### 3.0 How keys work (read once)

An SSH key is a **pair** of files:

| File | Example | Where it lives | Share? |
|---|---|---|---|
| **Private key** | `~/.ssh/example-ssh-tor-ed25519` | Only on the **client** (the device you connect *from*) | **Never** — whoever has it can log in |
| **Public key** | `~/.ssh/example-ssh-tor-ed25519.pub` | Copied to the **server** (the PC you connect *to*) | Safe to share |

- The server keeps a list of trusted public keys (`administrators_authorized_keys` or `authorized_keys`). When you connect, the client proves it holds the matching private key — no password crosses the network.
- A `.pub` file alone can't log in anywhere. To use a key on another device you need the **private** key there (§3.6), or better, a new key for that device.
- A **passphrase** encrypts the private key on disk. If the file is stolen it's useless without the passphrase. `ssh-agent` (§3.5) remembers it so you don't type it every time.
- **Fingerprint** = short ID of a key (`SHA256:AV/kKV8n...`). Use it to check that the key on the server is the one on the client.
- Recommended: **one key per device**, each with a clear comment (`-C "phone-tor-ssh"`), so you can revoke one device without touching the others (§3.8).

### 3.1 Create a key pair (on the client)

**Git Bash / PowerShell / Linux / macOS / Termux** — same command everywhere:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/example-ssh-tor-ed25519 -C "tor-ssh"
```

- `-t ed25519` — modern, short, fast key type (use this).
- `-f` — file name. Pick a descriptive one; the `.pub` is created next to it.
- `-C` — comment stored in the public key; shows up in the server's key list. Use the device name (`pc-office`, `phone-tor-ssh`, …).
- It asks `Enter passphrase` — **set one** (typing shows nothing; that's normal). Empty = no passphrase.
- In **PowerShell**, if `~` isn't expanded, write `$HOME\.ssh\example-ssh-tor-ed25519`.
- `~/.ssh` doesn't exist yet? `mkdir -p ~/.ssh` (Git Bash) / `mkdir $HOME\.ssh` (PowerShell).

Check what you got:

```bash
ls -l ~/.ssh/example-ssh-tor-ed25519*                 # two files: key and key.pub
ssh-keygen -lf ~/.ssh/example-ssh-tor-ed25519.pub     # fingerprint + comment
cat ~/.ssh/example-ssh-tor-ed25519.pub                # one line: ssh-ed25519 AAAA... tor-ssh
```
```powershell
Get-Content $HOME\.ssh\example-ssh-tor-ed25519.pub    # PowerShell
```

### 3.2 Authorize the key on the server

Which file depends on the Windows account you log in **as** on the server:

| Account type (check: `net localgroup Administrators`) | File | Notes |
|---|---|---|
| **Administrator** | `C:\ProgramData\ssh\administrators_authorized_keys` | Needs the `Match Group administrators` block (§2) and strict permissions |
| Standard user | `C:\Users\<you>\.ssh\authorized_keys` | No `icacls` needed |

**Administrator account — PowerShell (Admin):**

```powershell
Add-Content C:\ProgramData\ssh\administrators_authorized_keys "ssh-ed25519 AAAA...your key... tor-ssh"
icacls C:\ProgramData\ssh\administrators_authorized_keys /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F"
Restart-Service sshd
```

- `Add-Content` **appends** one line (and creates the file the first time) — existing keys keep working. Run it once per device key.
- ⚠️ Don't use `Set-Content` (or `>` in bash) on this file — that **overwrites** it and removes every other key.
- The key must stay on **one line**; paste the whole `.pub` content including `ssh-ed25519` at the start.
- File name ends in `_keys` — `icacls` saying `The system cannot find the file specified` usually means a typo.
- `icacls` must print `Successfully processed 1 files`. sshd silently ignores the file if other users can write to it. Run `icacls` again after editing the file with Notepad.
- Git Bash can't read or write this file after `icacls` (`Permission denied`) — that's expected; use PowerShell (Admin).

Copying the `.pub` from the client to the server: it's one line of text, so paste it via chat/email/USB — it's public. (Never send the private key that way.)

**Standard account** (in Git Bash on the server):

```bash
mkdir -p ~/.ssh && cat example-ssh-tor-ed25519.pub >> ~/.ssh/authorized_keys
```

### 3.3 Verify the server has the right key

Fingerprints must match:

```powershell
ssh-keygen -lf C:\ProgramData\ssh\administrators_authorized_keys   # server, PowerShell (Admin) - one line per key
```
```bash
ssh-keygen -lf ~/.ssh/example-ssh-tor-ed25519.pub                  # client
```

### 3.4 Use the key

Test on the server itself first (no Tor yet):

```bash
ssh -i ~/.ssh/example-ssh-tor-ed25519 user@127.0.0.1
```

From **another device**, `127.0.0.1` would point at that device itself — use the `.onion` address through the client's tor (§5–§6):

```bash
ssh -i ~/.ssh/example-ssh-tor-ed25519 -o ProxyCommand="connect -S 127.0.0.1:9050 %h %p" user@xxxxxxxx.onion
```

| Where you run `ssh` | Host part | Proxy |
|---|---|---|
| On the server itself (test) | `user@127.0.0.1` | none |
| Other Windows PC (Git Bash) | `user@xxxxxxxx.onion` | `connect -S 127.0.0.1:9050 %h %p` (9150 with Tor Browser) |
| Linux / macOS / Termux | `user@xxxxxxxx.onion` | `nc -X 5 -x 127.0.0.1:9050 %h %p` or `torsocks ssh ...` |
| Android with Tor VPN | `user@xxxxxxxx.onion` | none (the VPN handles it) |

The `127.0.0.1:9050` inside `ProxyCommand` is the **client's own** tor — that one never changes to the .onion address.

- `-i` picks the private key (not the `.pub`).
- `user` = the Windows account name on the server (replace with yours).
- First connection asks to trust the host key (`yes`) — it's then stored in `~/.ssh/known_hosts`.

Day-to-day, put it in `~/.ssh/config` so you never type `-i` (full Tor version in §6):

```text
Host mypc
    HostName xxxxxxxx.onion
    User user
    IdentityFile ~/.ssh/example-ssh-tor-ed25519
    IdentitiesOnly yes
```

`IdentitiesOnly yes` = only offer this key. Without it, ssh tries every key it knows and the server may cut you off with `Too many authentication failures`.

### 3.5 Passphrase and ssh-agent

Add or change a passphrase on an existing key (the public key stays the same, nothing to change on the server):

```bash
ssh-keygen -p -f ~/.ssh/example-ssh-tor-ed25519
```

Avoid typing it on every connection with `ssh-agent`:

- **Windows (PowerShell Admin, once)** — the agent runs as a service and remembers keys across reboots:
  ```powershell
  Set-Service ssh-agent -StartupType Automatic
  Start-Service ssh-agent
  ssh-add $HOME\.ssh\example-ssh-tor-ed25519
  ssh-add -l                      # list loaded keys
  ```
  This agent works with Windows' `ssh.exe` (PowerShell / cmd). Git Bash's `ssh` doesn't see it — use the next option there, or run `ssh.exe` from Git Bash.
- **Git Bash / Linux / Termux** (per terminal session):
  ```bash
  eval "$(ssh-agent -s)"
  ssh-add ~/.ssh/example-ssh-tor-ed25519
  ```
- Or add `AddKeysToAgent yes` under `Host mypc` in `~/.ssh/config`: the first connection asks for the passphrase and loads the key into the running agent.
- Remove keys from the agent: `ssh-add -D`.

### 3.6 Using the same key on another device (not recommended)

Possible, but copy the **private** key (and set a passphrase first) — see the Termux example in §7.1. Prefer a new key per device (§3.1 on that device, §3.2 on the server).

Private-key permissions on the new device:

- **Linux / macOS / Termux:** `chmod 700 ~/.ssh && chmod 600 ~/.ssh/example-ssh-tor-ed25519`
- **Windows** — if ssh complains `UNPROTECTED PRIVATE KEY FILE` / `bad permissions`, PowerShell:
  ```powershell
  icacls $HOME\.ssh\example-ssh-tor-ed25519 /inheritance:r /grant "${env:USERNAME}:F"
  ```

### 3.7 Back up keys

- Client private keys: back up `~/.ssh/` somewhere encrypted (password manager attachment, encrypted USB). Losing a key isn't fatal — create a new one and authorize it from another way in (local login, another device's key).
- Server: `administrators_authorized_keys` and the host keys `C:\ProgramData\ssh\ssh_host_*` (keeping the host keys avoids the `REMOTE HOST IDENTIFICATION HAS CHANGED` warning after a reinstall).
- Never put private keys in git (this repo's `.gitignore` doesn't cover `~/.ssh` — it's outside the repo; keep it that way).

### 3.8 Revoke / rotate a key

- **Revoke a device:** PowerShell (Admin) `notepad C:\ProgramData\ssh\administrators_authorized_keys`, delete that device's line (the comment at the end tells you which), save, re-run the `icacls` line from §3.2, `Restart-Service sshd`.
- **Rotate** (e.g. yearly, or if a device was lost): create a new key on the client (§3.1), authorize it (§3.2), test it, then delete the old line.
- List what's authorized: `ssh-keygen -lf C:\ProgramData\ssh\administrators_authorized_keys` (PowerShell Admin).

### 3.9 Log in as an administrator or as a standard user

Each SSH login is a **Windows account** on the server: `ssh <account>@<host>`. You can have both an admin login (full control) and a standard-user login (everyday work, can't change the system).

| | Administrator account | Standard user account |
|---|---|---|
| Key file on the server | `C:\ProgramData\ssh\administrators_authorized_keys` (**one file shared by all admin accounts**) | `C:\Users\<account>\.ssh\authorized_keys` (per account) |
| Session rights | Full admin (elevated — no UAC prompt over SSH) | Normal user rights only |
| Can run `Restart-Service`, `icacls` on ProgramData, install software | Yes | No |
| Good for | Server maintenance | Daily use, file access, less damage if a key leaks |

⚠️ A key in `administrators_authorized_keys` can log in to **every** administrator account on that PC. Only put keys there for devices you'd trust with full control.

#### 3.9.1 Check which accounts exist and what they are

**PowerShell:**

```powershell
whoami                                 # current account
Get-LocalUser | Select Name,Enabled    # local accounts
net localgroup Administrators          # which ones are admins
```

The SSH login name is the **local account name** (the `Name` column, usually the folder name under `C:\Users\`). For a Microsoft-account login you can also use the email address.

#### 3.9.2 (Optional) create a standard user just for SSH

**PowerShell (Admin):**

```powershell
$pw = Read-Host -AsSecureString "Password for the new account"
New-LocalUser -Name "sshuser" -Password $pw -FullName "SSH user" -PasswordNeverExpires
Add-LocalGroupMember -Group "Users" -Member "sshuser"
```

- The password is only for logging in at the PC itself — SSH still uses keys (`PasswordAuthentication no`).
- Its profile folder `C:\Users\sshuser\` is created at its **first** login. Create it now by signing in once at the PC, or with `runas /user:sshuser cmd` (enter the password, then close the window).

#### 3.9.3 Authorize a key for the standard user

**PowerShell (Admin)** — the folder belongs to the other account, so use an admin shell:

```powershell
$u = "sshuser"
New-Item -ItemType Directory -Force "C:\Users\$u\.ssh" | Out-Null
Add-Content "C:\Users\$u\.ssh\authorized_keys" "ssh-ed25519 AAAA...client key... laptop-user"
icacls "C:\Users\$u\.ssh\authorized_keys" /inheritance:r /grant "${u}:F" /grant "SYSTEM:F" /grant "Administrators:F"
```

- If you're signed in **as that user**, Git Bash works too: `mkdir -p ~/.ssh && cat key.pub >> ~/.ssh/authorized_keys`.
- sshd rejects the file if another non-admin user can write to it — the `icacls` line prevents that.
- Use a **different key** from the admin one, so a device can be given user access without admin access.

Admin keys are set up in §3.2 (`administrators_authorized_keys`).

#### 3.9.4 Connect as admin or as user

**On the server itself** (local test, no Tor):

```bash
ssh -i ~/.ssh/example-admin-ed25519 adminaccount@127.0.0.1    # admin
ssh -i ~/.ssh/example-user-ed25519  sshuser@127.0.0.1         # standard user
```

**From any other device** — `127.0.0.1` would mean *that* device itself, so use the `.onion` address and go through Tor (tor running on the client, §6):

```bash
ssh -i ~/.ssh/example-admin-ed25519 -o ProxyCommand="connect -S 127.0.0.1:9050 %h %p" adminaccount@xxxxxxxx.onion
ssh -i ~/.ssh/example-user-ed25519  -o ProxyCommand="connect -S 127.0.0.1:9050 %h %p" sshuser@xxxxxxxx.onion
```

(`127.0.0.1:9050` in `ProxyCommand` is the client's own tor SOCKS port — that one stays. Termux / Linux: `nc -X 5 -x 127.0.0.1:9050 %h %p`; Tor VPN on Android: no `ProxyCommand` at all.)

Two entries in the client's `~/.ssh/config`, same .onion address, different account and key:

```text
Host mypc-admin
    HostName xxxxxxxx.onion
    User adminaccount
    IdentityFile ~/.ssh/example-admin-ed25519
    IdentitiesOnly yes
    ProxyCommand connect -S 127.0.0.1:9050 %h %p

Host mypc-user
    HostName xxxxxxxx.onion
    User sshuser
    IdentityFile ~/.ssh/example-user-ed25519
    IdentitiesOnly yes
    ProxyCommand connect -S 127.0.0.1:9050 %h %p
```

```bash
ssh mypc-admin
ssh mypc-user
```

Check what you got after logging in:

```powershell
whoami                     # account name
whoami /groups | findstr /i "S-1-16-12288 S-1-16-8192"   # High = admin (elevated), Medium = standard
```

#### 3.9.5 Getting admin rights from a user session

There's no `sudo` over SSH on Windows (UAC can't prompt in an SSH session, and Windows' own `sudo` doesn't work there). When you need admin rights, **disconnect and log in as the admin account** (`ssh mypc-admin`). Keep admin logins for maintenance only.

#### 3.9.6 Restrict who may log in (optional)

Add **above** the `Match` block in `sshd_config` (PowerShell (Admin) `notepad C:\ProgramData\ssh\sshd_config`), then `Restart-Service sshd`:

```text
# only these accounts may log in over SSH
AllowUsers adminaccount sshuser
```

Or by group — names are case-sensitive and lower-case for built-in groups:

```text
AllowGroups administrators users
```

To allow **only** the standard user (no admin over SSH at all): `AllowUsers sshuser` and leave `administrators_authorized_keys` empty.

#### 3.9.7 Shell after login: cmd, PowerShell or Git Bash

SSH sessions start in **`cmd.exe`** by default.

**Git Bash over SSH:** `git-bash.exe` opens a *window on the PC's screen*, so it does nothing useful over SSH. Run the console shell `bash.exe` instead:

```bat
"C:\Program Files\Git\bin\bash.exe" -l
```

(`-l` = login shell, so `~/.bashrc` / `~/.bash_profile` are loaded.)

**Make Git Bash the default** — **PowerShell (Admin)**, no sshd restart needed:

```powershell
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value "C:\Program Files\Git\bin\bash.exe" -PropertyType String -Force
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShellCommandOption -Value "-c" -PropertyType String -Force
```

**Or PowerShell as the default:**

```powershell
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force
```

- Applies to every account and the next SSH login.
- Back to `cmd.exe`: `Remove-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell` (and `DefaultShellCommandOption` if you set it).
- Commands passed on the ssh line (`ssh mypc "git status"`) also run in the default shell — with Git Bash that's bash syntax.

#### 3.9.8 Interactive programs over SSH

Full-screen / interactive programs (editors, `htop`-style tools, AI CLIs such as Hermes Agent, `python` REPL) need a terminal:

- Logging in first and then starting the program works as usual.
- Starting it directly from the ssh command needs `-t`: `ssh -t mypc hermes` (without `-t` you get *not a terminal* errors or no prompt).
- A program that's installed but not on `PATH` → `command not found`; run it by full path or see §3.9.9.

#### 3.9.9 (Optional) add your own tools to `PATH` in Git Bash

Programs installed per user (e.g. under `AppData\Local\...`) are often not on the SSH session's `PATH`. Add their folder in `~/.bashrc` — example for Hermes Agent:

```bash
echo 'export PATH="$PATH:/c/Users/<you>/AppData/Local/hermes/bin"' >> ~/.bashrc
source ~/.bashrc
which hermes          # should print the path
```

- Replace `<you>` with your Windows account folder name; repeat the `echo` line for other tools.
- `>>` appends — run it once (running it twice just adds a duplicate line; harmless but messy, remove it with any editor).
- This only affects Git Bash. For cmd / PowerShell, add the folder to the user `PATH` instead: **PowerShell** `[Environment]::SetEnvironmentVariable("Path", [Environment]::GetEnvironmentVariable("Path","User") + ";C:\Users\<you>\AppData\Local\hermes\bin", "User")`, then log in again.

## 4. Firewall — open nothing inbound

tor connects **outbound** to the Tor network and hands traffic to `127.0.0.1:22` inside the machine, so no inbound rule is needed.
Installers create an inbound SSH rule — disable it. **PowerShell (Admin):**

```powershell
Get-NetFirewallRule -DisplayName "*SSH*" | Select Name,DisplayName,Enabled,Direction
Get-NetFirewallRule -DisplayName "*SSH*" | Disable-NetFirewallRule
```

(The rule is `OpenSSH-Server-In-TCP` for the Windows capability and `OpenSSH SSH Server Preview (sshd)` for the winget build.)

From **cmd / Git Bash** you can only check:

```bash
netstat -ano | grep ':22 '          # Git Bash
```
```bat
netstat -ano | findstr :22          :: cmd
```

Must show only `127.0.0.1:22 ... LISTENING`. `0.0.0.0:22` means sshd is still reachable from the network.

- Don't open 9050/9150 inbound either — SOCKS ports are local only.
- Outbound is allowed by default; if you block outbound traffic, allow `tor.exe`.

## 5. Server — publish the Onion Service

Add to the server's `torrc` (any editor; see [`readme.md` §3](./readme.md#3-configure-torrc)):

```text
HiddenServiceDir C:\example\tor\TorExpertBundle\tor\TorHiddenServiceSSH
HiddenServicePort 22 127.0.0.1:22
```

Restart tor:

```bash
cd /c/example/tor/TorExpertBundle/tor && ./tor.exe -f torrc      # Git Bash (needs ./)
```
```bat
cd C:\example\tor\TorExpertBundle\tor && tor.exe -f torrc         :: cmd / PowerShell
```

Wait for `Bootstrapped 100% (done)`, then read the address:

```bash
cat /c/example/tor/TorExpertBundle/tor/TorHiddenServiceSSH/hostname   # Git Bash
```
```bat
type C:\example\tor\TorExpertBundle\tor\TorHiddenServiceSSH\hostname  :: cmd
```

`TorHiddenServiceSSH\` holds the service's private key — it is excluded by `.gitignore`; back it up outside the repo to keep the same address.

### 5.1 Start tor at boot (Windows service)

Started by hand, tor stops when you log out or reboot — and then nobody can SSH in. Run it as a service instead (starts at boot, no login needed, restarts on failure). **PowerShell (Admin)**, from the repo folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install-tor-service.ps1 -SshServiceDir TorHiddenServiceSSH
```

The script copies `tor.exe` from Tor Browser into `TorExpertBundle\tor\` (git-ignored), writes `torrc-service` with absolute paths, gives the `LOCAL SERVICE` account access to `Data\` and the onion folder, stops a hand-started tor, installs the `tor` service and waits for `Bootstrapped 100%`. The existing onion keys are reused, so the `.onion` address stays the same.

- `-SshServiceDir` = the folder that holds your SSH onion keys (default `TorHiddenService1`).
- ⚠️ Run it **at the PC**, not over SSH-through-this-tor: stopping the hand-started tor drops that session (reconnect after ~1 min if you do).
- After a Tor Browser update, run it again to refresh `tor.exe`.
- Manage: `Get-Service tor`, `Restart-Service tor` (after editing `torrc-service`), log in `TorExpertBundle\tor\log.txt`.
- Remove: `.\scripts\install-tor-service.ps1 -Uninstall`.
- Tor Browser keeps working alongside (its own tor on 9150).

### 5.2 Watchdog: restart tor when the onion is stuck

The service restarts tor when the process *crashes*, but not when tor keeps running and the onion is unreachable (stuck below 100%, clock skew, network blocking Tor…). The watchdog covers that. **PowerShell (Admin)**, once:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install-tor-watchdog.ps1 -SshServiceDir TorHiddenServiceSSH
```

- Scheduled task `Tor_Watchdog` runs `scripts\tor-watchdog.ps1` as SYSTEM every 5 minutes (and 3 min after boot).
- Each run checks: service running → SOCKS port listening → **connects to this PC's own .onion on port 22 through tor and expects an `SSH-` banner**.
- 2 failed runs in a row → `Restart-Service tor` (at most once per 15 min). Log: `TorExpertBundle\tor\watchdog.log`; last result: `watchdog-state.json` (both git-ignored).
- It also lets your account start/stop **only** the `tor` service, so `Restart-Service tor` works from a normal (non-admin) shell or an SSH session.
- Check by hand anytime (no restart, no admin needed): `powershell -ExecutionPolicy Bypass -File .\scripts\tor-watchdog.ps1 -CheckOnly`
- Remove: `.\scripts\install-tor-watchdog.ps1 -Uninstall`.
- Want a phone notification when it stays down? Have something read `watchdog-state.json` (e.g. a cron job that alerts when `last_ok` is older than 15 min).



## 6. Client — connect through Tor

**The client must be running tor too**: Tor Browser listens on **9150**, the Expert Bundle on **9050** — use whichever is running.

One-off from **Git Bash** (`connect` ships with Git for Windows):

```bash
ssh -i ~/.ssh/example-ssh-tor-ed25519 -o ProxyCommand="connect -S 127.0.0.1:9050 %h %p" user@xxxxxxxx.onion
```

Better: add to `~/.ssh/config` once, then just run `ssh mypc`:

```text
Host mypc
    HostName xxxxxxxx.onion
    User user
    IdentityFile ~/.ssh/example-ssh-tor-ed25519
    IdentitiesOnly yes
    ProxyCommand connect -S 127.0.0.1:9050 %h %p
```

**`connect` not found** (plain PowerShell / cmd using Windows' own `ssh.exe`) — use the full path of Git's `connect.exe` in `ProxyCommand`:

```text
    ProxyCommand "C:\Program Files\Git\mingw64\bin\connect.exe" -S 127.0.0.1:9050 %h %p
```

Or use `ncat` from [Nmap](https://nmap.org/download.html):

```text
    ProxyCommand ncat --proxy 127.0.0.1:9050 --proxy-type socks5 %h %p
```

**Linux / macOS:**

```text
    ProxyCommand nc -X 5 -x 127.0.0.1:9050 %h %p
```

## 7. Connecting from other devices

Same rules on every device: **run tor there**, **give each device its own key** (create it on that device, then add its `.pub` line to the server — §3.2), and point SSH at the local SOCKS port.

| Device | tor | SOCKS port | Proxy for SSH |
|---|---|---|---|
| Android — Termux | `pkg install tor` | 9050 | `torsocks ssh` or `nc -X 5 -x` |
| Android — Orbot | Orbot app | 9050 | Termux `ssh` + `nc`/`torsocks` |
| Android — Tor VPN (beta) | Tor VPN app (VPN mode) | — | none: plain `ssh user@xxx.onion` |
| Windows PC | Tor Browser / Expert Bundle | 9150 / 9050 | `connect` (Git Bash) / `ncat` |
| Linux | `apt install tor` (service) | 9050 | `torsocks ssh` or `nc -X 5 -x` |
| macOS | `brew install tor` | 9050 | `nc -X 5 -x` |

### 7.1 Android — Termux

Install Termux from **F-Droid** or GitHub releases (the Google Play build is outdated).

```bash
pkg update && pkg upgrade
pkg install openssh tor torsocks netcat-openbsd
```

Create a key on the phone and show the public key:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/example-phone-ed25519 -C "phone-tor-ssh"
cat ~/.ssh/example-phone-ed25519.pub
```

Send that **one line** to the PC (e.g. message it to yourself) and add it on the server with §3.2 — `Add-Content` appends a new line, so existing keys keep working.

**Alternative — reuse the PC's key instead of creating one on the phone.** The `.pub` alone is not enough: the phone needs the **private key** (`example-ssh-tor-ed25519`), and the server already trusts it, so nothing changes on the server.
Downsides: the same key now lives on two devices, so you can't revoke just the phone (§3.8), and a lost phone means replacing the key everywhere — set a passphrase first (`ssh-keygen -p -f ~/.ssh/example-ssh-tor-ed25519`).

Copy it over USB / wireless debugging with `adb` (**Git Bash** on the PC):

```bash
adb push ~/.ssh/example-ssh-tor-ed25519 /sdcard/Download/
```

Then in **Termux** (allow storage access when asked), move it into Termux's private folder and delete the copy from shared storage:

```bash
termux-setup-storage
mkdir -p ~/.ssh && mv ~/storage/downloads/example-ssh-tor-ed25519 ~/.ssh/
chmod 600 ~/.ssh/example-ssh-tor-ed25519
ssh-keygen -y -f ~/.ssh/example-ssh-tor-ed25519 > ~/.ssh/example-ssh-tor-ed25519.pub   # rebuild .pub (optional)
ls ~/storage/downloads/ | grep example-ssh || echo "shared copy gone"
```

Use `~/.ssh/example-ssh-tor-ed25519` instead of `example-phone-ed25519` in the commands below. Avoid sending a private key through chat apps or cloud drives.

Start tor in the background and wait until it's ready:

```bash
tor > ~/tor.log 2>&1 &
tail -f ~/tor.log          # wait for "Bootstrapped 100% (done)", then Ctrl+C
```

Check that tor is really running before you connect — otherwise you get `Connection refused` (§9):

```bash
pgrep -a tor                         # must list a tor process
nc -z 127.0.0.1 9050 && echo OK      # must print OK
```

Connect — either with torsocks:

```bash
torsocks ssh -i ~/.ssh/example-phone-ed25519 user@xxxxxxxx.onion
```

or permanently via `~/.ssh/config` (then just `ssh mypc`):

```bash
mkdir -p ~/.ssh && cat >> ~/.ssh/config <<'EOF'
Host mypc
    HostName xxxxxxxx.onion
    User user
    IdentityFile ~/.ssh/example-phone-ed25519
    IdentitiesOnly yes
    ProxyCommand nc -X 5 -x 127.0.0.1:9050 %h %p
EOF
chmod 600 ~/.ssh/config
ssh mypc
```

Tips:
- Stop tor when you're done: `pkill tor`.
- Android may kill Termux in the background — run `termux-wake-lock` while connected, or allow Termux to ignore battery optimisation.
- The first connection takes 10–30 s while Tor builds the circuit to the onion service; that's normal.
- Missing keys on the phone keyboard? Long-press the screen → *More* → *Toggle extra keys* for Ctrl/Esc/Tab/arrows.

### 7.2 Android — Orbot instead of tor in Termux

If you already use [Orbot](https://orbot.app/) (Tor Project's Android app): start Orbot, then in Termux use the same `ssh` / `~/.ssh/config` as §7.1 **without** running `tor` yourself — Orbot's SOCKS port is also `127.0.0.1:9050` (check Orbot → Settings if you changed it).
Don't route Termux through Orbot's VPN mode *and* a SOCKS proxy at the same time; pick one (SOCKS is simpler).

### 7.3 Android — Tor VPN (beta) instead of Orbot

[Tor VPN](https://download.torproject.org/tor-vpn-for-android/) is the Tor Project's own Android VPN app (built on Arti; Google Play, F-Droid or APK). It routes **selected apps** through Tor, each on its own circuit, and the Tor Project lists *access to onion services* among its uses.

1. Install Tor VPN and connect.
2. In its **Apps** screen, turn routing **on for Termux**.
3. In Termux, connect **without any proxy** — the VPN handles both the `.onion` lookup and the traffic, so you don't need `tor`, `torsocks` or `ProxyCommand`:

```bash
ssh -i ~/.ssh/example-phone-ed25519 user@xxxxxxxx.onion
```

`~/.ssh/config` for this case:

```text
Host mypc-vpn
    HostName xxxxxxxx.onion
    User user
    IdentityFile ~/.ssh/example-phone-ed25519
    IdentitiesOnly yes
```

- ⚠️ The Tor Project marks Tor VPN as **beta: "Do not rely on it for anything other than testing. It may leak information"** ([support page](https://support.torproject.org/tor-vpn/)). Your SSH session is still end-to-end encrypted by SSH, but for anything important prefer tor in Termux (§7.1) or Orbot (§7.2).
- Don't combine it with Orbot's VPN or with `ProxyCommand nc -x 127.0.0.1:9050` — Tor VPN has no local SOCKS port, so a SOCKS proxy line fails with *connection refused*.
- If `ssh` says it can't resolve the `.onion` name, check that Termux is enabled in Tor VPN's Apps list and that the VPN shows *Connected*; fall back to §7.1 if it still fails.

### 7.4 Another Windows PC

1. Run tor: open **Tor Browser** (SOCKS **9150**, keep the window open) or the Expert Bundle (`tor.exe`, SOCKS **9050**).
2. Create that PC's own key (§3.1) and add its `.pub` to the server (§3.2).
3. Connect from **Git Bash** — set the port to match step 1:

```bash
ssh -i ~/.ssh/example-ssh-tor-ed25519 -o ProxyCommand="connect -S 127.0.0.1:9150 %h %p" user@xxxxxxxx.onion
```

From **PowerShell / cmd** without Git Bash, use the `~/.ssh/config` from §6 with the full `connect.exe` path or `ncat` — the file is `C:\Users\<you>\.ssh\config`.

### 7.5 Linux

```bash
sudo apt install tor torsocks openssh-client netcat-openbsd    # Debian/Ubuntu
sudo systemctl enable --now tor                                 # tor runs as a service on 9050
torsocks ssh -i ~/.ssh/example-ssh-tor-ed25519 user@xxxxxxxx.onion
```

Or `ProxyCommand nc -X 5 -x 127.0.0.1:9050 %h %p` in `~/.ssh/config` (§6).

### 7.6 macOS

```bash
brew install tor
brew services start tor                 # SOCKS on 9050
ssh -o ProxyCommand="nc -X 5 -x 127.0.0.1:9050 %h %p" -i ~/.ssh/example-ssh-tor-ed25519 user@xxxxxxxx.onion
```

macOS's built-in `nc` supports `-X 5 -x`, so nothing else is needed.

### 7.7 iPhone / iPad

There's no Termux equivalent; SSH apps need their own Tor support or a SOCKS proxy (e.g. Onion Browser doesn't provide one to other apps). Not covered here — use Android or a computer.

### 7.8 Revoking a device

Delete that device's line from `C:\ProgramData\ssh\administrators_authorized_keys` (**PowerShell (Admin)**: `notepad C:\ProgramData\ssh\administrators_authorized_keys`), save, then `Restart-Service sshd`. This is why each device should have its own key — the comment at the end of each line (`phone-tor-ssh`, `tor-ssh`, …) tells you which is which.

## 8. Hardening (optional, recommended)

- Enable [Client Authorization](https://community.torproject.org/onion-services/advanced/client-auth/) for the SSH service: without the client key nobody can even reach the service, even if the .onion address leaks — a second layer on top of SSH keys.
- Keep `PasswordAuthentication no`.
- One key per client device, so one can be revoked by deleting its line in `administrators_authorized_keys`.

## 9. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `Cannot find any service with service name 'sshd'` | OpenSSH Server not really installed → §1, use `winget install Microsoft.OpenSSH.Preview` |
| `icacls ... The system cannot find the file specified` | Typo in the file name — it must end in `_keys` (`ls C:\ProgramData\ssh\`) |
| `torsocks[...]: socks5 libc connect: Connection refused` then `ssh: connect to host xxx.onion port 22: Connection refused` | **tor isn't running on the client** — nothing listens on `127.0.0.1:9050`, so the connection never left the device. Termux: `tor > ~/tor.log 2>&1 &`, wait for `Bootstrapped 100%`, retry. Orbot: press Connect. Tor VPN: don't use `torsocks` / `ProxyCommand` at all (§7.3) |
| Same `Connection refused` with `connect` / `nc` in `ProxyCommand` | Same cause, or wrong port: Tor Browser = 9150, Expert Bundle / Termux / Orbot = 9050 |
| `Too many authentication failures` | ssh offered too many keys — set `IdentityFile` + `IdentitiesOnly yes` in `~/.ssh/config` (§3.4) |
| `UNPROTECTED PRIVATE KEY FILE` / `bad permissions` on the client | Fix the private key's permissions (§3.6) |
| `Warning: Identity file ... not accessible` | Wrong key file name after `-i` / `IdentityFile` → `ls ~/.ssh/` |
| `Permission denied (publickey,keyboard-interactive)` after `Offering public key` | sshd doesn't find your key: missing `Match Group administrators` block (§2), key not in the file, or wrong `icacls` permissions (§3.2) |
| Same, and you want to compare keys | **PowerShell (Admin)**: `ssh-keygen -lf C:\ProgramData\ssh\administrators_authorized_keys` vs **Git Bash**: `ssh-keygen -lf ~/.ssh/example-ssh-tor-ed25519.pub` — the `SHA256:` values must match |
| `Permission denied` when reading `C:\ProgramData\ssh\...` from Git Bash | Expected after `icacls` — use PowerShell (Admin) |
| `bash: ./tor.exe` / `tor.exe: command not found` | In Git Bash add `./` and run from the folder that contains `tor.exe` |
| `bash: $'\302\226...': command not found` | Invisible character from copy-paste → retype the command |
| Connection times out over .onion | tor not at 100% on either side, wrong SOCKS port (9050 vs 9150), or wrong `hostname` |
| More detail | `ssh -v mypc`; server log: **PowerShell (Admin)** `Get-Content C:\ProgramData\ssh\logs\sshd.log -Tail 30` (enable with `SyslogFacility LOCAL0` + `LogLevel DEBUG` above `Match`) |
