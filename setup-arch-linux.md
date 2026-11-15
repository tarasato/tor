# Install tor
```bash
sudo pacman -Syu tor
```
# Config
```bash
nano /etc/tor/torrc
```

```bash
SocksPort 9050
HiddenServiceDir /mnt/exmaple/HiddenService1
HiddenServiceVersion 3
HiddenServicePort 8080 127.0.0.1:8080
DataDirectory /var/lib/tor
Log notice stdout
```
Or
```bash
sudo cat > /etc/tor/torrc << 'EOF'
SocksPort 9050
HiddenServiceDir /mnt/exmaple/HiddenService1
HiddenServiceVersion 3
HiddenServicePort 8080 127.0.0.1:8080
DataDirectory /var/lib/tor
Log notice stdout
EOF
```

# Make directory for HiddenServiceDir
```bash
sudo mkdir -p /mnt/exmaple/tor
sudo chown -R tor:tor /mnt/exmaple/HiddenService1
sudo chmod 700 /mnt/exmaple/tor
```

# Start Service
```bash
sudo systemctl enable --now tor
sudo systemctl status tor --no-pager
```

# Get .onion address
```bash
sudo cat /mnt/exmaple/HiddenService1/hostname
```
