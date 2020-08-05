# Install Postgresql and Data Generator

##  The goal of this repo is automate the install of Postgresql and Data Generator

## Notes:
*  Pgadmin4 will be installed but the below steps are required to complete the setup from the cli.
*  After you ssh into the node run these steps.

```
sudo -i
yum install -y git
cd ~
git clone https://github.com/tlepple/datagen_postgres.git

# change to cloned repo directory
cd /root/datagen_postgres/provider/aws

# run the setup
. setup.sh
```

### Pgadmin4

```
#  run user setup
python3 /usr/lib/python3.6/site-packages/pgadmin4-web/setup.py


Email address: admin@example.com 
Password: Admin1234
Retype password: Admin1234

#  Access from browser
http://<public ip host>/pgadmin4


