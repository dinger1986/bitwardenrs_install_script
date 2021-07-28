####     Thanks to wh1te909 who I stole (or got inspiration) alot of this script from (first script I have ever written)
####     and https://pieterhollander.nl/post/vaultwarden/ which I followed the steps and converted them to a script


#check if running on ubuntu 20.04
UBU20=$(grep 20.04 "/etc/"*"release")
if ! [[ $UBU20 ]]; then
  echo -ne "\033[0;31mThis script will only work on Ubuntu 20.04\e[0m\n"
  exit 1
fi

#check if running as root
if [ $EUID -eq 0 ]; then
  echo -ne "\033[0;31mDo NOT run this script as root. Exiting.\e[0m\n"
  exit 1
fi

#Username
echo -ne "Enter your created username if you havent done this please do it now, use ctrl+c to cancel this script and do it${NC}: "
read username

#Set email address
echo -ne "Enter your Email Address${NC}: "
read email

#Set Name
while [[ $name != *[.]* ]]
do
echo -ne "Enter your Name Firstname.Lastname${NC}: "
read name
done

#Enter domain
while [[ $domain != *[.]*[.]* ]]
do
echo -ne "Enter your Domain${NC}: "
read domain
done

admintoken=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 70 | head -n 1)

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

#Configure GIT
sudo git config --global user.email "${email}"
sudo git config --global user.name "${name}"

#install dependencies
sudo apt update && apt list -u && sudo apt dist-upgrade -y
sudo apt install dirmngr git libssl-dev pkg-config build-essential curl wget git apt-transport-https ca-certificates curl software-properties-common pwgen nginx-full letsencrypt libpq-dev pkg-config  -y
curl -sL https://deb.nodesource.com/setup_12.x | sudo bash -
sudo apt install nodejs -y
curl https://sh.rustup.rs -sSf | sh
source ${HOME}/.cargo/env

#Set firewall
sudo ufw allow OpenSSH
sudo ufw allow "Nginx Full"
sudo ufw enable

#####Letsencrypt and web

#Make directory
sudo mkdir /etc/nginx/includes
sudo chown ${username}:${username} -R /etc/nginx/includes

#Set Letsencrypt file
letsencrypt="$(cat << EOF
#############################################################################
# Configuration file for Let's Encrypt ACME Challenge location
# This file is already included in listen_xxx.conf files.
# Do NOT include it separately!
#############################################################################
#
# This config enables to access /.well-known/acme-challenge/xxxxxxxxxxx
# on all our sites (HTTP), including all subdomains.
# This is required by ACME Challenge (webroot authentication).
# You can check that this location is working by placing ping.txt here:
# /var/www/letsencrypt/.well-known/acme-challenge/ping.txt
# And pointing your browser to:
# http://xxx.domain.tld/.well-known/acme-challenge/ping.txt
#
# Sources:
# https://community.letsencrypt.org/t/howto-easy-cert-generation-and-renewal-with-nginx/3491
#
# Rule for legitimate ACME Challenge requests
location ^~ /.well-known/acme-challenge/ {
    default_type "text/plain";
    # this can be any directory, but this name keeps it clear
    root /var/www/letsencrypt;
}
# Hide /acme-challenge subdirectory and return 404 on all requests.
# It is somewhat more secure than letting Nginx return 403.
# Ending slash is important!
location = /.well-known/acme-challenge/ {
    return 404;
}

EOF
)"
echo "${letsencrypt}" > /etc/nginx/includes/letsencrypt.conf

sudo mkdir /var/www/letsencrypt

sudo chown ${username}:${username} -R /etc/nginx/sites-available/

#Set vaultwarden web file
vaultwardenconf="$(cat << EOF
#
# HTTP does *soft* redirect to HTTPS
#
server {
    # add [IP-Address:]80 in the next line if you want to limit this to a single interface
    listen 0.0.0.0:80;
   server_name ${domain};
    root /home/data/${domain};
    index index.php;

    # change the file name of these logs to include your server name
    # if hosting many services...
    access_log /var/log/nginx/${domain}_access.log;
    error_log /var/log/nginx/${domain}_error.log;
    include includes/letsencrypt.conf;     # redirect all HTTP traffic to HTTPS.
    location / {
        return  302 https://${domain};
    }
}

EOF
)"
echo "${vaultwardenconf}" > /etc/nginx/sites-available/vaultwarden

#make vaultwarden site live
sudo ln /etc/nginx/sites-available/vaultwarden /etc/nginx/sites-enabled/vaultwarden

#restart nginx
sudo service nginx restart

#run certification
sudo letsencrypt certonly --webroot -w /var/www/letsencrypt -d ${domain}

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

#Create vaultwarden folder and copy
sudo mkdir /opt/vaultwarden
sudo cp -r ~/vaultwarden/target/release/vaultwarden /opt/vaultwarden
sudo mv ~/web-vault /opt/vaultwarden/web-vault
sudo mkdir /opt/vaultwarden/data
sudo mkdir /etc/vaultwarden
sudo chown ${username}:${username} -R /etc/vaultwarden
sudo chown ${username}:${username} -R /opt/vaultwarden

touch /etc/vaultwarden/vaultwarden.conf

#Set vaultwardenRS Conf File
vaultwardenconf="$(cat << EOF
## Bitwarden_RS Configuration File
## Uncomment any of the following lines to change the defaults
##
## Be aware that most of these settings will be overridden if they were changed.
## in the admin interface. Those overrides are stored within DATA_FOLDER/config.json .

## Main data folder
# DATA_FOLDER=data

## Database URL
## When using SQLite, this is the path to the DB file, default to %DATA_FOLDER%/db.sqlite3
# DATABASE_URL=data/db.sqlite3
## When using MySQL, specify an appropriate connection URI.
## Details: https://docs.diesel.rs/diesel/mysql/struct.MysqlConnection.html
# DATABASE_URL=mysql://user:password@host[:port]/database_name
## When using PostgreSQL, specify an appropriate connection URI (recommended)
## or keyword/value connection string.
## Details:
## - https://docs.diesel.rs/diesel/pg/struct.PgConnection.html
## - https://www.postgresql.org/docs/current/libpq-connect.html#LIBPQ-CONNSTRING
## DATABASE_URL=mysql://vwarden:${mysqlpwd}@localhost:3306/vwarden


## Individual folders, these override %DATA_FOLDER%
# RSA_KEY_FILENAME=data/rsa_key
# ICON_CACHE_FOLDER=data/icon_cache
# ATTACHMENTS_FOLDER=data/attachments

## Templates data folder, by default uses embedded templates
## Check source code to see the format
# TEMPLATES_FOLDER=/path/to/templates
## Automatically reload the templates for every request, slow, use only for development
# RELOAD_TEMPLATES=false

## Client IP Header, used to identify the IP of the client, defaults to "X-Client-IP"
## Set to the string "none" (without quotes), to disable any headers and just use the remote IP
# IP_HEADER=X-Client-IP

## Cache time-to-live for successfully obtained icons, in seconds (0 is "forever")
# ICON_CACHE_TTL=2592000
## Cache time-to-live for icons which weren't available, in seconds (0 is "forever")
# ICON_CACHE_NEGTTL=259200

## Web vault settings
#WEB_VAULT_FOLDER=/opt/vaultwarden/web-vault/
#WEB_VAULT_ENABLED=true

## Enables websocket notifications
WEBSOCKET_ENABLED=true

## Controls the WebSocket server address and port
WEBSOCKET_ADDRESS=127.0.0.1
#WEBSOCKET_PORT=3012

## Enable extended logging, which shows timestamps and targets in the logs
# EXTENDED_LOGGING=true

## Timestamp format used in extended logging.
## Format specifiers: https://docs.rs/chrono/latest/chrono/format/strftime
# LOG_TIMESTAMP_FORMAT="%Y-%m-%d %H:%M:%S.%3f"

## Logging to file
## This requires extended logging
## It's recommended to also set 'ROCKET_CLI_COLORS=off'
LOG_FILE=/var/log/vaultwarden/error.log

## Logging to Syslog
## This requires extended logging
## It's recommended to also set 'ROCKET_CLI_COLORS=off'
# USE_SYSLOG=false

## Log level
## Change the verbosity of the log output
## Valid values are "trace", "debug", "info", "warn", "error" and "off"
## Setting it to "trace" or "debug" would also show logs for mounted
## routes and static file, websocket and alive requests
LOG_LEVEL=info

## Enable WAL for the DB
## Set to false to avoid enabling WAL during startup.
## Note that if the DB already has WAL enabled, you will also need to disable WAL in the DB,
## this setting only prevents vaultwarden_rs from automatically enabling it on start.
## Please read project wiki page about this setting first before changing the value as it can
## cause performance degradation or might render  the service unable to start.
# ENABLE_DB_WAL=true

## Disable icon downloading
## Set to true to disable icon downloading, this would still serve icons from $ICON_CACHE_FOLDER,
## but it won't produce any external network request. Needs to set $ICON_CACHE_TTL to 0,
## otherwise it will delete them and they won't be downloaded again.
# DISABLE_ICON_DOWNLOAD=false

## Icon download timeout
## Configure the timeout value when downloading the favicons.
## The default is 10 seconds, but this could be to low on slower network connections
# ICON_DOWNLOAD_TIMEOUT=10

## Icon blacklist Regex
## Any domains or IPs that match this regex won't be fetched by the icon service.
## Useful to hide other servers in the local network. Check the WIKI for more details
# ICON_BLACKLIST_REGEX=192\.168\.1\.[0-9].*^

## Any IP which is not defined as a global IP will be blacklisted.
## Usefull to secure your internal environment: See https://en.wikipedia.org/wiki/Reserved_IP_addresses for a list of IPs which it will block
# ICON_BLACKLIST_NON_GLOBAL_IPS=true

## Disable 2FA remember
## Enabling this would force the users to use a second factor to login every time.
## Note that the checkbox would still be present, but ignored.
# DISABLE_2FA_REMEMBER=false

## Controls if new users can register
# SIGNUPS_ALLOWED=true

## Controls if new users need to verify their email address upon registration
## Note that setting this option to true prevents logins until the email address has been verified!
## The welcome email will include a verification link, and login attempts will periodically
## trigger another verification email to be sent.
# SIGNUPS_VERIFY=false

## If SIGNUPS_VERIFY is set to true, this limits how many seconds after the last time
## an email verification link has been sent another verification email will be sent
# SIGNUPS_VERIFY_RESEND_TIME=3600

## If SIGNUPS_VERIFY is set to true, this limits how many times an email verification
## email will be re-sent upon an attempted login.
# SIGNUPS_VERIFY_RESEND_LIMIT=6

## Controls if new users from a list of comma-separated domains can register
## even if SIGNUPS_ALLOWED is set to false
# SIGNUPS_DOMAINS_WHITELIST=example.com,example.net,example.org

## Controls which users can create new orgs.
## Blank or 'all' means all users can create orgs (this is the default):
ORG_CREATION_USERS=all
## 'none' means no users can create orgs:
# ORG_CREATION_USERS=none
## A comma-separated list means only those users can create orgs:
# ORG_CREATION_USERS=admin1@example.com,admin2@example.com

## Token for the admin interface, preferably use a long random string
## One option is to use 'openssl rand -base64 48'
## If not set, the admin panel is disabled
ADMIN_TOKEN=${admintoken}

## Enable this to bypass the admin panel security. This option is only
## meant to be used with the use of a separate auth layer in front
# DISABLE_ADMIN_TOKEN=false

## Invitations org admins to invite users, even when signups are disabled
# INVITATIONS_ALLOWED=true

## Controls the PBBKDF password iterations to apply on the server
## The change only applies when the password is changed
# PASSWORD_ITERATIONS=100000

## Whether password hint should be sent into the error response when the client request it
SHOW_PASSWORD_HINT=false

## Domain settings
## The domain must match the address from where you access the server
## It's recommended to configure this value, otherwise certain functionality might not work,
## like attachment downloads, email links and U2F.
## For U2F to work, the server must use HTTPS, you can use Let's Encrypt for free certs
DOMAIN=https://${domain}

## Yubico (Yubikey) Settings
## Set your Client ID and Secret Key for Yubikey OTP
## You can generate it here: https://upgrade.yubico.com/getapikey/
## You can optionally specify a custom OTP server
# YUBICO_CLIENT_ID=11111
# YUBICO_SECRET_KEY=AAAAAAAAAAAAAAAAAAAAAAAA
# YUBICO_SERVER=http://yourdomain.com/wsapi/2.0/verify

## Duo Settings
## You need to configure all options to enable global Duo support, otherwise users would need to configure it themselves
## Create an account and protect an application as mentioned in this link (only the first step, not the rest):
## https://help.vaultwarden.com/article/setup-two-step-login-duo/#create-a-duo-security-account
## Then set the following options, based on the values obtained from the last step:
# DUO_IKEY=<Integration Key>
# DUO_SKEY=<Secret Key>
# DUO_HOST=<API Hostname>
## After that, you should be able to follow the rest of the guide linked above,
## ignoring the fields that ask for the values that you already configured beforehand.

## Authenticator Settings
## Disable authenticator time drifted codes to be valid.
## TOTP codes of the previous and next 30 seconds will be invalid
##
## According to the RFC6238 (https://tools.ietf.org/html/rfc6238),
## we allow by default the TOTP code which was valid one step back and one in the future.
## This can however allow attackers to be a bit more lucky with there attempts because there are 3 valid codes.
## You can disable this, so that only the current TOTP Code is allowed.
## Keep in mind that when a sever drifts out of time, valid codes could be marked as invalid.
## In any case, if a code has been used it can not be used again, also codes which predates it will be invalid.
# AUTHENTICATOR_DISABLE_TIME_DRIFT = false

## Rocket specific settings, check Rocket documentation to learn more
# ROCKET_ENV=staging
ROCKET_ADDRESS=127.0.0.1
ROCKET_PORT=8000
# ROCKET_TLS={certs="/path/to/certs.pem",key="/path/to/key.pem"}

## Mail specific settings, set SMTP_HOST and SMTP_FROM to enable the mail service.
## Note: if SMTP_USERNAME is specified, SMTP_PASSWORD is mandatory
#SMTP_HOST=smtp.${domain}
#SMTP_FROM=vault@${domain}
# SMTP_FROM_NAME=Bitwarden_RS
#SMTP_PORT=25
#SMTP_SSL=true
# SMTP_EXPLICIT_TLS=true
#SMTP_USERNAME=vault@${domain}
#SMTP_PASSWORD=____PASSWORD____
# SMTP_AUTH_MECHANISM="Plain"
# SMTP_TIMEOUT=15

# vim: syntax=ini

EOF
)"
echo "${vaultwardenconf}" > /etc/vaultwarden/vaultwarden.conf

#Add some folders and permissions
sudo chmod 600 /etc/vaultwarden/vaultwarden.conf
sudo chown ${username}:${username} /etc/vaultwarden/vaultwarden.conf

sudo mkdir /var/log/vaultwarden
sudo chown -R ${username}:${username} /var/log/vaultwarden
touch /var/log/vaultwarden/error.log

#Stop nginx to remove file
sudo service nginx stop

#Remove vaultwarden config to add SSL
sudo rm /etc/nginx/sites-enabled/vaultwarden
sudo rm /etc/nginx/sites-available/vaultwarden
sudo chown ${username}:${username} -R /etc/nginx/sites-available

touch /etc/nginx/sites-available/vaultwarden

#Set vaultwarden web file with SSL
vaultwardenconf2="$(cat << EOF
server {
    listen 80;
    server_name ${domain};

    location /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
    }

    location / {
        return 301 https://${domain};
    }
}

server {
    listen 443 ssl http2;
    server_name ${domain};

    client_max_body_size 128M;

    ssl_certificate /etc/letsencrypt/live/${domain}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${domain}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers "ECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH";
    ssl_ecdh_curve secp384r1;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;
    ssl_stapling on;
    ssl_stapling_verify on;
    resolver 127.0.0.1 valid=300s;
    resolver_timeout 5s;
    add_header X-Content-Type-Options nosniff;
    add_header Strict-Transport-Security "max-age=63072000; preload";
    keepalive_timeout 300s;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header X-Forwarded-Host server_name;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /notifications/hub {
        proxy_pass http://127.0.0.1:3012;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    location /notifications/hub/negotiate {
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_pass http://127.0.0.1:8000;
    }
}
EOF
)"
echo "${vaultwardenconf2}" > /etc/nginx/sites-available/vaultwarden

#reenable vaultwarden site
sudo ln /etc/nginx/sites-available/vaultwarden /etc/nginx/sites-enabled/vaultwarden

#Start nginx with SSL
sudo service nginx start

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
ReadWritePaths=/opt/vaultwarden/data/ /var/log/vaultwarden/error.log

# Set reasonable connection and process limits
LimitNOFILE=1048576
LimitNPROC=64

[Install]
WantedBy=multi-user.target

EOF
)"
echo "${vaultwardenservice}" > /etc/systemd/system/vaultwarden.service

sudo systemctl daemon-reload
sudo systemctl enable vaultwarden
sudo systemctl start vaultwarden

#####Fail2ban setup
sudo apt install -y fail2ban

#Create files
sudo touch /etc/fail2ban/filter.d/vaultwarden.conf
sudo touch /etc/fail2ban/jail.d/vaultwarden.local
sudo touch /etc/fail2ban/filter.d/vaultwarden-admin.conf
sudo touch /etc/fail2ban/jail.d/vaultwarden-admin.local

#Set vaultwarden fail2ban filter conf File
vaultwardenfail2banfilter="$(cat << EOF
[INCLUDES]
before = common.conf

[Definition]
failregex = ^.*Username or password is incorrect\. Try again\. IP: <HOST>\. Username:.*$
ignoreregex =
EOF
)"
echo "${vaultwardenfail2banfilter}" | sudo tee -a /etc/fail2ban/filter.d/vaultwarden.conf > /dev/null

#Set vaultwarden fail2ban jail conf File
vaultwardenfail2banjail="$(cat << EOF
[vaultwarden]
enabled = true
port = 80,443,8081
filter = vaultwarden
action = iptables-allports[name=vaultwarden]
logpath = /var/log/vaultwarden/error.log
maxretry = 3
bantime = 14400
findtime = 14400
EOF
)"
echo "${vaultwardenfail2banjail}" | sudo tee -a /etc/fail2ban/jail.d/vaultwarden.local > /dev/null

#Set vaultwarden fail2ban admin filter conf File
vaultwardenfail2banadminfilter="$(cat << EOF
[INCLUDES]
before = common.conf

[Definition]
failregex = ^.*Unauthorized Error: Invalid admin token\. IP: <HOST>.*$
ignoreregex =
EOF
)"
echo "${vaultwardenfail2banadminfilter}" | sudo tee -a /etc/fail2ban/filter.d/vaultwarden-admin.conf > /dev/null

#Set vaultwarden fail2ban admin jail conf File
vaultwardenfail2banadminjail="$(cat << EOF
[vaultwarden-admin]
enabled = true
port = 80,443
filter = vaultwarden-admin
action = iptables-allports[name=vaultwarden]
logpath = /var/log/vaultwarden/error.log
maxretry = 5
bantime = 14400
findtime = 14400
EOF
)"
echo "${vaultwardenfail2banadminjail}" | sudo tee -a /etc/fail2ban/jail.d/vaultwarden-admin.local > /dev/null

sudo systemctl restart fail2ban

printf >&2 "Please go to admin url: https://${domain}/admin\n\n"
printf >&2 "Enter ${admintoken} to gain access, please save this somewhere!!\n\n"

echo "Press any key to finish install"
while [ true ] ; do
read -t 3 -n 1
if [ $? = 0 ] ; then
exit ;
else
echo "waiting for the keypress"
fi
done
