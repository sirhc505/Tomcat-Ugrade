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

# We need to connect to Apache's website and find what the current version of Tomcat is
TOMCAT_LATEST=`curl -s $BASE_URL/ |grep v9  | sed 's:<a href="\(v9.*\)">.*</a>:\1:' | cut -f2 -d v | cut -f 1 -d \/`
TOMCAT_VERSION=`echo $TOMCAT_LATEST | cut -f 2 -d v`
TOMCAT_WORKING_DIR="/opt/tomcat9"
TMP_TOMCAT="/tmp/apache-tomcat-$TOMCAT_VERSION.tar.gz"
TMP_SHASUM="/tmp/apache-tomcat-$TOMCAT_VERSION.tar.gz.sha512"

TOMCAT_BIN="$BASE_URL/$TOMCAT_LATEST/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz"
TOMCAT_SHA="$BASE_URL/$TOMCAT_LATEST/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz.sha512"

# Apache & SSL Variables
LONG_HOST=`hostname -f`
SHORT_HOST=`hostname -s`
OPENSSL_CERT_DIR="/root/certs"
OPENSSL_CONFIG="$OPENSSL_CERT_DIR/openssl.cnf"
CERT_REQ="$OPENSSL_CERT_DIR/server.csr"
CERT_KEY="$OPENSSL_CERT_DIR/server.key"

yum -y install httpd apr apr-devel httpd-devel libcurl-devel pcre-devel openssl-devel pam-devel java-11-openjdk mod_ssl

mkdir $TOMCAT_WORKING_DIR

$USERADD -d $TOMCAT_WORKING_DIR -c 'Tomcat Service Account' $TOMCAT_USER

# Download Tomcat
$CURL $TOMCAT_BIN -o $TMP_TOMCAT
$CURL $TOMCAT_SHA -o $TMP_SHASUM

SHA_SUM=`sha512sum $TMP_TOMCAT`
ACTUAL_SUM=`cat $TMP_SHASUM`

tar -zxf $TMP_TOMCAT -C $TOMCAT_WORKING_DIR --strip-components 1
chown tomcat.tomcat $TOMCAT_WORKING_DIR
chown tomcat.tomcat $TOMCAT_WORKING_DIR/* -R

# Make needed Directories
mkdir /etc/tomcat/
mkdir -p /etc/tomcat/Catalina/localhost/
mkdir /usr/libexec/tomcat/
mkdir /var/lib/tomcat /var/lib/tomcats
mkdir /usr/share/tomcat
mkdir -p /var/log/tomcat
mkdir -p /var/lib/tomcat/webapps
mkdir -p /var/cache/tomcat/work
mkdir -p /etc/pki/shib/

# Create symlinks to simulate an RPM based installation
ln -s /opt/tomcat9/lib /usr/share/tomcat/lib
ln -s /opt/tomcat9/bin /usr/share/tomcat/bin
ln -s /etc/tomcat /usr/share/tomcat/conf
ln -s /var/log/tomcat /usr/share/tomcat/logs
ln -s /var/lib/tomcat/webapps /usr/share/tomcat/webapps
ln -s /var/cache/tomcat/work /usr/share/tomcat/work
ln -s /opt/shibboleth-idp/war/idp.war /var/lib/tomcat/webapps/idp.war

# Copy configuration files
cp configs/tomcat.conf /etc/tomcat/
cp /opt/tomcat9/conf/* /etc/tomcat/
cp libexec/* /usr/libexec/tomcat/

# Localize the configuration file
sed -i s/ServerAlias\ shib3.uits.uconn.edu/ServerAlias\ $LONG_HOST/g /etc/httpd/conf.d/shibboleth.uconn.edu.conf

# Set folder ownership
chown tomcat.tomcat -R /etc/tomcat/*
chown root.tomcat /var/lib/tomcat /var/lib/tomcats
chown tomcat.tomcat /var/log/tomcat
chown tomcat.tomcat /var/lib/tomcat /var/lib/tomcat/* /var/cache/tomcat /var/cache/tomcat/* /etc/tomcat /etc/tomcat/*

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
DNS.1 = $SHORT_HOST.its.uconn.edu
DNS.2 = shibboleth.uconn.edu
DNS.3 = dev.shibboleth.uconn.edu" > $OPENSSL_CONFIG

$OPENSSL req -new -config $OPENSSL_CONFIG -keyout $CERT_KEY -out $CERT_REQ -nodes

# Update Timezone & Time Servers
timedatectl set-timezone America/New_York
sed -i '/pool\ 2.rhel.pool.ntp.org\ iburst/i server\ time.uconn.edu\nserver\ time2.uconn.edu' /etc/chrony.conf
sed -i s/pool\ 2.rhel.pool.ntp.org\ iburst//g /etc/chrony.conf
systemctl restart chronyd.service

echo "Go get yourself some certificates"

echo "
################################################################################
# Once you have a real certificate, save it as server.crt                      #
# Create a file incommon.crt which is the intermediate/root certs for InCommon #
# Then:                                                                        #
# cp server.crt server.key incommon.crt /etc/pki/shib/                         #
# systemctl start httpd.service                                                #
# systemctl start tomcat.service                                               #
################################################################################
"

# Create redirect page
echo "<!DOCTYPE html>
<html>
   <head>
      <title>Shibboleth Redirect</title>
      <meta http-equiv=\"refresh\" content=\"0;url=/idp/\" />
   </head>
   <body>
      <p>Redirecting... If redirect does not happen <a href=\"/idp/\">click here</a></p>
   </body>
</html>" > /var/www/html/index.html

# Enable services at book time
systemctl enable httpd.service
systemctl enable tomcat.service

# Setup the firewall
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
# Cockpit? Really? Because who wouldn't want a management gui on a server for pwning?
firewall-cmd --permanent --remove-service=cockpit
firewall-cmd --reload