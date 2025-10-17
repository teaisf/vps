#!/bin/bash
set -e

###############################
# 1. Create user "debian" without password
###############################
if ! id -u debian >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" debian
fi

echo "👉 Now set a password for user 'debian':"
passwd debian

###############################
# 2. Install basic packages
###############################
apt update
apt install -y sudo ufw curl ca-certificates gnupg lsb-release

###############################
# 3. Add user to sudo and docker groups
###############################
usermod -aG sudo debian

###############################
# 4. Disable password prompt for sudo
###############################
echo "debian ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/010_debian_nopasswd
chmod 440 /etc/sudoers.d/010_debian_nopasswd

###############################
# 5. Setup SSH key login for user "debian"
###############################
sudo -u debian mkdir -p /home/debian/.ssh
sudo -u debian chmod 700 /home/debian/.ssh

# Placeholder public key
cat << 'EOF' > /home/debian/.ssh/authorized_keys
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC4KTGHISS2+/8BiNrNQO4MmIwp5GFRQg7iQzsjTqCqmmJI5ioS0ldC9KbrK3pokRXSYlnytVOVMUJ5Y29KoG7tOahtl07ZcfE5BerBtZt41ZTDcAVxLlA+MqcuhmVZM1bA3+AoSOGFWikKKW9rfqCFMFcpIlpTtLyxSKma2hCuMleeVQCK4VG8voIA2fnHvqdZywVyBdPiMMXuI8lpWkK4EKE9sKr8RwC6+/4yNltICDsm1ZBWbUiHBpmuiQJp4rz+FcCpq/UJ43xJXFguLzAGjLfPquEUqJu5jIQJowZEviJqfD9uR9P7K7LoFkrAel9szGjxXKo1vZ9YxkyQJc2NNFawhK98rlOraJuiVV3RkIKBODlD5zukQ5Gw/+BFsu24rLQYHPQXgOOMSun8W7nu50ye28pZoU44cIifHCbaOfad7kMt/azGt1mBUcR1bO6Tj3+IWMQiUK2P55Thi9elDckrKtdKHl7JzVQ5ieeBxaHm2zZK7kRLap5nstOLgk0= user@local
EOF

chmod 600 /home/debian/.ssh/authorized_keys
chown -R debian:debian /home/debian/.ssh

###############################
# 6. Disable SSH password login (key-only)
###############################
SSHD_CONFIG="/etc/ssh/sshd_config"

# Ensure "PasswordAuthentication no" is present
if grep -q "^PasswordAuthentication" "$SSHD_CONFIG"; then
  sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD_CONFIG"
else
  echo "PasswordAuthentication no" >> "$SSHD_CONFIG"
fi

# Ensure "ChallengeResponseAuthentication no" is set
if grep -q "^ChallengeResponseAuthentication" "$SSHD_CONFIG"; then
  sed -i 's/^ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' "$SSHD_CONFIG"
else
  echo "ChallengeResponseAuthentication no" >> "$SSHD_CONFIG"
fi

# Harden root login
if grep -q "^PermitRootLogin" "$SSHD_CONFIG"; then
  sed -i 's/^PermitRootLogin.*/PermitRootLogin prohibit-password/' "$SSHD_CONFIG"
else
  echo "PermitRootLogin prohibit-password" >> "$SSHD_CONFIG"
fi

systemctl reload sshd || systemctl restart ssh

###############################
# 7. Configure UFW
###############################
ufw allow OpenSSH
ufw --force enable

###############################
# 8. Install Docker (official repository)
###############################
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --yes --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/debian \
$(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add user to docker group
usermod -aG docker debian

docker network create nginx-proxy

###############################
# 9. Add UFW-Docker rules
###############################
UFW_RULES=/etc/ufw/after.rules

if ! grep -q "BEGIN UFW AND DOCKER" $UFW_RULES; then
cat << 'EOF' >> $UFW_RULES

# BEGIN UFW AND DOCKER
*filter
:ufw-user-forward - [0:0]
:DOCKER-USER - [0:0]
-A DOCKER-USER -j RETURN -s 10.0.0.0/8
-A DOCKER-USER -j RETURN -s 172.16.0.0/12
-A DOCKER-USER -j RETURN -s 192.168.0.0/16

-A DOCKER-USER -j ufw-user-forward

-A DOCKER-USER -j DROP -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -d 192.168.0.0/16
-A DOCKER-USER -j DROP -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -d 10.0.0.0/8
-A DOCKER-USER -j DROP -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -d 172.16.0.0/12
-A DOCKER-USER -j DROP -p udp -m udp --dport 0:32767 -d 192.168.0.0/16
-A DOCKER-USER -j DROP -p udp -m udp --dport 0:32767 -d 10.0.0.0/8
-A DOCKER-USER -j DROP -p udp -m udp --dport 0:32767 -d 172.16.0.0/12

-A DOCKER-USER -j RETURN
COMMIT
# END UFW AND DOCKER
EOF
fi

ufw reload

###############################
# 10. Allow HTTP & HTTPS
###############################
ufw route allow proto tcp from any to any port 80
ufw route allow proto tcp from any to any port 443

###############################
# 11. Final reboot
###############################
echo "✅ Setup complete. Rebooting now..."
sleep 3
reboot
