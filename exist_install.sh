###############################################################
#
# EXIST
#
################################################################
## initial setting
export LANG=en_US.UTF-8
echo include_only=.jp >> /etc/yum/pluginconf.d/fastestmirror.conf

## DB initial setting
export DBHOST='localhost'
export DBNAME='exist'
export DBUSER_ADMIN='root'
export DBPASSWORD_ADMIN="$(openssl rand -hex 32)"
export DBUSER_EXIST='exist'
export DBPASSWORD_EXIST="$(openssl rand -hex 32)"
export FQDN='localhost'

## DB install 
curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash
yum install mariadb mariadb-server -y
systemctl enable mariadb.service
systemctl start  mariadb.service

## Create EXIST DB
yum install expect -y
expect -f - <<-EOF
    set timeout 10

    spawn mysql_secure_installation;
    expect "Enter current password for root (enter for none):"
    send -- "\r"
    expect "Switch to unix_socket authentication"
    send -- "y\r"
    expect "Change the root password?"
    send -- "y\r"
    expect "New password:"
    send -- "${DBPASSWORD_ADMIN}\r"
    expect "Re-enter new password:"
    send -- "${DBPASSWORD_ADMIN}\r"
    expect "Remove anonymous users?"
    send -- "y\r"
    expect "Disallow root login remotely?"
    send -- "y\r"
    expect "Remove test database and access to it?"
    send -- "y\r"
    expect "Reload privilege tables now?"
    send -- "y\r"
    expect eof
EOF

## uninstall expect
yum remove tcl expect -y

##DB reflect the settings
systemctl restart mariadb.service
systemctl status mariadb.service
mysql -u ${DBUSER_ADMIN} -p${DBPASSWORD_ADMIN} -e "create database intelligence_db;"
mysql -u ${DBUSER_ADMIN} -p${DBPASSWORD_ADMIN} -e "create user '${DBNAME}'@'${DBHOST}' identified by '${DBPASSWORD_EXIST}';"
mysql -u ${DBUSER_ADMIN} -p${DBPASSWORD_ADMIN} -e "grant ALL on intelligence_db.* to ${DBNAME};"


## Git clone EXIST
cd /opt
git clone https://github.com/nict-csl/exist.git

## Install EXIST requirements
cd /opt/exist
pip install -r requirements.txt

## Change settings.py
sed -i -e "s/os.environ.get('EXIST_DB_NAME', 'intelligence_db')/intelligence_db/g" intelligence/settings.py
sed -i -e "s/os.environ.get('EXIST_DB_USER'),/exist/g" intelligence/settings.py
sed -i -e "s/os.environ.get('EXIST_DB_PASSWORD')/${DBPASSWORD_EXIST}/g" intelligence/settings.py
sed -i -e "s/os.environ.get('EXIST_DB_HOST', 'localhost')/${DBHOST}/g" intelligence/settings.py
sed -i -e "s/os.environ.get('EXIST_DB_PORT', '3306')/3306/g" intelligence/settings.py
sed -i -e "s/\"SET CHARACTER SET utf8mb4;\"/\"SET CHARACTER SET utf8mb4;\"\n                            \"SET sql_mode='STRICT_TRANS_TABLES';\"/g" intelligence/settings.py

## Django initial setting
python3 manage.py makemigrations exploit reputation threat threat_hunter twitter twitter_hunter news news_hunter vuln
python3 manage.py migrate

## .env initial setting
cp .env.example .env
SECRET_KEY=$(python3 keygen.py)
HOST_IP=$(ip route get 8.8.8.8 | awk -F"src " 'NR==1{split($2,a," ");print a[1]}')
sed -i -e "s/your_database_user/${DBUSER_EXIST}/g" .env
sed -i -e "s/your_database_password/${DBPASSWORD_EXIST}/g" .env
sed -i -e "s/insert_your_secret_key/${SECRET_KEY}/g" .env
sed -i -e "s/False/True/g" .env
sed -i -e "s/192.168.56.101/${HOST_IP}|localhost|/g" .env

## Redis install
yum install redis -y
systemctl start redis
systemctl enable redis

## Make celery config
cat <<EOL >> /etc/sysconfig/celery
# Name of nodes to start
# here we have a single node
CELERYD_NODES="localhost"
# or we could have three nodes:
#CELERYD_NODES="w1 w2 w3"
# Absolute or relative path to the 'celery' command:
CELERY_BIN="/root/.pyenv/shims/celery"
# App instance to use
# comment out this line if you don't use an app
CELERY_APP="intelligence"
# or fully qualified:
#CELERY_APP="proj.tasks:app"
# How to call manage.py
CELERYD_MULTI="multi"
# Extra command-line arguments to the worker
CELERYD_OPTS="--time-limit=300 --concurrency=8"
# - %n will be replaced with the first part of the nodename.
# - %I will be replaced with the current child process index
# and is important when using the prefork pool to avoid race conditions.
CELERYD_PID_FILE="/var/run/celery/%n.pid"
CELERYD_LOG_FILE="/var/log/celery/%n%I.log"
CELERYD_LOG_LEVEL="INFO"
EOL

cat <<EOL >> /etc/systemd/system/celery.service
[Unit]
Description=Celery Service
After=network.target
[Service]
Type=forking
User=root
Group=root
EnvironmentFile=/etc/sysconfig/celery
WorkingDirectory=/opt/exist
ExecStart=/bin/sh -c '${CELERY_BIN} multi start ${CELERYD_NODES} \
-A ${CELERY_APP} --pidfile=${CELERYD_PID_FILE} \
--logfile=${CELERYD_LOG_FILE} --loglevel=${CELERYD_LOG_LEVEL} ${CELERYD_OPTS}'
ExecStop=/bin/sh -c '${CELERY_BIN} multi stopwait ${CELERYD_NODES} \
--pidfile=${CELERYD_PID_FILE}'
ExecReload=/bin/sh -c '${CELERY_BIN} multi restart ${CELERYD_NODES} \
-A ${CELERY_APP} --pidfile=${CELERYD_PID_FILE} \
--logfile=${CELERYD_LOG_FILE} --loglevel=${CELERYD_LOG_LEVEL} ${CELERYD_OPTS}'
[Install]
WantedBy=multi-user.target
EOL

mkdir /var/log/celery; chown root:root /var/log/celery
mkdir /var/run/celery; chown root:root /var/run/celery

cat <<EOL >> /etc/tmpfiles.d/exist.conf
#Type  Path               Mode  UID        GID         Age  Argument
d      /var/run/celery    0755  root  root  -
EOL

systemctl start celery.service
systemctl enable celery.service

## Firewall setting
systemctl status firewalld.service
firewall-cmd --zone=public --add-port=8000/tcp --permanent
firewall-cmd --reload

## Add Tweet Link
sed -i -e "s/{{ tw.datetime }}/\<a href=\"https:\/\/twitter.com\/{{ tw.screen_name }}\/status\/{{ tw.id }}\"\>{{ tw.datetime }}\<\/a\>/g" apps/twitter/templates/twitter/index.html
sed -i -e "s/{{ tw.datetime }}/\<a href=\"https:\/\/twitter.com\/{{ tw.screen_name }}\/status\/{{ tw.id }}\"\>{{ tw.datetime }}\<\/a\>/g" apps/dashboard/templates/dashboard/index.html
sed -i -e "s/{{ tw.datetime }}/\<a href=\"https:\/\/twitter.com\/{{ tw.screen_name }}\/status\/{{ tw.id }}\"\>{{ tw.datetime }}\<\/a\>/g" apps/dashboard/templates/dashboard/crosslist.html
sed -i -e "s/{{ tw.datetime }}/\<a href=\"https:\/\/twitter.com\/{{ tw.screen_name }}\/status\/{{ tw.id }}\"\>{{ tw.datetime }}\<\/a\>/g" apps/twitter_hunter/templates/twitter_hunter/tweets.html

# Web Site Screenshot
yum install wkhtmltopdf xorg-x11-server-Xvfb -y
cp scripts/url/url.conf.template scripts/url/url.conf
sed -i -e "s/path\/to\/your\/exist/opt\/exist/g" scripts/url/url.conf
sed -i -e "s/YOUR_DB_USER/exist/g" -e "s/YOUR_DB_PASSWORD/${DBPASSWORD_EXIST}/g" -e "s/YOUR_DB/intelligence_db/g" scripts/url/url.conf

# Japanese Font
yum install ipa-gothic-fonts ipa-pgothic-fonts -y
fc-cache -f

## EXIST Service
cat <<EOL >> /etc/systemd/system/exist.service
[Unit]
Description = EXIST
After = celery.service
[Service]
WorkingDirectory=/opt/exist
ExecStart=/root/.pyenv/shims/python3 manage.py runserver 0.0.0.0:8000
Restart=always
Type=simple
KillMode=control-group
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOL


## Start EXIST 
systemctl start exist.service
systemctl enable exist.service

echo "Admin (root) DB Password: ${DBPASSWORD_ADMIN}"
echo "User (exist) DB Password: ${DBPASSWORD_EXIST}"
