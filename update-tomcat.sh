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
SERVER_ADMINS="chris@uconn.edu" # kevin.r.brown@uconn.edu dylan.marquis@uconn.edu"
# START_TLS="-S smtp-use-starttls"
SENDER="$HOSTNAME@uconn.edu"

TOMCAT_CURRENT=`java -classpath /opt/tomcat9/lib/catalina.jar org.apache.catalina.util.ServerInfo |grep "Server version" |cut -f 2 -d \/`
TOMCAT_LATEST=`curl -s https://downloads.apache.org/tomcat/tomcat-9/ |grep v9 | cut -f 6 -d \> | cut -f 1 -d \/ |cut -f 2 -d \"`

TOMCAT_VERSION=`echo $TOMCAT_LATEST | cut -f 2 -d v`
TOMCAT_WORKING_DIR="/opt/tomcat9"
TMP_TOMCAT="/tmp/apache-tomcat-$TOMCAT_VERSION.tar.gz"
TMP_SHASUM="/tmp/apache-tomcat-$TOMCAT_VERSION.tar.gz.sha512"

TOMCAT_BIN="https://downloads.apache.org/tomcat/tomcat-9/$TOMCAT_LATEST/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz"
TOMCAT_SHA="https://downloads.apache.org/tomcat/tomcat-9/$TOMCAT_LATEST/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz.sha512"

# We need to send notifications if we have a failure of some kind.
# If for some reason ssmtp is not installed we are going to do that
# now and setup the error messages.
MAILX_CHECKSUM_FAILED_SUBJECT="Tomcat Upgrade: Checksum failure"
MAILX_CHECKSUM_FAILED="Subject: Tomcat SHA Checksum failure\nThe system was unable to upgrade Tomcat properly. There was a mismatch of SHA512 sums from the downloaded file and expected SHA sum. Please login to $HOSTNAME check the system.\n"

MAILX_UPGRADE_FAILED_SUBJECT="Tomcat Upgrade: Upgrade failure"
MAILX_UPGRADE_FAILED="Subject: Tomcat Upgrade Failed\nThe system was unable to upgrade Tomcat properly. Please login to $HOSTNAME check the system.\n"
MAILX="/usr/bin/mailx"

if [ ! -f "/usr/bin/mailx" ]; then
	yum -y mailx
fi


if [ "$TOMCAT_CURRENT" != "$TOMCAT_VERSION" ]; then
	echo "Our Tomcat: $TOMCAT_CURRENT, Latest Release: $TOMCAT_LATEST"
	echo "Downloading Tomcat: $TOMCAT_LATEST..."
	curl $TOMCAT_BIN -o $TMP_TOMCAT
	curl $TOMCAT_SHA -o $TMP_SHASUM
	SHA_SUM=`sha512sum $TMP_TOMCAT`
	ACTUAL_SUM=`cat $TMP_SHASUM`

	if [ "$SHA_SUM" == "$ACTUAL_SUM" ]; then
		echo "SHA sums do not match. Exiting..."
		# echo "$MAILX_CHECKSUM_FAILED" | $MAILX -v -r "$SENDER" -s "$MAILX_CHECKSUM_FAILED_SUBJECT" $START_TLS -S smtp="$MAIL_SERVER" "$SERVER_ADMINS"
		exit 1
	fi

	echo "Done!"
	echo "Stopping CAS..."
	systemctl stop tomcat.service
	echo "Done!"

	echo "Starting Upgrade Process..."
	tar -zxf $TMP_TOMCAT -C $TOMCAT_WORKING_DIR --strip-components 1
	chown tomcat.tomcat $TOMCAT_WORKING_DIR
	chown tomcat.tomcat $TOMCAT_WORKING_DIR/* -R
	echo "Upgrade Complete!"

	INSTALLED_VERSION=`java -classpath /opt/tomcat9/lib/catalina.jar org.apache.catalina.util.ServerInfo |grep "Server version" |cut -f 2 -d \/`

	if [ "$INSTALLED_VERSION" = "$TOMCAT_VERSION" ]; then
		echo "Upgrade version mismatch. Something went wrong."
		# echo "$MAILX_UPGRADE_FAILED" | $MAILX -v -r "$SENDER" -s "$MAILX_UPGRADE_FAILED_SUBJECT" $START_TLS -S smtp="$MAIL_SERVER" "$SERVER_ADMINS"
		exit 1
	fi

	echo "Restarting CAS..."
	systemctl start tomcat.service
	echo "Done!"
else
	echo "No Upgrade needed [$TOMCAT_CURRENT:$TOMCAT_VERSION] [CURRENT:LATEST]"
fi
