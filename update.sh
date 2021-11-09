####     Thanks to wh1te909 who I stole (or got inspiration) alot of this script from (first script I have ever written) 
####     and https://pieterhollander.nl/post/bitwarden/ which I followed the steps and converted them to a script

#check if running on ubuntu 20.04
UBU20=$(grep 20.04 "/etc/"*"release")
if ! [[ $UBU20 ]]; then
  echo -ne "\033[0;31mThis script will only work on Ubuntu 20.04\e[0m\n"
  exit 1
fi

#Ensure not running as root
if [ $EUID -eq 0 ]; then
  echo -ne "\033[0;31mDo NOT run this script as root. Exiting.\e[0m\n"
  exit 1
fi

#Username
echo -ne "Enter your created username if you havent done this please do it now, use ctrl+c to cancel this script and do it${NC}: "
read username

#Check Sudo works
if [[ "$EUID" != 0 ]]; then
    sudo -k # make sure to ask for password on next sudo
    if sudo true; then
        echo "Password ok"
    else
        echo "Aborting script"
        exit 1
    fi
fi

echo "Running Script"

#Clean up old folders
rm -rf ~/bitwarden_rs ~/web ~/vaultwarden ~/bw_web*.tar.gz

#Check if showing as bitwardenrs and rename to vaultwarden
if [ -d "/opt/vaultwarden/" ]; then
    echo "Already running as vaultwarden nothing to do" 
else
    echo "Migrating to vaultwarden"
	sudo systemctl stop bitwarden
	sudo mv /opt/bitwardenrs /opt/vaultwarden
	sudo mv /etc/bitwardenrs /etc/vaultwarden
	sudo mv /etc/vaultwarden/bitwardenrs.conf /etc/vaultwarden/vaultwarden.conf
	sudo rm /etc/systemd/system/bitwarden.service

sudo touch /etc/systemd/system/vaultwarden.service
sudo chown ${username}:${username} -R /etc/systemd/system/vaultwarden.service

#Set vaultwarden Service File
vaultwardenservice="$(cat << EOF
[Unit]
Description=Vaultwarden server
After=network.target auditd.service

[Service]
RestartSec=2s
Type=simple

User=${username}
Group=${username}

EnvironmentFile=/etc/vaultwarden/vaultwarden.conf

WorkingDirectory=/opt/vaultwarden/
ExecStart=/opt/vaultwarden/vaultwarden
Restart=always

# Isolate vaultwarden from the rest of the system
PrivateTmp=true
PrivateDevices=true
ProtectHome=true
NoNewPrivileges=true
ProtectSystem=strict

# Only allow writes to the following directory
ReadWritePaths=/opt/vaultwarden/data/ /var/log/bitwardenrs/error.log

# Set reasonable connection and process limits
LimitNOFILE=1048576
LimitNPROC=64

[Install]
WantedBy=multi-user.target

EOF
)"
echo "${vaultwardenservice}" > /etc/systemd/system/vaultwarden.service

sudo systemctl unmask vaultwarden.service
sudo systemctl daemon-reload
sudo systemctl enable vaultwarden
sudo systemctl start vaultwarden	

fi

#Upgrade Rust
curl https://sh.rustup.rs -sSf | sh
source $HOME/.cargo/env

#Compile vaultwarden
git clone https://github.com/dani-garcia/vaultwarden.git
cd vaultwarden/
git checkout
cargo build --features postgresql --release
cd ..

#Download precompiled webvault
VWRELEASE=$(curl -s https://api.github.com/repos/dani-garcia/bw_web_builds/releases/latest \
| grep "tag_name" \
| awk '{print substr($2, 2, length($2)-3) }') \

wget https://github.com/dani-garcia/bw_web_builds/releases/download/$VWRELEASE/bw_web_$VWRELEASE.tar.gz

tar -xzf bw_web_$VWRELEASE.tar.gz

#Apply Updates and restart Bitwarden_RS
sudo systemctl stop vaultwarden.service
sudo cp -r ~/vaultwarden/target/release/vaultwarden /opt/vaultwarden
sudo rm -rf /opt/vaultwarden/web-vault
sudo mv ~/web-vault /opt/vaultwarden/web-vault
sudo chown -R ${username}:${username} /opt/vaultwarden
sudo systemctl start vaultwarden.service

#restart nginx
sudo service nginx restart
