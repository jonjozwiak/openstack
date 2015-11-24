#!/bin/bash
###############################################################################
# This script is used to write some hieradata for use in the puppet run
###############################################################################

TROVEPW=$(uuidgen | sha1sum | awk '{print $1}')

cat << EOF >> /home/stack/templates/puppet/hieradata/controller.yaml
# Trove config data
trove::nova_proxy_admin_user: trove
trove::nova_proxy_admin_pass: <ENTER PASSWORD HERE>
trove::nova_proxy_admin_tenant_name: service
trove::rabbit_userid: guest
trove::rabbit_password: guest
### Trove API
trove::api::keystone_tenant: 'service'
trove::api::keystone_user: trove
trove::api::keystone_password: < ENTER PASSWORD >
### Trove Keystone Auth
trove::keystone::auth::region: regionOne
trove::keystone::auth::tenant: service
# Generate password for below: uuidgen | sha1sum | awk '{print $1}'
trove::keystone::auth::password: <ENTER PASSWORD HERE>
# Trove database.yaml
trove::db::mysql::user: trove
trove::db::mysql::password: <ENTER PASSWORD HERE>
trove::db::mysql::dbname: trove

EOF
