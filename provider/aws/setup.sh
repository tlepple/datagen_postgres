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

PRIVATE_IP=`ip route get 1 | awk '{print $NF;exit}'`
PUBLIC_IP=`curl https://api.ipify.org/`

###########################################################################################################
#  Setup some prereqs
###########################################################################################################

if [ getenforce != Disabled ]
then  setenforce 0;
fi

sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
sed -i 's/SELINUX=permissive/SELINUX=disabled/g' /etc/selinux/config

ln -sf /usr/share/zoneinfo/$LOCAL_TIMEZONE /etc/localtime

## turn off Transparent Huge pages
echo never > /sys/kernel/mm/transparent_hugepage/defrag
echo never > /sys/kernel/mm/transparent_hugepage/enabled


#  turn off swappiness
sysctl vm.swappiness=10

echo "vm.swappiness = 10" >> /etc/sysctl.conf

yum install -y epel-release

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


#########################################################################################
#########################################################################################

#########################################################################################
#########################################################################################
yum install -y pgadmin4

# ensure things start on boot
systemctl start httpd &&  systemctl enable httpd

#cp /etc/httpd/conf.d/pgadmin4.conf.sample /etc/httpd/conf.d/pgadmin4.conf
cat <<EOF > /etc/httpd/conf.d/pgadmin4.conf
<VirtualHost *:80>
LoadModule wsgi_module modules/pgadmin4-python3-mod_wsgi.so
WSGIDaemonProcess pgadmin processes=1 threads=25
WSGIScriptAlias /pgadmin4 /usr/lib/python3.6/site-packages/pgadmin4-web/pgAdmin4.wsgi

<Directory /usr/lib/python3.6/site-packages/pgadmin4-web/>
        WSGIProcessGroup pgadmin
        WSGIApplicationGroup %{GLOBAL}
        <IfModule mod_authz_core.c>
                # Apache 2.4
                Require all granted
        </IfModule>
        <IfModule !mod_authz_core.c>
                # Apache 2.2
                Order Deny,Allow
                Deny from All
                Allow from 127.0.0.1, 205.201.98.48, 173.3.101.154, ${PUBLIC_IP}, ${PRIVATE_IP}
                Allow from ::1
        </IfModule>
</Directory>
</VirtualHost>
EOF
# Add some variables to config_distro.py
echo "SQLITE_PATH = '/var/lib/pgadmin4/pgadmin4.db'" >> /usr/lib/python3.6/site-packages/pgadmin4-web/config_distro.py
echo "SESSION_DB_PATH = '/var/lib/pgadmin4/sessions'" >> /usr/lib/python3.6/site-packages/pgadmin4-web/config_distro.py
echo "STORAGE_DIR = '/var/lib/pgadmin4/storage'" >> /usr/lib/python3.6/site-packages/pgadmin4-web/config_distro.py
echo "LOG_FILE = '/var/log/pgadmin4/pgadmin4.log'" >> /usr/lib/python3.6/site-packages/pgadmin4-web/config_distro.py

# create directories:
mkdir -p /var/lib/pgadmin4/ /var/log/pgadmin4/
chown -R apache:apache /var/log/pgadmin4
chown -R apache:apache /var/lib/pgadmin4

# restart webserver
systemctl restart httpd

# after restart ensure permission still good
chown -R apache:apache /var/log/pgadmin4
chown -R apache:apache /var/lib/pgadmin4

#add postgres to path
sed -i '/^PATH=/ s/$/:\/usr\/pgsql-9.6\/bin/' ~/.bash_profile
source ~/.bash_profile

#########################################################################################
#########################################################################################

# install needed python packages
python3 -m pip install uuid
python3 -m pip install kafka-python
python3 -m pip install simplejson
python3 -m pip install faker
python3 -m pip install boto3

pip3 install psycopg2-binary

#########################################################################################
#########################################################################################
#  echo these variables into pgadmin4 setup
export pgadmin_email="admin@example.com"
export pgadmin_pwd="admin@example.com"

#########################################################################################
#########################################################################################
# create directories:
#########################################################################################
#########################################################################################

mkdir -p ~/datagen
cd ~/datagen

#########################################################################################
# python data generator files
#########################################################################################
cat <<EOF > ~/datagen/datagenerator.py
import time 
import collections
import datetime
from decimal import Decimal
from random import randrange, randint, sample
import sys
class DataGenerator():
	#  DataGenerator 
	def __init__(self):
	    #  comments
	    self.z = 0
	def fake_person_generator(self, startkey, iterateval, f):
	    self.startkey = startkey
	    self.iterateval = iterateval
	    self.f = f
	    endkey = startkey + iterateval
	    for x in range(startkey, endkey):
	    	yield {'last_name': f.last_name(),
	    		'first_name': f.first_name(),
	    		'street_address': f.street_address(),
	    		'city': f.city(),
	    		'state': f.state_abbr(),
	    		'zip_code': f.postcode(),
	    		'email': f.email(),
	    		'home_phone': f.phone_number(),
	    		'mobile': f.phone_number(),
	    		'ssn': f.ssn(),
	    		'job_title': f.job(),
	    		'create_date': (f.date_time_between(start_date="-60d", end_date="-30d", tzinfo=None)).strftime('%Y-%m-%d %H:%M:%S'),
	    		'cust_id': x}
	def fake_txn_generator(self, txnsKey, txniKey, fake):
	    self.txnsKey = txnsKey
	    self.txniKey = txniKey
	    self.fake = fake
	
	    txnendKey = txnsKey + txniKey
	    for x in range(txnsKey, txnendKey):
	    	for i in range(1,randrange(1,7,1)):
	    		yield {'transact_id': fake.uuid4(),
	    			'category': fake.safe_color_name(),
	    			'barcode': fake.ean13(),
	    			'item_desc': fake.sentence(nb_words=5, variable_nb_words=True, ext_word_list=None),
	    			'amount': fake.pyfloat(left_digits=2, right_digits=2, positive=True),
	    			'transaction_date': (fake.date_time_between(start_date="-29d", end_date="now", tzinfo=None)).strftime('%Y-%m-%d %H:%M:%S'),
	    			'cust_id': x}
EOF

##################################################################################
#  create python script to spool data generator data to a csv file
##################################################################################
cat <<EOF > ~/datagen/csv_dg.py
import datetime
import time
from faker import Faker
import sys
import csv
import boto3
import os
import shutil
from datagenerator import DataGenerator
#########################################################################################
#       Define variables
#########################################################################################
#bname_in = sys.argv[3]
dg = DataGenerator()
fake = Faker() # <--- Don't Forgot this
now = datetime.datetime.now()
dir_location = "/tmp/"
target_location = "/home/nifi/inbound/"
prefix = 'customer_csv'
#tname = now.strftime("%Y-%m-%d-%H:%M:%S")
tname = now.strftime("%Y-%m-%d-%H-%M-%S")
suffix = '.txt'
fname = dir_location + prefix + tname + suffix
s3bucket_location = 'data_gen/customer/' + prefix + tname + suffix
s3 = boto3.resource('s3')
#bucket_name = bname_in
bucket_name=${S3_BNAME}
#object_name = fname
dest = target_location + prefix + tname + suffix
startKey = int(sys.argv[1])
iterateVal = int(sys.argv[2])
#########################################################################################
#       Code execution below
#########################################################################################
#  open file to write csv
with open(fname, 'w', newline='') as csvfile:
#       Create a header row of data
        fpgheader = dg.fake_person_generator(1, 1, fake)
        for h in fpgheader:
                writer = csv.DictWriter(csvfile, fieldnames=h.keys() , delimiter='|', quotechar='"', quoting=csv.QUOTE_NONNUMERIC)
                writer.writeheader()
#       Create the data rows
        fpg = dg.fake_person_generator(startKey, iterateVal, fake)
        for person in fpg:
                writer = csv.DictWriter(csvfile, fieldnames=person.keys() , delimiter='|', quotechar='"', quoting=csv.QUOTE_NONNUMERIC)
                writer.writerow(person)
csvfile.close()
#Upload to S3
#s3.meta.client.upload_file(fname, bucket_name, s3bucket_location)
# move the file to a nifi in directory
shutil.move(fname,dest)
EOF

##################################################################################
#  create python script to send data to postgres script
##################################################################################
cat <<EOF > ~/datagen/pg_upsert_dg.py
############################################
# file contents:
############################################

from __future__ import print_function
from faker import Faker
from datagenerator import DataGenerator
import simplejson
import sys
import psycopg2

#########################################################################################
#	Define variables
#########################################################################################
dg = DataGenerator()
fake = Faker() # <--- Don't Forgot this
startKey = int(sys.argv[1])
iterateVal = int(sys.argv[2])

# functions to display errors
def printf (format,*args):
	sys.stdout.write (format % args)

def printException (exception):
	error, = exception.args
	printf("Error code = %s\n",error.code);
	printf("Error message = %s\n",error.message);

def myconverter(obj):
	if isinstance(obj, (datetime.datetime)):
		return obj.__str__()
#########################################################################################
#	Code execution below
#########################################################################################

try:
    try:
        conn = psycopg2.connect(host="${PRIVATE_IP}",database="datagen", user="datagen", password="supersecret1")
        print("Connection Established")

    except psycopg2.Error as exception:
        printf ('Failed to connect to database')
        printException (exception)
        exit (1)

    cursor = conn.cursor()

    try:
        fpg = dg.fake_person_generator(startKey, iterateVal, fake)
        for person in fpg:
#            print(simplejson.dumps(person, ensure_ascii=False, default = myconverter))
            json_out = simplejson.dumps(person, ensure_ascii=False, default = myconverter)
            print(json_out)
            insert_stmt = "SELECT datagen.insert_from_json('" + json_out +"');"

            cursor.execute(insert_stmt)
        print("Records inserted successfully")

    except psycopg2.Error as exception:
        printf ('Failed to insert\n')
        printException (exception)
        exit (1)

    finally:
        if(conn):
            conn.commit()
            cursor.close()
            conn.close()
            print("PostgreSQL connection is closed")

except (Exception, psycopg2.Error) as error:
    print("Something else went wrong...\n", error)

finally:
    print("script complete!")
EOF
##################################################################################
##################################################################################
