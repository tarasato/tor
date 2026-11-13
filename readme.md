# Tor — Running the Tor Expert Bundle + Onion Services on Windows

> Short command notes live in [`setup.md`](./setup.md). SSH over Tor: [`ssh-over-tor-windows.md`](./ssh-over-tor-windows.md) (Windows) · [`ssh-over-tor-arch.md`](./ssh-over-tor-arch.md) (Arch Linux). This guide follows the official Tor Project documentation (links at the end of each section).
> Checked against the Tor website on 2026-11-13 — latest version at the time: Tor Expert Bundle **16.0.1 (tor 0.4.9.16)**

---

## ⚠️ Never commit Onion Service keys

Every file in a `HiddenServiceDir` except `hostname` is a service key. From the Tor docs: *"it is imperative that these are kept private.
If your keys leak, other people can impersonate your Onion Service"* ([Set up Your Onion Service – Step 4](https://community.torproject.org/onion-services/setup/))

- This repo's `.gitignore` already excludes `TorHiddenService*/`, `Data/`, logs, binaries and downloads — only `torrc`, the `.bat` scripts and docs are tracked.
- Back up `hs_ed25519_secret_key` somewhere safe outside the repo if you want to keep the same .onion address (if it's lost, tor generates a new address).
- The keys that appear in this repo's history are examples only — never use them for a real service.

---

## 1. Download the Tor Expert Bundle

- Page: <https://www.torproject.org/download/tor/> → **tor expert bundle** → **Windows (x86_64) → Download** and **Sig**
- The Expert Bundle is `tor.exe` + pluggable transports + geoip, with no browser (the site lists it for developers and advanced users).
- Extract it into a folder such as `C:\example\tor\TorExpertBundle\`

## 2. Verify the download's signature (every time, before use)

You need GnuPG first — on Windows use [Gpg4win](https://gpg4win.org/) (or the `gpg` that ships with Git Bash).
Source: [How to verify Tor Browser's signature](https://support.torproject.org/tbb/how-to-verify-signature/)

### 2.1 Fetch the Tor Browser Developers key (`0xEF6E286DDA85EA2A4BA7DE684E2C6E8793298290`)

```bash
cd ~
gpg --auto-key-locate nodefault,wkd --locate-keys torbrowser@torproject.org
```

If that fails, use one of the fallbacks:

```bash
gpg --keyserver keys.openpgp.org --recv-keys EF6E286DDA85EA2A4BA7DE684E2C6E8793298290
# or
curl -s https://openpgpkey.torproject.org/.well-known/openpgpkey/torproject.org/hu/kounek7zrdx745qydx6p59t9mqjpuhdf | gpg --import -
```

The output must show `"Tor Browser Developers (signing key) <torbrowser@torproject.org>"` and the fingerprint `EF6E286DDA85EA2A4BA7DE684E2C6E8793298290`.

### 2.2 Export it to a keyring file

```bash
gpg --output ./tor.keyring --export 0xEF6E286DDA85EA2A4BA7DE684E2C6E8793298290
ls -l ./tor.keyring        # the file must exist and not be 0 bytes
```

### 2.3 Verify the file

In **Git Bash** (use `/`, and prefix the keyring with `./`):

```bash
gpgv --keyring ./tor.keyring ~/Downloads/<file>.asc ~/Downloads/<file>
```

In **cmd.exe** (as in the Tor website's example, with `\`):

```bat
gpgv --keyring .\tor.keyring Downloads\<file>.asc Downloads\<file>
```

You must see `gpgv: Good signature from "Tor Browser Developers (signing key) <torbrowser@torproject.org>"`

| Symptom | Cause / fix |
|---|---|
| `no valid OpenPGP data found` on `gpg --import xxx.asc` | The `.asc` is a **signature**, not a key — use `gpgv` / `gpg --verify` on it |
| `No such file or directory` | Wrong file name, or `\` used in Git Bash (bash strips `\`) |
| `keyblock resource '.../.gnupg/...tor.keyring'` | Keyring name given without `./` → gpgv looks in `~/.gnupg` |
| `command not found` with odd characters (`$'\302\226...'`) | An invisible character came along with a copy-paste → retype the command |
| Key expired / missing subkey | `gpg --refresh-keys EF6E286DDA85EA2A4BA7DE684E2C6E8793298290`, then export `tor.keyring` again |

## 3. Configure `torrc`

Create a file named `torrc` (no `.txt` — watch out for Notepad adding it) in the same folder as `tor.exe`.

```text
SocksPort 9050

# Onion Service 1: website (visitors use port 80 → forwarded to the local web server on 8080)
HiddenServiceDir C:\example\tor\TorExpertBundle\tor\TorHiddenService1
HiddenServicePort 80 127.0.0.1:8080

# Onion Service 2: Minecraft
HiddenServiceDir C:\example\tor\TorExpertBundle\tor\TorHiddenService2
HiddenServicePort 25565 127.0.0.1:25565

DataDirectory C:\example\tor\TorExpertBundle\Data

Log notice stdout
Log notice file C:\example\tor\TorExpertBundle\tor\log.txt
```

What it means (from [Set up Your Onion Service](https://community.torproject.org/onion-services/setup/)):
- `HiddenServiceDir` = the folder holding the service's keys and `hostname` — tor must be able to read/write it, and **tor creates it if it doesn't exist**.
- `HiddenServicePort <virtual port> <local target>` = traffic arriving on the .onion's virtual port is forwarded to this local target.
- Several services from one tor: add another `HiddenServiceDir` — each `HiddenServicePort` that follows belongs to the most recent dir.
- Several ports on one service: add multiple `HiddenServicePort` lines under the same dir.
- The default is **v3** (56-character address) — v2 has been unsupported since 0.4.6.1-alpha (2021), so `HiddenServiceVersion 3` is optional.

Differences from the older `setup.md`:
- The old paths were `E:\Tor\TorExpertBundle\...`, but the repo lives at `C:\example\tor\` → adjust to wherever you actually put it.
- `#` comments moved onto their own lines so they don't sit next to path values.

## 4. Start tor

```bat
cd C:\example\tor\TorExpertBundle\tor
tor.exe -f torrc
```

In Git Bash / MSYS2 you need `./` in front (bash doesn't look for programs in the current folder):

```bash
cd /c/example/tor/TorExpertBundle/tor
./tor.exe -f torrc
```

(or double-click `StartTor.bat`)
- If you run it from the Tor Browser folder (`Tor Browser/Browser/TorBrowser/Tor`), there's no `torrc` next to `tor.exe` — point `-f` at our torrc with a full path.
- Tor Browser runs its own tor on port 9150 · this torrc uses 9050 and a separate `DataDirectory`, so both can run at once. Wait for `Bootstrapped 100% (done): Done` and **leave that window open**.

If tor doesn't start, read the log — it's usually a typo in `torrc` or a wrong path / folder permission (Tor docs, Step 3).

## 5. Check that it works

```bat
:: Is the SOCKS port open? (CheckPort.bat)
netstat -ano | findstr :9050

:: Is that PID really tor.exe?
tasklist /FI "PID eq <PID>"

:: Can traffic go out through Tor? — must show "Congratulations. This browser is configured to use Tor."
curl --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/
```

> A plain `curl https://check.torproject.org/` (as in `setup.md`) **does not go through Tor** and will always report that Tor isn't in use —
> add `--socks5-hostname 127.0.0.1:9050` (this also makes Tor resolve DNS, so lookups don't leak to the machine's resolver).

## 6. Get the .onion address and test it

```bat
type C:\example\tor\TorExpertBundle\tor\TorHiddenService1\hostname
```

- `hostname` = the .onion address (safe to share).
- The other files (`hs_ed25519_secret_key`, `hs_ed25519_public_key`) are keys — **don't share them, don't commit them** (see ⚠️ above), and back them up if you want to keep the address.
- Test: start a web server on `127.0.0.1:8080` first, then open `http://<hostname>` in Tor Browser,
  or from the same machine: `curl --socks5-hostname 127.0.0.1:9050 http://<hostname>/`

## 7. SSH remote access over Tor

➡️ **Full step-by-step guide: [`ssh-over-tor-windows.md`](./ssh-over-tor-windows.md)** — installing OpenSSH Server, `sshd_config`, keys, firewall, the onion service for port 22, client config, and PowerShell / cmd alternatives where Git Bash can't be used.

➡️ **Arch Linux server/client: [`ssh-over-tor-arch.md`](./ssh-over-tor-arch.md)** — pacman, systemd, `/etc/tor/torrc`, sshd drop-in config, nftables/ufw.

## 8. Security (from the Tor docs)

- Bind local services to `127.0.0.1` only (not `0.0.0.0`), otherwise people on the LAN/internet can reach them directly without Tor.
- An Onion Service like this is **reachable by anyone who knows the address** — to restrict access use
  [Client Authorization](https://community.torproject.org/onion-services/advanced/client-auth/): create `<HiddenServiceDir>\authorized_clients\`,
  add a `name.auth` file with one line `descriptor:x25519:<base32 public key>`, then restart tor (delete the file to revoke; takes effect after a restart).
- Configure the web server not to reveal anything about the machine (version headers, error pages, IP) — Tor suggests OnionScan to check.
- Minecraft over .onion: players must route the game through a Tor SOCKS proxy themselves (e.g. a client-side proxy tool) — the game doesn't understand .onion directly.

## 9. Network debugging (Windows)

```bat
netsh trace start capture=yes tracefile=c:\temp\nettrace.etl
:: ... do what you want to capture ...
netsh trace stop
```

Run cmd as Administrator · create `c:\temp` first if it doesn't exist (`mkdir c:\temp`) · open the `.etl` with Microsoft Network Monitor / Message Analyzer, or convert it to pcapng with `etl2pcapng`.

---

## References

- Tor Expert Bundle download — <https://www.torproject.org/download/tor/>
- How to verify Tor Browser's signature — <https://support.torproject.org/tbb/how-to-verify-signature/>
- Set up Your Onion Service — <https://community.torproject.org/onion-services/setup/>
- Onion Services: Client Authorization — <https://community.torproject.org/onion-services/advanced/client-auth/>
- SSH over Tor — [`ssh-over-tor-windows.md`](./ssh-over-tor-windows.md) (Windows), [`ssh-over-tor-arch.md`](./ssh-over-tor-arch.md) (Arch Linux)
- Original notes in this repo — [`setup.md`](./setup.md)
