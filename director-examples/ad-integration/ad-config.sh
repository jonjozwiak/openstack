#!/bin/bash
##########################################################################
# This script modifies the Keystone Identity Backend to Active Directory
# and implements Keystone v3
##########################################################################
set -eu
set -o pipefail


# Variables passed via Heat
varldapdomain="LDAP_DOMAIN" 	# Domain name i.e. EXAMPLE
varldapserver="LDAP_SERVER"	# ldaps://<fqdn>:636 # Comma separate for multiple
varldapuser="LDAP_USER"		# Account created for LDAP access
				# i.e. "CN=svc-openstack,CN=Users,DC=example,DC=com"
varldappassword="LDAP_PASSWORD" # Password for the service account
varsuf="SUFFIX"			# i.e. "DC=example,DC=com"
vartree="USER_TREE"		# i.e. "CN=Users,DC=example,DC=com"
vargenabled="ENABLED_GROUP"	# i.e. "CN=grp-openstack,CN=Users,DC=Users,DC=example,DC=com"
vargtree="GROUP_TREE"		# i.e. "CN=Groups,DC=example,DC=com"
vargroupfilter="GROUP_FILTER"	# i.e. "CN=grp-openstack,CN=Users,DC=Users,DC=example,DC=com"
varcertname="LDAPSCERTNAME"	# i.e. ds1.example.com.cer -- this is a DER-encoded x509 .cer
varcerturl="LDAPSCERTURL"	# i.e. http://<director prov IP>/ds1.example.com.cer


#### NOTE - Need to have a way to validate these variables!

####################
# Controller Nodes #
####################
function setup_controller {

  # Verify Port Access - Not certain if this works 
   # ldaps is port 636 
   # ldap is port 389
  # nc -v -i 5 -w 5 addc.lab.local 636 2> /dev/null 1> /dev/null
    ##  This will connect and then respond Ncat: Idle timeout expired (5000 ms). if all was successful.  But still exits with error code 1.
    ## wait 5 seconds, idle connection timeout 5 seconds
    ## With ldaps not running I was getting this:
    ## Ncat: Connection reset by peer.
  # Once it's running I get an idle connection... 
  # if [[ $? -ne 0 ]]; then
  # echo "ERROR: Cannot connect to LDAP server"
  # exit 1

  ### NOTE - ldapsearch needs openldap-clients package
  ### yum -y install openldap-clients
  # Test LDAP query 
  #ldapsearch \
  #    -x -h ldapserver.mydomain.com \
  #    -D "mywindowsuser@mydomain.com" \
  #    -W \
  #    -b "cn=users,dc=mydomain,dc=com" \
  #    -s sub "(cn=*)" cn mail sn

  # ldapsearch -x -H ldaps://addc.lab.local:636 -D "svc-ldap@lab.local" -W -b "CN=Users,DC=lab,DC=local" -s sub "(cn=*)" cn
  ### If you can't connect, add '-d 1 -v' to the ldapsearch to get more info 

  # Configure cert if LDAPS
  if [[ $(echo $varldapserver | grep ldaps | wc -l) -ne 0 ]]; then
    echo "INFO: ldaps specified.  Configuring Cert"
    # Configure the LDAPS certificate
    CERTTMPDIR=/root
    if [[ ! -f ${CERTTMPDIR}/${varcertname} ]]; then 
      # Get x509 cert (hosted on director web server)
      curl -o ${CERTTMPDIR}/${varcertname} ${varcerturl}

      PEMFILE="$(echo ${CERTTMPDIR}/${varcertname} | sed 's/.cer$//').pem"
      CRTFILE="$(echo ${CERTTMPDIR}/${varcertname} | sed 's/.cer$//').crt"
      CRTSHORTNAME="$(echo ${varcertname} | sed 's/.cer$//').crt"
   
      openssl x509 -inform der -in $varcert -out $PEMFILE
      cp $PEMFILE /etc/pki/ca-trust/source/anchors
      update-ca-trust
      openssl x509 -outform der -in $PEMFILE -out $CRTFILE
      cp $CRTFILE /etc/ssl/certs

      # Point openldap to it's correct certs directory 
      cp /etc/openldap/ldap.conf /etc/openldap/ldap.conf.$(date +%m%d%y%H%M)
      sed -i 's/^TLS_CACERTDIR.*/TLS_CACERTDiR \/etc\/openldap\/certs/' /etc/openldap/ldap.conf
    fi
  fi

  # Create overcloudrc_admin
  if [[ ! -f /root/overcloudrc_admin ]] ; then
    echo "INFO: Creating /root/overcloudrc_admin"
    AUTHURL=$(hiera nova::api::auth_uri | tr -d '\n')
    ADMINPASS=$(hiera admin_password | tr -d '\n')
    ADMINUSER=$(hiera heat::keystone::domain::keystone_admin | tr -d '\n')
    ADMINTENANT=$(hiera heat::keystone::domain::keystone_tenant | tr -d '\n')
    cat << EOF > /root/overcloudrc_admin 
export OS_USERNAME=$ADMINUSER
export OS_TENANT_NAME=$ADMINTENANT
export OS_AUTH_URL=$AUTHURL
export OS_PASSWORD=$ADMINPASS
EOF
  fi 

  # Create keystone v3 service & endpoints if they do not yet exist
  source /root/overcloudrc_admin
  KEYSTONEADMINVIP=$(hiera keystone_admin_api_vip | tr -d '\n')
  KEYSTONEPUBLICVIP=$(hiera tripleo::loadbalancer::public_virtual_ip | tr -d '\n')
  if [[ $(openstack endpoint show keystone | grep https | wc -l) -eq 0 ]]; then
    PROTO="http"
  else
    PROTO="https"
  fi
  if [[ $(openstack service list | grep identityv3 | wc -l) -eq 0 ]]; then
    echo "INFO: Creating identityv3 service"
    openstack service create --name keystonev3 --description "Keystone Identity Service v3" identityv3
  fi

  if [[ $(openstack endpoint list | grep identityv3 | wc -l) -eq 0 ]]; then
    echo "INFO: Creating identityv3 endpoint"
    REGION=$(openstack endpoint show identity -c region -f value)
    openstack endpoint create --publicurl "${PROTO}://${KEYSTONEPUBLICVIP}:5000/v3" --adminurl "${PROTO}://${KEYSTONEADMINVIP}:5000/v3" --internalurl "${PROTO}://${KEYSTONEADMINVIP}:5000/v3" --region $REGION keystonev3
  fi

  # Create overcloudrc_admin_v3
  if [[ ! -f /root/overcloudrc_admin_v3 ]] ; then
    echo "INFO: Creating /root/overcloudrc_admin_v3"
    AUTHURL=$(hiera nova::api::auth_uri | tr -d '\n')
    ADMINPASS=$(hiera admin_password | tr -d '\n')
    ADMINUSER=$(hiera heat::keystone::domain::keystone_admin | tr -d '\n')
    ADMINTENANT=$(hiera heat::keystone::domain::keystone_tenant | tr -d '\n')
    cat << EOF > /root/overcloudrc_admin_v3
export OS_USERNAME=$ADMINUSER
export OS_TENANT_NAME=$ADMINTENANT
export OS_AUTH_URL=$(echo $AUTHURL | sed 's/v2.0/v3/')
export OS_PASSWORD=$ADMINPASS
export OS_IDENTITY_API_VERSION=3
export OS_PROJECT_DOMAIN_NAME=Default
export OS_USER_DOMAIN_NAME=Default
EOF
  fi

  # Configure selinux
  if [[ $(getsebool authlogin_nsswitch_use_ldap | grep off | wc -l) -ne 0 ]]; then
    echo "INFO: Setting sebool authlogin_nsswitch_use_ldap on"
    setsebool -P authlogin_nsswitch_use_ldap on
  fi

  # Create Domains Directory
  if [ ! -d /etc/keystone/domains ]; then
    echo "INFO: Creating /etc/keystone/domains directory"
    mkdir /etc/keystone/domains
    chown keystone:keystone /etc/keystone/domains
  fi

  # Configure Identity Service to use multiple back ends:
  KEYSTONE_CHANGED=0
  if [[ $(openstack-config --get /etc/keystone/keystone.conf identity domain_specific_drivers_enabled) != "true" ]]; then
    echo "INFO: Setting keystone.conf domain_specific_drivers_enabled true"
    KEYSTONE_CHANGED=1
    openstack-config --set /etc/keystone/keystone.conf identity domain_specific_drivers_enabled true
  fi
  if [[ $(openstack-config --get /etc/keystone/keystone.conf identity domain_config_dir) != "/etc/keystone/domains" ]]; then
    echo "INFO: Setting keystone.conf domain_config_dir /etc/keystone/domains"
    KEYSTONE_CHANGED=1
    openstack-config --set /etc/keystone/keystone.conf identity domain_config_dir /etc/keystone/domains
  fi
  if [[ $(openstack-config --get /etc/keystone/keystone.conf assignment driver) != "keystone.assignment.backends.sql.Assignment" ]]; then
    echo "INFO: Setting keystone.conf assignment driver"
    KEYSTONE_CHANGED=1
    openstack-config --set /etc/keystone/keystone.conf assignment driver keystone.assignment.backends.sql.Assignment
  fi

  # Restart keystone if changed
  if [[ $KEYSTONE_CHANGED -eq 1 ]]; then
    echo "INFO: Keystone changed.  Restarting keystone"
    systemctl restart openstack-keystone
  fi

  # Enable multiple domains and keystone v3 in dashboard 
     # Backup Dashboard first
  cp /etc/openstack-dashboard/local_settings /etc/openstack-dashboard/local_settings.$(date +%m%d%y%H%M)
  DASHBOARD_CHANGED=0
  if ! grep -q "^OPENSTACK_API_VERSIONS" /etc/openstack-dashboard/local_settings
  then
    echo "INFO: Updating Dashboard for Multiple domains and keystone v3"
    DASHBOARD_CHANGED=1
    cat >> /etc/openstack-dashboard/local_settings << EOF
OPENSTACK_API_VERSIONS = {
"identity": 3
}
OPENSTACK_KEYSTONE_MULTIDOMAIN_SUPPORT = True
OPENSTACK_KEYSTONE_DEFAULT_DOMAIN = '${varldapdomain}'
EOF
  fi

  if ! grep "OPENSTACK_KEYSTONE_URL" /etc/openstack-dashboard/local_settings | grep -q v3
  then
    echo "INFO: Updating Dashboard for v3 OPENSTACK_KEYSTONE_URL"
    DASHBOARD_CHANGED=1
    API_VIP=$(hiera tripleo::loadbalancer::internal_api_virtual_ip | tr -d '\n')
    if [[ $API_VIP == "" ]]; then
      echo "ERROR: API VIP cannot be found"
      exit 1
    fi
    #sed 's/^OPENSTACK_KEYSTONE_URL.*/OPENSTACK_KEYSTONE_URL="http://$API_VIP:5000/v3"/' /etc/openstack-dashboard/local_settings
    sed -i "s/^OPENSTACK_KEYSTONE_URL.*/OPENSTACK_KEYSTONE_URL=\"http:\/\/${API_VIP}:5000\/v3\"/" /etc/openstack-dashboard/local_settings
  fi

  if grep -q "native" /etc/openstack-dashboard/local_settings
  then
    echo "INFO: Updating Dashboard for disabling edit user/group options"
    DASHBOARD_CHANGED=1
    sed -i "s/^    'name': 'native',/    'name': 'ldap',/g" /etc/openstack-dashboard/local_settings
    sed -i "s/^    'can_edit_user': True,/    'can_edit_user': False,/g" /etc/openstack-dashboard/local_settings
    sed -i "s/^    'can_edit_group': True,/    'can_edit_group': False,/g" /etc/openstack-dashboard/local_settings
  fi

  # Restart dashboard if changed
  if [[ $DASHBOARD_CHANGED -eq 1 ]]; then
    echo "INFO: Dashboard changed.  Restarting httpd"
    systemctl restart httpd 
  fi

  # Create LDAP domain in OpenStack Keystone 
  if [[ ! -f /root/overcloudrc_admin_v3 ]]; then
    echo "ERROR: /root/overcloudrc_admin_v3 does NOT exist"
    exit 1
  fi

  # Create the domain if it does not exist
  source /root/overcloudrc_admin_v3
  if [[ $(openstack domain list | grep ${varldapdomain} | wc -l) -eq 0 ]]; then 
    openstack domain create --description "${varldapdomain} LDAP Domain" ${varldapdomain}
  fi 

  # Create the domain configuration file
  DOMAINBKUP=""
  if [[ -f /etc/keystone/domains/keystone.${varldapdomain}.conf ]] ; then
     DOMAINBKUP=/etc/keystone/domains/keystone.${varldapdomain}.conf.$(date +%m%d%y%H%M)
     cp -p /etc/keystone/domains/keystone.${varldapdomain}.conf $DOMAINBKUP
  fi
  cat <<EOF > /etc/keystone/domains/keystone.${varldapdomain}.conf
[ldap]
url=${varldapserver}
user=${varldapuser}
password=${varldappassword}
suffix=${varsuf}
user_tree_dn=${vartree}
user_objectclass=person
# Only users in the user_filter DN will be seen (and have access to) OpenStack
user_filter = (memberOf=${vargenabled})
# AD Mappings
# user_id_attribute cannot change after adding LDAP users as it will ruin your mappings
# user_name_attribute=cn results in 'FirstName LastName' user (i.e Red Hat)
# user_name_attribute=SamAccountName results in 'FirstInitial LastName' user (i.e rhat)
# user_name_attribute=UserPrincipalName results in 'SamAccountName@domain' user (i.e rhat@example.com)
user_id_attribute=SamAccountName
user_name_attribute=SamAccountName
user_mail_attribute=mail
user_pass_attribute=
user_enabled_attribute=userAccountControl
user_enabled_mask=2
user_enabled_default=512
user_attribute_ignore=password,tenant_id,tenants
user_allow_create=False
user_allow_update=False
user_allow_delete=False
group_tree_dn=${vargtree}
group_objectclass=group
group_id_attribute=SamAccountName
group_name_attribute=SamAccountName
group_member_attribute=member
# Only groups in the group_filter DN will be seen (and have access to) OpenStack
group_filter = (memberOf=${vargroupfilter})
group_desc_attribute=description
group_allow_create=False
group_allow_update=False
group_allow_delete=False
use_tls = False
### If using LDAPS you need to set this!
tls_cacertfile=/etc/ssl/certs/${CRTSHORTNAME}

[identity]
driver = keystone.identity.backends.ldap.Identity
EOF

  # Ensure correct ownership
  chown -R keystone:keystone /etc/keystone/domains
  chcon --reference=/etc/keystone /etc/keystone/domains
  chcon --reference=/etc/keystone/keystone.conf /etc/keystone/domains/*.conf

  # Now configure the default admin user to be admin in your LDAP domain
  LDAPDOMAINID=$(openstack domain show ${varldapdomain} -c id -f value)
  ADMINUSERID=$(openstack user show --domain default admin -c id -f value)
  ADMINROLEID=$(openstack role show admin -c id -f value)

  if [[ $(openstack role assignment list --role $ADMINROLEID --user $ADMINUSERID --domain $LDAPDOMAINID | wc -l) -eq 0 ]]; then
    echo "INFO: Adding admin user/role to ${varldapdomain} domain"
    openstack role add --domain $LDAPDOMAINID --user $ADMINUSERID $ADMINROLEID
  fi

  ### Note - admin will not work now until keystone is restarted

  # restart keystone to apply domain changes from above (only if domain conf changed)
  if [[ $DOMAINBKUP != "" ]] ; then
    if [[ $(diff $DOMAINBKUP /etc/keystone/domains/keystone.${varldapdomain}.conf | wc -l) -ne 0 ]]; then
      echo "INFO: Restarting OpenStack"
      systemctl restart openstack-keystone
    fi 
  fi

  # Can validate by doing: 
  # openstack user list --domain <LDAP Domain>  # ${varldapdomain}
  # openstack user list --domain default

  if [ ! -f  /etc/keystone/policy.v3.json ]; then
    cp /usr/share/keystone/policy.v3cloudsample.json /etc/keystone/policy.v3.json
    sed -i "s/admin_domain_id/default/g" /etc/keystone/policy.v3.json
    chown keystone:keystone /etc/keystone/policy.v3.json
    chcon --reference=/etc/keystone/policy.json /etc/keystone/policy.v3.json
  fi
  openstack-config --set /etc/keystone/keystone.conf oslo_policy policy_file policy.v3.json

  # Any reason to set these? 
  #sed -i 's/^    "identity:list_domains":.*/    "identity:list_domains":"",/g' /etc/keystone/policy.v3.json
  #sed -i 's/^    "identity:list_users":.*/    "identity:list_users":"",/g' /etc/keystone/policy.v3.json
  #sed -i 's/^    "identity:list_projects":.*/    "identity:list_projects":"",/g' /etc/keystone/policy.v3.json


  # Sync our Keystone v3 policy with Horizon
  ### Not needed because not introducing cloud_admin
  #if [ ! -f /etc/openstack-dashboard/keystone_policy.json.orig ]; then
  #  mv /etc/openstack-dashboard/keystone_policy.json /etc/openstack-dashboard/keystone_policy.json.orig
  #fi
  #
  #cp /etc/keystone/policy.v3.json /etc/openstack-dashboard/keystone_policy.json
  #chcon --reference=/etc/openstack-dashboard/keystone_policy.json.orig /etc/openstack-dashboard/keystone_policy.json
  #chgrp apache /etc/openstack-dashboard/keystone_policy.json
  #chmod 640 /etc/openstack-dashboard/keystone_policy.json

  
  # Configure Services to talk to v3 API
  KEYSTONEADMINVIP=$(hiera keystone_admin_api_vip | tr -d '\n')

  # Nova
  if [[ $(openstack-config --get /etc/nova/nova.conf keystone_authtoken auth_uri) != "http://${KEYSTONEADMINVIP}:5000/v3" ]] ; then
    echo "INFO: Changing nova to keystone v3 and restarting nova"
    openstack-config --set /etc/nova/nova.conf keystone_authtoken auth_version v3
    openstack-config --set /etc/nova/nova.conf keystone_authtoken auth_uri http://${KEYSTONEADMINVIP}:5000/v3
    systemctl restart openstack-nova-api openstack-nova-cert openstack-nova-conductor openstack-nova-consoleauth openstack-nova-novncproxy openstack-nova-scheduler
  fi

# Neutron Config 
  if [[ $(openstack-config --get /etc/neutron/neutron.conf keystone_authtoken auth_uri) != "http://${KEYSTONEADMINVIP}:5000/v3" ]] ; then
    echo "INFO: Changing neutron to keystone v3 and restarting neutron"
    openstack-config --set /etc/neutron/neutron.conf keystone_authtoken auth_uri http://${KEYSTONEADMINVIP}:5000/v3
    systemctl restart neutron-server
  fi

  # Cinder Config 
  if [[ $(openstack-config --get /etc/cinder/cinder.conf keystone_authtoken auth_uri) != "http://${KEYSTONEADMINVIP}:5000/v3" ]] ; then
    echo "INFO: Changing cinder to keystone v3 and restarting cinder"
    openstack-config --set /etc/cinder/cinder.conf keystone_authtoken auth_uri http://${KEYSTONEADMINVIP}:5000/v3
    systemctl restart openstack-cinder-api
  fi

  # Ceilometer Config 
  if [[ $(openstack-config --get /etc/ceilometer/ceilometer.conf keystone_authtoken auth_uri) != "http://${KEYSTONEADMINVIP}:5000/v3" ]] ; then
    echo "INFO: Changing ceilometer to keystone v3 and restarting ceilometer"
    openstack-config --set /etc/ceilometer/ceilometer.conf keystone_authtoken auth_uri http://${KEYSTONEADMINVIP}:5000/v3
    systemctl restart openstack-ceilometer-api openstack-ceilometer-central 
  fi

# Glance Config
if [[ $(openstack-config --get /etc/glance/glance-api.conf keystone_authtoken auth_uri) != "http://${KEYSTONEADMINVIP}:5000/v3" ]] ; then
  echo "INFO: Changing glance to keystone v3 and restarting glance"
  openstack-config --set /etc/glance/glance-api.conf keystone_authtoken auth_uri http://${KEYSTONEADMINVIP}:5000/v3
  openstack-config --set /etc/glance/glance-registry.conf keystone_authtoken auth_uri http://${KEYSTONEADMINVIP}:5000/v3
  systemctl restart openstack-glance-api
fi

# Heat Config 
if [[ $(openstack-config --get /etc/heat/heat.conf keystone_authtoken auth_uri) != "http://${KEYSTONEADMINVIP}:5000/v3" ]] ; then
  echo "INFO: Changing heat to keystone v3 and restarting heat"
  openstack-config --set /etc/heat/heat.conf keystone_authtoken auth_uri http://${KEYSTONEADMINVIP}:5000/v3
  openstack-config --set /etc/heat/heat.conf keystone_authtoken auth_version 3
  systemctl restart openstack-heat-api  openstack-heat-api-cloudwatch openstack-heat-api-cfn
fi

} # End function setup_controller

#################
# Compute Nodes #
#################
function setup_compute {
  # Compute Nodes - Configure Services to talk to Keystone v3 
  # Nova 
  KEYSTONEADMINVIP=$(hiera nova_api_host | tr -d '\n')
  if [[ $(openstack-config --get /etc/nova/nova.conf keystone_authtoken auth_uri) != "http://${KEYSTONEADMINVIP}:5000/v3" ]] ; then
    echo "INFO: Changing nova to keystone v3 and restarting nova-compute"
    openstack-config --set /etc/nova/nova.conf keystone_authtoken auth_version v3
    openstack-config --set /etc/nova/nova.conf keystone_authtoken auth_uri http://${KEYSTONEADMINVIP}:5000/v3
    systemctl restart openstack-nova-compute
  fi

  # Ceilometer
  if [[ $(openstack-config --get /etc/ceilometer/ceilometer.conf keystone_authtoken auth_uri | grep "/v3" | wc -l) eq 0 ]]; then
    echo "INFO: Changing ceilometer to keystone v3 and restarting ceilometer"
    CEILOMETER_V2_AUTH=$(hiera ceilometer::agent::auth::auth_url | tr -d '\n')
    CEILOMETER_V3_AUTH=$(echo $CEILOMETER_V2_AUTH | sed 's/v2.0/v3/')
    openstack-config --set /etc/ceilometer/ceilometer.conf keystone_authtoken auth_uri $CEILOMETER_V3_AUTH 
    systemctl restart openstack-ceilometer-api openstack-ceilometer-central
  fi
} # End function setup_compute


#################
# Main Routine  #
#################
HOSTNAME=$(hostnamectl --static) 
if [[ $HOSTNAME == *"controller"* ]]; then
  echo "This is a controller node... continuing"
  setup_controller
elif [[ $HOSTNAME == *"compute"* ]]; then
  echo "This is a compute node... continuing"
  setup_compute
else:
  echo "Not running on a controller or compute node, so I'm not doing anything"
fi



# Allow AD users to access projects:
###openstack project create --domain <LDAP Domain> --enable --description "LDAP User Testing" ldaptestproject
###openstack user list --domain <LDAP Domain>   # ${varldapdomain}
###openstack role list 
###openstack role add --project <project name> --user <user id> _member_
###openstack role add --project <project name> --user <user id> admin
###openstack role assignment list --role admin --user <user ID> --domain <LDAP Domain> 
# You should now be able to log into the dashboard as this user... 

# Allow AD group (and all it's users) to access projects
### NOTE - Adding an AD group does NOT give a user access to login to openstack!  It only gives them access to the project you've associated.  You still need to add the user to the grp-openstack in AD ... 
### openstack project create --domain <LDAP Domain> --enable --description "LDAP Group Testing" ldaptestproject2
### openstack group list --domain <LDAP Domain> 
### openstack role list 
### openstack role add --project <project> --group <group id> <_member_ id>
### openstack role assignment list --role _member_ --group <group ID> 
# If the user is already in the main openstack group they will be able to login.  The group assignment simply gives mapping into projects.  

