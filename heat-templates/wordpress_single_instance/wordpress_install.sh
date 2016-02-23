#!/bin/bash -v

# CloudFormation Helper Function
function error_exit  {
  #cfn-signal -e 1 -r \"$1\" cfnwaithandle
  exit 1
}

#cfn-init -s awsstackname -r WebServer --region awsregion || error_exit 'Failed to run cfn-init'

# Add local yum repository or RHN register if RHEL?

yum -y install mariadb mariadb-server mariadb-devel mariadb-libs httpd php php-mysql || error_exit 'Failed to run cfn-init'
mkdir -p /var/log/mariadb
touch /var/log/mariadb/mariadb.log
chown mysql:mysql /var/log/mariadb/mariadb.log
systemctl start mariadb
systemctl enable mariadb

# Setup MySQL root password and create a user
mysqladmin -u root password db_rootpassword || error_exit 'Failed to run cfn-init'

cat << EOF | mysql -u root --password=db_rootpassword || error_exit 'Failed to run cfn-init'

CREATE DATABASE db_name;
GRANT ALL PRIVILEGES ON db_name.* TO "db_username"@"localhost"
IDENTIFIED BY "db_password";
FLUSH PRIVILEGES;
EXIT
EOF

# Ensure name resolution
echo "nameserver 8.8.8.8" >> /etc/resolv.conf

# Get wordpress
cd /var/www/html
curl -O https://wordpress.org/latest.tar.gz
tar xzf latest.tar.gz
#curl -O http://192.168.122.1/wordpress-3.9.1.tar.gz
#tar xzf wordpress-3.9.1.tar.gz
chown -R apache:apache wordpress
chmod -R 755 wordpress

# Add wordpress configuration
cd /var/www/html/wordpress
cp -p wp-config-sample.php wp-config.php
restorecon -v wp-config.php
sed -i "s/database_name_here/db_name/" wp-config.php
sed -i "s/username_here/db_username/" wp-config.php
sed -i "s/password_here/db_password/" wp-config.php

# Add httpd configuration
cat << EOF >> /etc/httpd/conf.d/wordpress.conf
<VirtualHost *:80>
  ServerAdmin webmaster@redhat.com
  DocumentRoot /var/www/html/wordpress
  ServerName wordpress.redhat.com
  <Directory /var/www/html/wordpress>
     Allowoverride All
  </Directory>
  ErrorLog logs/wordpress.redhat.com-error_log
  CustomLog logs/wordpress.redhat.com-access_log combined
</VirtualHost>
EOF

### Add something here for iptables and firewalld if needed 
#iptables -I INPUT 1 -p tcp --dport 80 -j ACCEPT
#iptables -I INPUT 1 -p tcp --dport 443 -j ACCEPT
#service iptables save
#service iptables reload

systemctl enable httpd; systemctl start httpd

# CloudFormation - Signal Success (Exit 0)
cfn-signal -e 0 -r "WordPress setup complete" 'cfnwaithandle'

