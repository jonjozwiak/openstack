#!/bin/bash
#
# This script creates some orphaned objects to test catching this information
# It also requires internet access to download a cirros image
##############################################################################

# Admin Keystone credentials
KSADMIN="/root/keystonerc_admin"
if [[ ! -f $KSADMIN ]]; then
  echo "$KSADMIN does not exist!  You need a keystone admin file" 
  exit 1
fi
source $KSADMIN

# Name of public network to attach to
PUBNET="pubnet1"

if [[ $1 == "cleanup" ]]; then
  # I have not found a nice way to clean up an orphaned stack...
  mysql -e 'DELETE FROM event WHERE stack_id = (SELECT id FROM stack WHERE name="orphanstack");' heat
  mysql -e 'DELETE FROM resource_data WHERE resource_id = (select id from resource where stack_id = (SELECT id FROM stack WHERE name="orphanstack"));' heat
  mysql -e 'DELETE FROM resource WHERE stack_id = (SELECT id FROM stack WHERE name="orphanstack");' heat
  mysql -e 'DELETE FROM stack WHERE name="orphanstack";' heat

  nova delete orphanvm
  nova delete orphanvm --all-tenants
 
  # Nova can't see the keypair so can't delete it
  #nova keypair-delete orphankey
  mysql -e 'DELETE FROM key_pairs WHERE name = "orphankey" AND deleted_at IS NULL AND user_id NOT IN (SELECT id FROM keystone.user);' nova
  #cinder backup-delete orphanvol-backup
  cinder snapshot-delete orphanvol-snap
  sleep 2
  cinder delete orphanvol
  glance image-list --all-tenants | grep orphanimage | awk '{print $2}' | while read image 
  do
    glance image-delete $image
  done
  glance image-list | grep orphanimage | awk '{print $2}' | while read image
  do
    glance image-delete $image
  done


  neutron router-gateway-clear orphan-router
  neutron router-interface-delete orphan-router orphan-subnet
  neutron router-delete orphan-router
  neutron subnet-delete orphan-subnet
  neutron net-delete orphan-net
  neutron security-group-delete orphansg
  # Clean up default security groups for the deleted tenants 
  NEUTRONDB=$(mysql -e 'SHOW DATABASES' | grep neutron)
  mysql -Nse 'SELECT id FROM securitygroups WHERE tenant_id NOT in (SELECT id from keystone.project)' $NEUTRONDB | while read id 
  do
    neutron security-group-delete $id 
  done
  # Clean up floating ips for deleted tenants
  mysql -Nse 'SELECT id FROM floatingips WHERE tenant_id NOT in (SELECT id FROM keystone.project)' $NEUTRONDB | while read id 
  do
    neutron floatingip-delete $id 
  done
  keystone user-delete orphanuser
  #keystone tenant-delete orphantenant
 
else

  # Create resources
  keystone tenant-create --name orphantenant --description "Testing Orphaned Objects"

  # Add admin user to orphan tenant?
  ###keystone user-role-add --user admin --tenant orphantenant --role admin

  keystone user-create --name orphanuser --tenant orphantenant --pass 'password'
  openstack role list -f csv -c Name --quote none | grep -v ^Name | while read role 
  do
    if [[ $role == "heat_stack_owner" ]] || [[ $role == "ResellerAdmin" ]] || [[ $role == "swiftoperator" ]] || [[ $role == "SwiftOperator" ]] ; then
      keystone user-role-add --user orphanuser --tenant orphantenant --role $role
    fi
  done

  export OS_USERNAME=orphanuser
  export OS_TENANT_NAME=orphantenant
  export OS_PASSWORD=password

  # Create glance image
  if [[ ! -f cirros-0.3.4-x86_64-disk.img ]]; then
    curl -k -o cirros-0.3.4-x86_64-disk.img https://download.cirros-cloud.net/0.3.4/cirros-0.3.4-x86_64-disk.img
  fi
  glance image-create --name "orphanimage" --disk-format qcow2 --container-format bare --file cirros-0.3.4-x86_64-disk.img 

  # Create sec group & some rules 
  if [[ $(neutron security-group-list | grep orphansg | wc -l) -eq 0 ]]; then 
    neutron security-group-create --description "Orphan Test Sec Group" orphansg
  fi
  neutron security-group-rule-create --protocol icmp --direction ingress orphansg
  neutron security-group-rule-create --protocol tcp --port-range-min 22 --port-range-max 22 --direction ingress orphansg

  # Keypair
  nova keypair-add orphankey > /dev/null

  # Create Networks 
  neutron net-create orphan-net
  ORPHANNETID=$(neutron net-list | grep orphan-net | awk '{print $2}')
  neutron subnet-create --name orphan-subnet orphan-net 192.193.194.0/24
  neutron router-create orphan-router
  neutron router-interface-add orphan-router orphan-subnet
  neutron router-gateway-set orphan-router $PUBNET

  # Cinder Volumes, Snapshots, Backups
  cinder create --display-name orphanvol 1 
  sleep 2
  VOLID=$(cinder list | grep orphanvol | awk '{print $2}')
  cinder snapshot-create --display-name orphanvol-snap $VOLID
  #sleep 2
  #cinder backup-create --display-name orphanvol-backup $VOLID


  # Create VM and attach floating IP
  nova boot orphanvm --flavor m1.tiny --image orphanimage --key-name orphankey --security-groups orphansg --nic net-id=$ORPHANNETID

  FLOATINGIP=$(neutron floatingip-create $PUBNET | grep floating_ip_address | awk '{print $4}')
  nova add-floating-ip orphanvm $FLOATINGIP

  # Basic Heat Stack  (Launching a VM)
  cat << EOF > test-stack.yml
heat_template_version: 2013-05-23

description: Test Template

parameters:
  ImageID:
    type: string
    description: Image use to boot a server
  NetID:
    type: string
    description: Network ID for the server

resources:
  server1:
    type: OS::Nova::Server
    properties:
      name: "orphanvmheat"
      image: { get_param: ImageID }
      flavor: "m1.tiny"
      networks:
      - network: { get_param: NetID }

outputs:
  server1_private_ip:
    description: IP address of the server in the private network
    value: { get_attr: [ server1, first_address ] }
EOF
  heat stack-create -f test-stack.yml -P "ImageID=orphanimage;NetID=$ORPHANNETID" orphanstack

  # Remove tenant creds and change back to admin 
  unset OS_USERNAME
  unset OS_TENANT_NAME
  unset OS_PASSWORD
  source $KSADMIN
  
  # Delete the tenant to leave lots of orphaned resources
  keystone tenant-delete orphantenant
  rm -f test-stack.yml
fi


