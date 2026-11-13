# SSH over Tor (Onion Service) on Windows

Reach this PC's SSH server from anywhere through a Tor Onion Service — no router port forwarding, no public IP, and **no inbound firewall port**.

> Back to the main guide: [`readme.md`](./readme.md) (installing and verifying tor, `torrc` basics)
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

Leave `PasswordAuthentication no` for after step 3 if you're not sure the key works yet — otherwise you can lock yourself out.

## 3. Create an SSH key and authorize it

### 3.1 On the client — create the key pair

**Git Bash / PowerShell / Linux / macOS** (same command everywhere):

```bash
ssh-keygen -t ed25519 -f ~/.ssh/example-ssh-tor-ed25519 -C "tor-ssh"
```

- Set a passphrase.
- `example-ssh-tor-ed25519` = **private key** — stays on the client, never share or commit it.
- `example-ssh-tor-ed25519.pub` = public key — this one goes to the server.
- In **PowerShell** write `$HOME\.ssh\...` if `~` isn't expanded by the program you use.

Show the public key (one line starting with `ssh-ed25519 AAAA...`):

```bash
cat ~/.ssh/example-ssh-tor-ed25519.pub          # Git Bash
```
```powershell
Get-Content $HOME\.ssh\example-ssh-tor-ed25519.pub   # PowerShell
```

### 3.2 On the server — add it to `administrators_authorized_keys`

If your Windows account is an **Administrator** (check: `net localgroup Administrators`), keys go into the ProgramData file, not your profile.
**PowerShell (Admin)** — the file is admin-only, so Git Bash can't write it:

```powershell
Add-Content C:\ProgramData\ssh\administrators_authorized_keys "ssh-ed25519 AAAA...your key... tor-ssh"
icacls C:\ProgramData\ssh\administrators_authorized_keys /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F"
Restart-Service sshd
```

- The key must be on **one line**.
- Check the file name: it's `administrators_authorized_key`**`s`** — `icacls` saying `The system cannot find the file specified` usually means a typo.
- `icacls` must print `Successfully processed 1 files`; sshd ignores the file if anyone else can write to it.
- **Non-admin account:** put the key in `C:\Users\<you>\.ssh\authorized_keys` instead (no `icacls` needed).

### 3.3 Test locally (before Tor)

**Git Bash / PowerShell** on the server:

```bash
ssh -i ~/.ssh/example-ssh-tor-ed25519 user@127.0.0.1
```

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
Downsides: the same key now lives on two devices, so you can't revoke just the phone (§7.8), and a lost phone means replacing the key everywhere — set a passphrase first (`ssh-keygen -p -f ~/.ssh/example-ssh-tor-ed25519`).

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
| `Warning: Identity file ... not accessible` | Wrong key file name after `-i` / `IdentityFile` → `ls ~/.ssh/` |
| `Permission denied (publickey,keyboard-interactive)` after `Offering public key` | sshd doesn't find your key: missing `Match Group administrators` block (§2), key not in the file, or wrong `icacls` permissions (§3.2) |
| Same, and you want to compare keys | **PowerShell (Admin)**: `ssh-keygen -lf C:\ProgramData\ssh\administrators_authorized_keys` vs **Git Bash**: `ssh-keygen -lf ~/.ssh/example-ssh-tor-ed25519.pub` — the `SHA256:` values must match |
| `Permission denied` when reading `C:\ProgramData\ssh\...` from Git Bash | Expected after `icacls` — use PowerShell (Admin) |
| `bash: ./tor.exe` / `tor.exe: command not found` | In Git Bash add `./` and run from the folder that contains `tor.exe` |
| `bash: $'\302\226...': command not found` | Invisible character from copy-paste → retype the command |
| Connection times out over .onion | tor not at 100% on either side, wrong SOCKS port (9050 vs 9150), or wrong `hostname` |
| More detail | `ssh -v mypc`; server log: **PowerShell (Admin)** `Get-Content C:\ProgramData\ssh\logs\sshd.log -Tail 30` (enable with `SyslogFacility LOCAL0` + `LogLevel DEBUG` above `Match`) |
