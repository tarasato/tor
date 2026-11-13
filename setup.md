## Fetching the Tor Developers key
```bash
cd ~
gpg --auto-key-locate nodefault,wkd --locate-keys torbrowser@torproject.org
# or
gpg --keyserver keys.openpgp.org --recv-keys EF6E286DDA85EA2A4BA7DE684E2C6E8793298290

gpg --output ./tor.keyring --export 0xEF6E286DDA85EA2A4BA7DE684E2C6E8793298290
ls -l ./tor.keyring
```
# if --auto-key-locate not working
```bash
cd ~
gpg --keyserver keys.openpgp.org --recv-keys EF6E286DDA85EA2A4BA7DE684E2C6E8793298290
gpg --output ./tor.keyring --export 0xEF6E286DDA85EA2A4BA7DE684E2C6E8793298290
ls -l ./tor.keyring
```
## Verifying the signature
```bash
gpgv --keyring ./tor.keyring ~/Downloads/tor-browser-linux-x86_64-13.0.1.tar.xz.asc ~/Downloads/tor-browser-linux-x86_64-13.0.1.tar.xz
```
# incase if key expired
```bash
gpg --refresh-keys EF6E286DDA85EA2A4BA7DE684E2C6E8793298290
```

Create torrc with no .txt in same folder with tor.exe

```
SocksPort 9050

HiddenServiceDir E:\Tor\TorExpertBundle\tor\TorHiddenService1 #You must create a folder before running.
HiddenServiceVersion 3
HiddenServicePort 80 127.0.0.1:8080

HiddenServiceDir E:\Tor\TorExpertBundle\tor\TorHiddenService2 #You must create a folder before running.
HiddenServiceVersion 3
HiddenServicePort 25565 127.0.0.1:25565

DataDirectory E:\Tor\TorExpertBundle\Data

Log notice stdout
Log notice file E:\Tor\TorExpertBundle\tor\log.txt
```

tor.exe -f torrc

netstat -ano | findstr :9050

tasklist /FI "PID eq <PID>"

curl https://check.torproject.org/

netsh trace start capture=yes tracefile=c:\temp\nettrace.etl
