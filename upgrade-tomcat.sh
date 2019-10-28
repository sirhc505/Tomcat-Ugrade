#!/bin/bash
####################################################################################################################
# upgrade-tomcat.sh
####################################################################################################################
# Purpose:
#	Red Hat decided to stop support for Tomcat in RHEL 8 and later. However there are a significant number of
#	installations of Tomcat already. The purpose of this script is to pull down the latest version 9 edition
#	of Tomcat and upgrade it. 
####################################################################################################################
# Created by:
#	Christopher Tarricone
#	chris at uconn dot edu
#	10/25/2019
####################################################################################################################
# License: 
#	GNU General Public License
#	https://www.gnu.org/licenses/gpl-3.0.md
####################################################################################################################

HOSTNAME=`hostname -f`
MAIL_SERVER="smtp.uconn.edu"
SERVER_ADMIN="chris@uconn.edu"
SENDMAIL_UPGRADE_FAILED="/etc/ssmtp/upgrade_failed.txt"
SENDMAIL_CHECKSUM_FAILED="/etc/ssmtp/checksum_failure.txt"

TOMCAT_CURRENT=`java -classpath /opt/tomcat9/lib/catalina.jar org.apache.catalina.util.ServerInfo |grep "Server version" |cut -f 2 -d \/`
TOMCAT_LATEST=`curl -s https://www.apache.org/dist/tomcat/tomcat-9/ |grep v9 | cut -f 3 -d \> | cut -f 1 -d \/`

TOMCAT_VERSION=`echo $TOMCAT_LATEST | cut -f 2 -d v`
TOMCAT_WORKING_DIR="/opt/tomcat9"
TMP_TOMCAT="/tmp/apache-tomcat-$TOMCAT_VERSION.tar.gz"
TMP_SHASUM="/tmp/apache-tomcat-$TOMCAT_VERSION.tar.gz.sha512"

TOMCAT_BIN="https://www.apache.org/dist/tomcat/tomcat-9/$TOMCAT_LATEST/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz"
TOMCAT_SHA="https://www.apache.org/dist/tomcat/tomcat-9/$TOMCAT_LATEST/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz.sha512"

# We need to send notifications if we have a failure of some kind.
# If for some reason ssmtp is not installed we are going to do that
# now and setup the error messages.
if [ ! -f "/etc/ssmtp/ssmtp.conf" ]; then
	yum -y install ssmtp
	sed -i s/root=postmaster/root=$SERVER_ADMIN/g /etc/ssmtp/ssmtp.conf
	sed -i s/mailhub=mail/mailhub=$MAIL_SERVER/g /etc/ssmtp/ssmtp.conf
	sed -i s/\#Hostname=/Hostname=$HOSTNAME/g /etc/ssmtp/ssmtp.conf

	echo -e "Subject: Tomcat Upgrade Failed\nThe system was unable to upgrade Tomcat properly. Please login to $HOSTNAME check the system.\n" > $SENDMAIL_UPGRADE_FAILED
	echo -e "Subject: Tomcat SHA Checksum failure\nThe system was unable to upgrade Tomcat properly. There was a mismatch of SHA512 sums from the downloaded file and expected SHA sum. Please login to $HOSTNAME check the system.\n" > $SENDMAIL_CHECKSUM_FAILED
fi


if [ "$TOMCAT_CURRENT" != "$TOMCAT_VERSION" ]; then
	echo "Our Tomcat: $TOMCAT_CURRENT, Latest Release: $TOMCAT_LATEST"
	echo "Downloading Tomcat: $TOMCAT_LATEST..."
	curl $TOMCAT_BIN -o $TMP_TOMCAT
	curl $TOMCAT_SHA -o $TMP_SHASUM
	SHA_SUM = `sha512sum $TMP_TOMCAT`
	ACTUAL_SUM = `cat $TMP_SHASUM`

	if [ "$SHA_SUM" == "$ACTUAL_SUM" ]; then
		echo "SHA sums do not match. Exiting..."
		/usr/sbin/sendmail $SERVER_ADMIN < $SENDMAIL_CHECKSUM_FAILED
		exit 1
	fi

	echo "Done!"
	echo "Stopping CAS..."
	systemctl stop tomcat9
	echo "Done!"

	echo "Starting Upgrade Process..."
	tar -zxf $TMP_TOMCAT -C $TOMCAT_WORKING_DIR --strip-components 1
	chown tomcat.tomcat $TOMCAT_WORKING_DIR
	chown tomcat.tomcat $TOMCAT_WORKING_DIR/* -R
	echo "Upgrade Complete!"

	INSTALLED_VERSION=`java -classpath /opt/tomcat9/lib/catalina.jar org.apache.catalina.util.ServerInfo |grep "Server version" |cut -f 2 -d \/`

	if [ "$INSTALLED_VERSION" == "$TOMCAT_VERSION" ]; then
		echo "Upgrade version mismatch. Something went wrong."
		/usr/sbin/sendmail $SERVER_ADMIN < $SENDMAIL_UPGRADE_FAILED
		exit 1
	fi

	echo "Restarting CAS..."
	systemctl start tomcat9
	echo "Done!"
else
	echo "No Upgrade needed [$TOMCAT_CURRENT:$TOMCAT_VERSION] [CURRENT:LATEST]"
fi