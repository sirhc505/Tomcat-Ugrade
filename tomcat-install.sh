#!/bin/sh

###########################################################
# Purpose:
#	This is the installation script for Shibboleth.
###########################################################
# Prereqs:
#	You will need to have already transfered the working 
#	archive of /opt/shibboleth-idp from a working node to 
#	this machine.
#	apr apr-devel httpd-devel libcurl-devel pcre-devel 
#	openssl-devel
############################################################

#Applications
CURL="/usr/bin/curl"
USERADD="/usr/sbin/useradd"
OPENSSL="/usr/bin/openssl"

BASE_URL="https://downloads.apache.org/tomcat/tomcat-9"

# Get the current running Tomcat version
TOMCAT_CURRENT=`java -classpath /opt/tomcat9/lib/catalina.jar org.apache.catalina.util.ServerInfo |grep "Server version" |cut -f 2 -d \/`
TOMCAT_LATEST=`curl -s https://downloads.apache.org/tomcat/tomcat-9/|grep v9 | cut -f 2 -d \> | cut -f 1 -d \/ |cut -f 2 -d \" | tail -n 1`

TOMCAT_VERSION=`echo $TOMCAT_LATEST | cut -f 2 -d v`
TOMCAT_WORKING_DIR="/opt/tomcat9"
TMP_TOMCAT="/tmp/apache-tomcat-$TOMCAT_VERSION.tar.gz"
TMP_SHASUM="/tmp/apache-tomcat-$TOMCAT_VERSION.tar.gz.sha512"

TOMCAT_BIN="https://downloads.apache.org/tomcat/tomcat-9/$TOMCAT_LATEST/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz"
TOMCAT_SHA="https://downloads.apache.org/tomcat/tomcat-9/$TOMCAT_LATEST/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz.sha512"


# Apache & SSL Variables
LONG_HOST=`hostname -f`
SHORT_HOST=`hostname -s`
OPENSSL_CERT_DIR="/root/certs"
OPENSSL_CONFIG="$OPENSSL_CERT_DIR/openssl.cnf"
CERT_REQ="$OPENSSL_CERT_DIR/server.csr"
CERT_KEY="$OPENSSL_CERT_DIR/server.key"

echo "--------------------------------------------------"
echo "Installing software prereqs"
echo "--------------------------------------------------"
yum -y install httpd apr apr-devel httpd-devel libcurl-devel pcre-devel openssl-devel pam-devel java-11-openjdk mod_ssl mailx

# Download Tomcat
echo "--------------------------------------------------"
echo "Downloading Tomcat"
echo "--------------------------------------------------"
$CURL $TOMCAT_BIN -o $TMP_TOMCAT
$CURL $TOMCAT_SHA -o $TMP_SHASUM

SHA_SUM=`sha512sum $TMP_TOMCAT`
ACTUAL_SUM=`cat $TMP_SHASUM`

echo "--------------------------------------------------"
echo "Validating SHA sums for the Tomcat download"
echo "--------------------------------------------------"
if [[ "$TMP_TOMCAT" != "$TMP_SHASUM" ]]; then
    echo "SHA sums do not match. Exiting..."
    exit 1
fi

echo "--------------------------------------------------"
echo "Creating Tomcat user account and directory"
echo "--------------------------------------------------"
mkdir $TOMCAT_WORKING_DIR
$USERADD -d $TOMCAT_WORKING_DIR -c 'Tomcat Service Account' $TOMCAT_USER

tar -zxf $TMP_TOMCAT -C $TOMCAT_WORKING_DIR --strip-components 1

# Make needed Directories
echo "--------------------------------------------------"
echo "Creating Red Hat consisted Tomcat directories"
echo "--------------------------------------------------"
mkdir /etc/tomcat/
mkdir -p /etc/tomcat/Catalina/localhost/
mkdir /usr/libexec/tomcat/
mkdir /var/lib/tomcat /var/lib/tomcats
mkdir /usr/share/tomcat
mkdir -p /var/log/tomcat
mkdir -p /var/lib/tomcat/webapps
mkdir -p /var/cache/tomcat/work

# Create symlinks to simulate an RPM based installation
echo "--------------------------------------------------"
echo "Linking all directories together"
echo "--------------------------------------------------"
ln -s /opt/tomcat9/lib /usr/share/tomcat/lib
ln -s /opt/tomcat9/bin /usr/share/tomcat/bin
ln -s /etc/tomcat /usr/share/tomcat/conf
ln -s /var/log/tomcat /usr/share/tomcat/logs
ln -s /var/lib/tomcat/webapps /usr/share/tomcat/webapps
ln -s /var/cache/tomcat/work /usr/share/tomcat/work
ln -s /opt/shibboleth-idp/war/idp.war /var/lib/tomcat/webapps/idp.war

# Copy configuration files
echo "--------------------------------------------------"
echo "Copying base Tomcat config"
echo "--------------------------------------------------"
cp configs/tomcat.conf /etc/tomcat/
cp /opt/tomcat9/conf/* /etc/tomcat/
cp libexec/* /usr/libexec/tomcat/

# Set folder ownership
echo "--------------------------------------------------"
echo "Setting Permissions"
echo "--------------------------------------------------"
chown tomcat.tomcat $TOMCAT_WORKING_DIR
chown tomcat.tomcat $TOMCAT_WORKING_DIR/* -R
chown tomcat.tomcat -R /etc/tomcat/*
chown root.tomcat /var/lib/tomcat /var/lib/tomcats
chown tomcat.tomcat /var/log/tomcat
chown tomcat.tomcat /var/lib/tomcat /var/lib/tomcat/* /var/cache/tomcat /var/cache/tomcat/* /etc/tomcat /etc/tomcat/*

echo "--------------------------------------------------"
echo "Creating systemd startup script for Tomcat"
echo "--------------------------------------------------"

echo "[Unit]
Description=Tomcat 9 servlet container
After=network.target

[Service]
Type=forking

User=tomcat
Group=tomcat

Environment=\"JAVA_HOME=/usr/lib/jvm/jre\"
Environment=\"JAVA_OPTS=-Djava.security.egd=file:///dev/urandom\"

Environment=\"CATALINA_BASE=/usr/share/tomcat\"
Environment=\"CATALINA_HOME=/usr/share/tomcat\"
Environment=\"CATALINA_PID=/var/run/tomcat/tomcat.pid\"
Environment=\"CATALINA_OPTS=-Xms2048M -Xmx8192M -server -XX:+UseParallelGC\"

ExecStart=/usr/share/tomcat/bin/startup.sh
ExecStop=/usr/share/tomcat/bin/shutdown.sh

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/tomcat.service

systemctl daemon-reload

echo "--------------------------------------------------"
echo "Creating Digital CSR for $LONG_HOST"
echo "--------------------------------------------------"
mkdir $OPENSSL_CERT_DIR

echo "[req]
default_bits             = 4096
distinguished_name       = req_distinguished_name
req_extensions           = req_ext
prompt                   = no

[req_distinguished_name]
0.countryName            = US
0.stateOrProvinceName    = CT
0.localityName           = Storrs
0.organizationName       = UConn
0.organizationalUnitName = ITS

commonName               = $LONG_HOST
emailAddress             = helpcenter@uconn.edu

[req_ext]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = $LONG_HOST
DNS.2 = $SHORT_HOST.its.uconn.edu
DNS.4 = $SHORT_HOST.grove.ad.uconn.edu" > $OPENSSL_CONFIG

$OPENSSL req -new -config $OPENSSL_CONFIG -keyout $CERT_KEY -out $CERT_REQ -nodes
echo "--------------------------------------------------"
echo "Go get yourself some certificates"
echo "--------------------------------------------------"



# Update Timezone & Time Servers
echo "--------------------------------------------------"
echo "Configuring timezone and setting NTP Servers"
echo "--------------------------------------------------"
timedatectl set-timezone America/New_York
sed -i '/pool\ 2.rhel.pool.ntp.org\ iburst/i server\ time.uconn.edu\nserver\ time2.uconn.edu' /etc/chrony.conf
sed -i s/pool\ 2.rhel.pool.ntp.org\ iburst//g /etc/chrony.conf
systemctl restart chronyd.service


# Enable services at book time
echo "--------------------------------------------------"
echo "Setting Tomcat to start at Boot Time"
echo "--------------------------------------------------"
systemctl enable tomcat.service

# Setup the firewall
echo "--------------------------------------------------"
echo "Configuring Bas Firewall for HTTP & HTTPS"
echo "--------------------------------------------------"
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
# Cockpit? Really? Because who wouldn't want a management gui on a server for pwning?
firewall-cmd --permanent --remove-service=cockpit
firewall-cmd --reload