# Install openssh
```bash
sudo pacman -Syu openssh
```
# Setup passwordless
```bash
sudo systemctl enable --now sshd
sudo sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart sshd
```
# Add Authorized Keys
```
cat > ~/.ssh/authorized_keys << 'EOF'
ssh-ed25519 example_key
EOF
```
Or
```bash
echo "ssh-ed25519 example_key" >> ~/.ssh/authorized_keys
```
# Add permission
```bash
chmod 600 ~/.ssh/authorized_keys
```
# Move file
```bash
scp -i ~/.ssh/id_ed25519 -r C:/path/to/dir ubuntu@0.0.0.0:~/dir
```
