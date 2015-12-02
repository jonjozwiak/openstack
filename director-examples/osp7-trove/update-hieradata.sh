#!/bin/bash
###############################################################################
# This script is used to write some hieradata for use in the puppet run
###############################################################################

TROVEPW=$(uuidgen | sha1sum | awk '{print $1}')

cat << EOF >> /home/stack/templates/puppet/hieradata/controller.yaml
# Trove config data
trove::nova_proxy_admin_user: trove
trove::nova_proxy_admin_pass: $TROVEPW
trove::nova_proxy_admin_tenant_name: service
trove::rabbit_userid: guest
trove::rabbit_password: guest
### Trove API
trove::api::keystone_tenant: 'service'
trove::api::keystone_user: trove
trove::api::keystone_password: $TROVEPW
### Trove Keystone Auth
trove::keystone::auth::region: regionOne
trove::keystone::auth::tenant: service
trove::keystone::auth::password: $TROVEPW
# Trove database.yaml
trove::db::mysql::user: trove
trove::db::mysql::password: $TROVEPW
trove::db::mysql::dbname: trove
trove::database_connection: mysql://trove:$TROVEPW@%{hiera('mysql_vip')}/trove
EOF
