#!/bin/bash

###########################################################################################################
# import parameters and utility functions 
###########################################################################################################
. utils.sh

###########################################################################################################
# install aws cli
###########################################################################################################
install_aws_cli

###########################################################################################################
# Set some variables
###########################################################################################################
#postgres info
PG_REPO_URL="https://yum.postgresql.org/9.6/redhat/rhel-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm"

PG_HOME_DIR="/var/lib/pgsql/9.6"

#LOCAL_TIMEZONE="America/Los_Angeles"
#LOCAL_TIMEZONE="Europe/London"
#LOCAL_TIMEZONE="America/New_York"
LOCAL_TIMEZONE="America/Chicago"

###########################################################################################################
#  Setup some prereqs
###########################################################################################################

if [ getenforce != Disabled ]
then  setenforce 0;
fi

ln -sf /usr/share/zoneinfo/$LOCAL_TIMEZONE /etc/localtime

## turn off Transparent Huge pages
echo never > /sys/kernel/mm/transparent_hugepage/defrag
echo never > /sys/kernel/mm/transparent_hugepage/enabled


#  turn off swappiness
sysctl vm.swappiness=10

echo "vm.swappiness = 10" >> /etc/sysctl.conf

###########################################################################################################
## Install Postgresql repo for Redhat
###########################################################################################################
yum -y install $PG_REPO_URL

###########################################################################################################
## Install PG 9.6
###########################################################################################################
yum -y install postgresql96-server postgresql96-contrib postgresql96 postgresql-jdbc*

###########################################################################################################
## setup the jdbc connetor
###########################################################################################################
cp /usr/share/java/postgresql-jdbc.jar /usr/share/java/postgresql-connector-java.jar
chmod 644 /usr/share/java/postgresql-connector-java.jar

echo 'LC_ALL="en_US.UTF-8"' >> /etc/locale.conf

###########################################################################################################
## Initialize Postgresql
###########################################################################################################
/usr/pgsql-9.6/bin/postgresql96-setup initdb


## Start Postgres service and config it for restart on reboot
systemctl enable postgresql-9.6
systemctl start postgresql-9.6

## Allow listeners from any host
sed -e 's,#listen_addresses = \x27localhost\x27,listen_addresses = \x27*\x27,g' -i $PG_HOME_DIR/data/postgresql.conf

## Increase number of connections
sed -e 's,max_connections = 100,max_connections = 300,g' -i  $PG_HOME_DIR/data/postgresql.conf

## Save the original & replace with a new pg_hba.conf
mv $PG_HOME_DIR/data/pg_hba.conf $PG_HOME_DIR/data/pg_hba.conf.orig

cat <<EOF > $PG_HOME_DIR/data/pg_hba.conf
  # TYPE  DATABASE        USER            ADDRESS                 METHOD
  local   all             all                                     peer
  host    datagen         datagen        0.0.0.0/0                md5
EOF

chown postgres:postgres $PG_HOME_DIR/data/pg_hba.conf
chmod 600 $PG_HOME_DIR/data/pg_hba.conf


## Restart Postgresql
systemctl restart postgresql-9.6

###########################################################################################################
## Create a DDL file for all our Db’s
###########################################################################################################

cat <<EOF > ~/create_ddl_c703.sql
CREATE ROLE datagen LOGIN PASSWORD 'supersecret1';
CREATE DATABASE datagen OWNER datagen ENCODING 'UTF-8';
EOF

###########################################################################################################
## Run the sql file to create the schema for all DB’s
###########################################################################################################
sudo -u postgres psql < ~/create_ddl_c703.sql


###########################################################################################################
#time issues for clock offset in aws	
###########################################################################################################
echo "setup clock offset issues for aws"
echo "server 169.254.169.123 prefer iburst minpoll 4 maxpoll 4" >> /etc/chrony.conf
systemctl restart chronyd


