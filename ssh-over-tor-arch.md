# SSH over Tor (Onion Service) on Arch Linux

The Arch Linux version of [`ssh-over-tor-windows.md`](./ssh-over-tor-windows.md) (Windows): reach an Arch machine's SSH server from anywhere through a Tor Onion Service — no port forwarding, no public IP, **no inbound firewall port**.

> Back to the main guide: [`readme.md`](./readme.md) · Windows server version: [`ssh-over-tor-windows.md`](./ssh-over-tor-windows.md)
> References: [ArchWiki — Tor](https://wiki.archlinux.org/title/Tor), [ArchWiki — OpenSSH](https://wiki.archlinux.org/title/OpenSSH), [Tor — Set up Your Onion Service](https://community.torproject.org/onion-services/setup/)

```
client ── tor (9050) ══ Tor network ══ tor on Arch server ── 127.0.0.1:22 ── sshd
```

All commands run in a normal terminal; lines starting with `sudo` need root. Replace `user` with your Linux user name and `xxxxxxxx.onion` with your address (§4).

---

## 1. Server — install packages

```bash
sudo pacman -Syu
sudo pacman -S openssh tor
```

- `openssh` provides `sshd` (service `sshd.service`), `tor` provides `tor.service`.
- Arch's tor service runs as the `tor` user with data in `/var/lib/tor/`.

## 2. Server — SSH keys

Keys work the same as on Windows — see [`ssh-over-tor-windows.md` §3.0](./ssh-over-tor-windows.md#30-how-keys-work-read-once) for the concepts (private vs public key, passphrase, one key per device).

### 2.1 Create a key on each client

On the device you connect **from** (Arch, other Linux, macOS, Git Bash, Termux):

```bash
ssh-keygen -t ed25519 -f ~/.ssh/example-ssh-tor-ed25519 -C "laptop-tor-ssh"
cat ~/.ssh/example-ssh-tor-ed25519.pub        # one line: ssh-ed25519 AAAA... laptop-tor-ssh
```

Set a passphrase when asked. Add or change it later with `ssh-keygen -p -f ~/.ssh/example-ssh-tor-ed25519`.

### 2.2 Authorize it on the Arch server

On Linux, every user (including ones in `wheel`) uses their own `~/.ssh/authorized_keys` — there's no `administrators_authorized_keys` like on Windows.

```bash
mkdir -p ~/.ssh
echo "ssh-ed25519 AAAA...your key... laptop-tor-ssh" >> ~/.ssh/authorized_keys
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```

- `>>` **appends** a line; `>` would overwrite the file and remove every other key.
- Permissions matter: with `StrictModes yes` (default) sshd ignores `authorized_keys` if `~/.ssh` or the file is writable by others. Your home directory must not be group/world-writable either.
- If the client can already reach the server over LAN, `ssh-copy-id -i ~/.ssh/example-ssh-tor-ed25519.pub user@<lan-ip>` does all of the above for you.
- Check fingerprints match: `ssh-keygen -lf ~/.ssh/authorized_keys` (server) vs `ssh-keygen -lf ~/.ssh/example-ssh-tor-ed25519.pub` (client).

### 2.3 Log in as admin or as a normal user

On Linux "admin" means a user in the `wheel` group who can use `sudo` — not logging in as `root`.

| | Admin (`wheel` + sudo) | Normal user | `root` |
|---|---|---|---|
| Key file | `~/.ssh/authorized_keys` of that user | `~/.ssh/authorized_keys` of that user | `/root/.ssh/authorized_keys` |
| Rights | Normal; `sudo <cmd>` for admin tasks | Normal only | Everything, no confirmation |
| Recommended | ✅ for maintenance | ✅ for daily use | ❌ keep `PermitRootLogin no` |

Create a normal user for SSH and give it its own key:

```bash
sudo useradd -m -s /bin/bash sshuser
sudo install -d -m 700 -o sshuser -g sshuser /home/sshuser/.ssh
echo "ssh-ed25519 AAAA...client key... laptop-user" | sudo tee -a /home/sshuser/.ssh/authorized_keys > /dev/null
sudo chown sshuser:sshuser /home/sshuser/.ssh/authorized_keys
sudo chmod 600 /home/sshuser/.ssh/authorized_keys
```

Make an existing user an admin (needs `sudo` installed and `%wheel ALL=(ALL:ALL) ALL` enabled via `sudo EDITOR=nano visudo`):

```bash
sudo usermod -aG wheel adminaccount
```

Client `~/.ssh/config` with one entry per account (same .onion, different key):

```text
Host mypc-admin
    HostName xxxxxxxx.onion
    User adminaccount
    IdentityFile ~/.ssh/example-admin-ed25519
    IdentitiesOnly yes
    ProxyCommand nc -X 5 -x 127.0.0.1:9050 %h %p

Host mypc-user
    HostName xxxxxxxx.onion
    User sshuser
    IdentityFile ~/.ssh/example-user-ed25519
    IdentitiesOnly yes
    ProxyCommand nc -X 5 -x 127.0.0.1:9050 %h %p
```

- In an admin session use `sudo` for system tasks; check with `id` (`wheel` listed) and `sudo -v`.
- A normal user can't `sudo` — log in as `mypc-admin` when you need it.
- Limit who may log in: add `AllowUsers adminaccount sshuser` to the drop-in file in §3.
- Root over SSH only if you really must: `PermitRootLogin prohibit-password` (keys only) and a key in `/root/.ssh/authorized_keys`. Prefer `sudo`.

## 3. Server — configure sshd (localhost only, keys only)

Arch's `/etc/ssh/sshd_config` includes `/etc/ssh/sshd_config.d/*.conf` at the top, so put your settings in a drop-in file instead of editing the main one (survives package updates):

```bash
sudo tee /etc/ssh/sshd_config.d/10-tor-onion.conf > /dev/null <<'EOF'
ListenAddress 127.0.0.1
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
EOF
```

- Check that the include line exists: `grep -n '^Include' /etc/ssh/sshd_config` → `Include /etc/ssh/sshd_config.d/*.conf`. If it's missing (very old config / `.pacnew` not merged), add the lines above to the **top** of `sshd_config` instead.
- For the first value set, sshd uses the first one it reads — that's why drop-ins are included at the top.
- Test the key **before** relying on `PasswordAuthentication no` (§3.1), or keep a local console session open.

Validate and start:

```bash
sudo sshd -t                               # no output = config OK
sudo systemctl enable --now sshd
sudo systemctl restart sshd                # after any config change
ss -tlnp | grep ':22 '                     # must show 127.0.0.1:22 only
```

`0.0.0.0:22` or `[::]:22` in the `ss` output means sshd is still listening on all interfaces — check the drop-in file and restart.

### 3.1 Test locally

```bash
ssh -i ~/.ssh/example-ssh-tor-ed25519 user@127.0.0.1
```

`127.0.0.1` works **only on the server itself**. From another device use the `.onion` address (§4) through that device's tor (§6):

```bash
ssh -i ~/.ssh/example-ssh-tor-ed25519 -o ProxyCommand="nc -X 5 -x 127.0.0.1:9050 %h %p" user@xxxxxxxx.onion
# or
torsocks ssh -i ~/.ssh/example-ssh-tor-ed25519 user@xxxxxxxx.onion
```

The `127.0.0.1:9050` in `ProxyCommand` is the client's own tor SOCKS port — it stays as is.

(Run on the server with a key that's in `authorized_keys`, or temporarily from a client over the LAN before setting `ListenAddress`.)

## 4. Server — publish the Onion Service

Edit `/etc/tor/torrc`:

```bash
sudoedit /etc/tor/torrc
```

Add:

```text
HiddenServiceDir /var/lib/tor/ssh/
HiddenServicePort 22 127.0.0.1:22
```

- `HiddenServiceDir` must be owned by the user tor runs as (`tor`) with mode `700`. Under `/var/lib/tor/` tor creates it correctly by itself.
- Leave `SocksPort` at its default (9050) if you also want to use this machine as a Tor client.

Start tor and read the address:

```bash
sudo systemctl enable --now tor
sudo systemctl restart tor                 # after editing torrc
journalctl -u tor -f                       # wait for "Bootstrapped 100% (done)", then Ctrl+C
sudo cat /var/lib/tor/ssh/hostname         # -> xxxxxxxx.onion
```

- `hostname` is safe to share; the other files in `/var/lib/tor/ssh/` are the service's private keys — back them up (`sudo cp -a /var/lib/tor/ssh ~/onion-ssh-backup && sudo chown -R $USER: ~/onion-ssh-backup`, then store it encrypted) to keep the same address after a reinstall. Never commit them.
- tor fails to start? `journalctl -u tor -e` — usually a typo in `torrc` or wrong ownership/permissions of `HiddenServiceDir`. Check the config with `sudo -u tor tor --verify-config -f /etc/tor/torrc`.

## 5. Server — firewall: open nothing inbound

tor makes **outbound** connections only and hands traffic to `127.0.0.1:22`, so no inbound port is needed. Arch has no firewall enabled by default; if you use one, keep SSH closed.

**nftables** (`sudo pacman -S nftables`, minimal inbound-deny ruleset):

```bash
sudo tee /etc/nftables.conf > /dev/null <<'EOF'
#!/usr/bin/nft -f
flush ruleset
table inet filter {
  chain input {
    type filter hook input priority filter; policy drop;
    ct state established,related accept
    iif "lo" accept
    ct state invalid drop
    meta l4proto { icmp, ipv6-icmp } accept
  }
  chain forward { type filter hook forward priority filter; policy drop; }
  chain output  { type filter hook output priority filter; policy accept; }
}
EOF
sudo systemctl enable --now nftables
sudo nft list ruleset
```

`iif "lo" accept` keeps tor ↔ sshd on loopback working; nothing else comes in. ⚠️ If you manage the box over LAN SSH right now, this cuts that session — do it from the local console or via the onion address.

**ufw** (`sudo pacman -S ufw`) instead:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw enable
sudo ufw status verbose                    # no rule for 22
sudo systemctl enable ufw
```

Don't open 9050 either — SOCKS is local only.

## 6. Client on Arch Linux

```bash
sudo pacman -S tor openssh openbsd-netcat torsocks
sudo systemctl enable --now tor            # SOCKS on 127.0.0.1:9050
```

One-off:

```bash
torsocks ssh -i ~/.ssh/example-ssh-tor-ed25519 user@xxxxxxxx.onion
```

Permanent — `~/.ssh/config`, then just `ssh mypc`:

```text
Host mypc
    HostName xxxxxxxx.onion
    User user
    IdentityFile ~/.ssh/example-ssh-tor-ed25519
    IdentitiesOnly yes
    AddKeysToAgent yes
    ProxyCommand nc -X 5 -x 127.0.0.1:9050 %h %p
```

```bash
chmod 600 ~/.ssh/config
ssh mypc
```

- `nc -X 5 -x` needs **`openbsd-netcat`**. Arch's other netcat (`gnu-netcat`) doesn't support `-X`; the two packages conflict, pacman will ask to replace.
- Instead of `nc`: `ProxyCommand ncat --proxy 127.0.0.1:9050 --proxy-type socks5 %h %p` (package `nmap`).
- Using Tor Browser instead of the tor service? Its SOCKS port is **9150**.
- First connection takes 10–30 s while the onion circuit is built.
- `ssh-agent`: `eval "$(ssh-agent -s)"; ssh-add ~/.ssh/example-ssh-tor-ed25519`, or enable the user unit `systemctl --user enable --now ssh-agent` and set `SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent.socket"` in your shell profile.

Clients on other systems (Windows, Android Termux / Orbot / Tor VPN, macOS): see [`ssh-over-tor-windows.md` §6–§7](./ssh-over-tor-windows.md#7-connecting-from-other-devices) — only the server side differs.

## 7. Hardening (optional, recommended)

- **Client Authorization** — only clients holding a key can even reach the onion service ([Tor docs](https://community.torproject.org/onion-services/advanced/client-auth/)):
  - Server: put `<name>.auth` files containing `descriptor:x25519:<base32 public key>` in `/var/lib/tor/ssh/authorized_clients/` (owned by `tor`, mode 700), then `sudo systemctl restart tor`.
  - Client: add `ClientOnionAuthDir /var/lib/tor/onion_auth` to the client's `torrc` and put `<name>.auth_private` (`<56-char-onion-addr-without-.onion>:descriptor:x25519:<base32 private key>`) there.
- `AllowUsers user` in the drop-in file limits who can log in.
- Keep the system updated (`sudo pacman -Syu`) — tor and openssh get security fixes often.
- `sshguard` or `fail2ban` add little here: attackers can't reach port 22 directly, and with Client Authorization they can't reach the onion service either.

## 8. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `Permission denied (publickey)` | Key not in `~/.ssh/authorized_keys` of **that** user, or bad permissions (`chmod 700 ~/.ssh; chmod 600 ~/.ssh/authorized_keys`). Server log: `journalctl -u sshd -e` (look for `Authentication refused: bad ownership or modes`) |
| `Too many authentication failures` | ssh offered many keys — add `IdentitiesOnly yes` and `IdentityFile` in `~/.ssh/config` |
| `UNPROTECTED PRIVATE KEY FILE` | `chmod 600 ~/.ssh/example-ssh-tor-ed25519` on the client |
| `ss` shows `0.0.0.0:22` | Drop-in not loaded — check the `Include` line (§3), `sudo sshd -T \| grep listenaddress`, restart sshd |
| tor service fails | `journalctl -u tor -e`; `sudo -u tor tor --verify-config -f /etc/tor/torrc`; `HiddenServiceDir` permissions (`sudo ls -ld /var/lib/tor/ssh` → `drwx------ tor tor`) |
| No `hostname` file | tor hasn't started successfully since editing `torrc` — restart and check the journal |
| `nc: invalid option -- 'X'` | `gnu-netcat` installed — `sudo pacman -S openbsd-netcat` |
| `torsocks[...]: socks5 libc connect: Connection refused` |  tor not running on the client — `sudo systemctl start tor` (or start Tor Browser and use port 9150), check `ss -tln \| grep 9050` |
| `connect to 127.0.0.1 port 9050: Connection refused` | tor not running on the client (`systemctl status tor`), or you use Tor Browser → port 9150 |
| Connection times out | Server tor not at 100%, wrong `.onion` address, or server offline |
| `REMOTE HOST IDENTIFICATION HAS CHANGED` | Server reinstalled with new host keys — verify, then `ssh-keygen -R xxxxxxxx.onion` |
| More detail | `ssh -v mypc` on the client, `journalctl -u sshd -f` on the server |
