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

TOMCAT_VERSION_FILE="/opt/current_tomcat"
TOMCAT_CURRENT=`cat $TOMCAT_VERSION_FILE`
TOMCAT_LATEST=`curl -s http://apache.mirrors.hoobly.com/tomcat/tomcat-9/ |grep v9 | cut -f 3 -d \> | cut -f 1 -d \/`
TOMCAT_VERSION=`echo $TOMCAT_LATEST | cut -f 2 -d v`
TOMCAT_WORKING_DIR="/opt/tomcat9"
TMP_TOMCAT="/tmp/apache-tomcat-$TOMCAT_VERSION.tar.gz"

if [ "$TOMCAT_CURRENT" -ne "$TOMCAT_LATEST" ];	
	echo "Our Tomcat: $TOMCAT_CURRENT, Latest Release: $TOMCAT_LATEST"
	echo "Downloading Tomcat: $TOMCAT_LATEST..."
	URL = "http://apache.mirrors.hoobly.com/tomcat/tomcat-9/$TOMCAT_LATEST/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz"
	curl $URL -o $TMP_TOMCAT
	echo "Done!"
	echo "Stopping CAS..."
	systemctl stop tomcat9
	echo "Done!"
	echo "Starting Upgrade Process..."
	tar -zxf $TMP_TOMCAT -C $TOMCAT_WORKING_DIR --strip-components 1
	chown tomcat.tomcat $TOMCAT_WORKING_DIR
	chown tomcat.tomcat $TOMCAT_WORKING_DIR/* -R
	echo "Upgrade Complete!"
	echo "Restarting CAS..."
	systemctl start tomcat9
	echo "Done!"
fi