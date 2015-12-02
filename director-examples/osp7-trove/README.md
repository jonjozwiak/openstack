# Trove for RHEL OSP 7 / Director
This set of templates and puppet manifests are used to install and configure Trove on a RHEL OSP 7 installation deployed by OSP Director.  It modifies the existing controller yaml and puppet manifests to enable the deployment as it was not possible via NodeExtraConfig.  

Pre-requisites:

1) A running/installed OSP Director host with heat templates copied to a working directory 
``` 
cp -rp /usr/share/openstack-tripleo-heat-templates /home/stack/templates
```

**IMPORTANT:** This is ONLY developed for an HA OpenStack deployment.  It will not work on a non-HA OpenStack deployed from Director

2) Overcloud controllers MUST have repository access to install packages.  This can be local repos, Satellite, or CDN.  

# Steps to deploy Trove on OSP7 with Director

1) Get the repository as the stack user on your director host
```
cd /home/stack
git clone http://github.com/jonjozwiak/openstack.git
```

2) Add the Trove-specific data to your controller hieradata.  Note this generates a password for some parameters.  Feel free to modify the values in the yaml afterwards.
```
chmod 755 /home/stack/openstack/director-examples/osp7-trove/update-hieradata.sh
/home/stack/openstack/director-examples/osp7-trove/update-hieradata.sh
```

3) Add a step to the controller post install puppet run for Trove.  This enables a call to the puppet manifest with an extra step specific to Trove.  (/home/stack/templates/puppet/controller-post-puppet.yaml)
```
sed -i '/^  ExtraConfig/i \
  # Custom Step for Trove Deployment - Before ExtraConfig \ 
  ControllerOvercloudServicesDeployment_Step8: \
    type: OS::Heat::StructuredDeployments \
    depends_on: ControllerOvercloudServicesDeployment_Step7 \ 
    properties: \ 
      servers:  {get_param: servers} \ 
      config: {get_resource: ControllerPuppetConfig} \
      input_values: \ 
        step: 7 \ 
        update_identifier: {get_param: NodeConfigIdentifiers}  \
\
' /home/stack/templates/puppet/controller-post-puppet.yaml
```

4) Add the Trove Database Configuration to the puppet manifest (/home/stack/templates/puppet/manifests/overcloud_controller_pacemaker.pp)
```
vi /home/stack/templates/puppet/manifests/overcloud_controller_pacemaker.pp
### Add this just before the line with heat_dsn:
    $trove_dsn = split(hiera('trove::database_connection'), '[@:/?]')
    class { 'trove::db::mysql':
      user          => $trove_dsn[3],
      password      => $trove_dsn[4],
      host          => $trove_dsn[5],
      dbname        => $trove_dsn[6],
      allowed_hosts => $allowed_hosts,
      require       => Exec['galera-ready'],
    }

```

5) Update Puppet manifest to provision trove
Add the Trove implementation steps (including load balancer) to the puppet manifest (/home/stack/templates/puppet/controller-post-puppet.yaml)

```
chmod 755 /home/stack/openstack/director-examples/osp7-trove/patch-manifest.sh
/home/stack/openstack/director-examples/osp7-trove/patch-manifest.sh
```

6) Deploy as usual.  Make certain your nodes will register to get content or have local repos.  The deploy will fail if it can't install trove packages!  Here's an example of my deploy command with network isolation and Ceph backend.  Obviously this is specific to my environment.
```
. stackrc
openstack overcloud deploy --templates ~/templates/ --ntp-server 108.61.56.35 \
  --libvirt-type kvm --control-flavor control --compute-flavor compute \
  --ceph-storage-flavor ceph --control-scale 3 --compute-scale 2 \
  --ceph-storage-scale 3 --log-file overcloud_deployment.log \
  --neutron-bridge-mappings datacentre:br-ex,tenant:br-tenant \
  --neutron-network-type vlan --neutron-network-vlan-ranges tenant:1603:1610 \
  --neutron-disable-tunneling \
  -e ~/templates/environments/storage-environment.yaml \
  -e ~/templates/advanced-networking.yaml \
  -e ~/templates/extraconfig/pre_deploy/rhel-registration/environment-rhel-registration.yaml \
  -e ~/templates/extraconfig/pre_deploy/rhel-registration/rhel-registration-resource-registry.yaml
```
**IMPORTANT:** I could not get this to update hieradata on an existing deployment.  If you have an existing deployment, just manually add the trove hieradata to each controller in */etc/puppet/hieradata/controller.yaml.*  I have a feeling it's a bug that causes it not to update.  Possibly this https://bugzilla.redhat.com/show_bug.cgi?id=1267855 or https://bugs.launchpad.net/tripleo/+bug/1463092, but not certain.
But looks like a fix is committed...//bugs.launchpad.net/tripleo/+bug/1463092

Once the deployment is done, log into the controller and run *pcs status*
My Trove services weren't all running properly at install so I ran a *pcs resource cleanup* and that seemed to fix things.  This is likely an ordering issue with the puppet run.  I have a feeling (although haven't confirmed) that the load balancer config is happening after the initial trove config.  


6) Create the Keystone service and endpoint for Trove
Note that OSP-d 7 deploys keystone endpoints as post config on the director node.  It does NOT run them from puppet.  This will thankfully change with OSP-d 8. 

To setup endpoints, copy the setup-keystone.pp puppet module to controller-0.  Then execute it. 

```
  scp trove-keystone.pp heat-admin@<controller-0-ip>:/tmp
  ssh heat-admin@<controller-0-ip>
  sudo su - 
  puppet apply /tmp/trove-keystone.pp
  keystone catalog   # Verify database endpoints 
  keystone user-list # Verify trove user
```

Troubleshooting: 
. If a puppet run fails, log into a node it failed on.  
.. Puppet manifests exist in /var/lib/heat-config/heat-config-puppet.  
.. Logs from each run will be in /var/run/heat-config/deployed (although in really poor format)
.. To test, vi /etc/puppet/hieradata/controller.yaml (if on a controller)
... add 'step: 7' at the bottom.  Or whatever step you're troubleshooting
... Re-execute to test (from heat-config-puppet): puppet apply file.pp

# Using Trove
Just to verify trove is functioning, it is best to run *trove list*.  

## Trove Images
Trove requires an image that has the guest agent installed and configured as well as the database that is being used.  I'll show an example using cloud-init.  However, it may be better to build images with the agent and DB software built in.  Potential approaches:
  - Cloud-init
  - virt-customize to modify the RHEL image
  - Disk image builder to build your own image

### Trove Images via cloud-init
Trove has a facility to enable cloud-init based on datastore type.  My example is using a mysql database.  Ensure to put in your subscription details in the below example.  Also, Use a RHEL 7.2 or newer image.  I'm not certain that the cloud-init subscription module was available in 7.1 or earlier.  

Do the following on **ALL** controllers:
```
mkdir /etc/trove/cloudinit
cat << EOF >> /etc/trove/cloudinit/mysql.cloudinit
#cloud-config
## cloud-init template for mysql
rh_subscription:
    username: <Your SM User>
 
    ## Quote your password if it has symbols to be safe
    password: '<Your SM Password'
 
    ## If you prefer, you can use the activation key and 
    ## org instead of username and password. Be sure to
    ## comment out username and password
     
    #activation-key: foobar
    #org: 12345
    
    ## Uncomment to auto-attach subscriptions to your system 
    #auto-attach: True
    
    ## Uncomment to set the service level for your 
    ##   subscriptions
    #service-level: self-support

    ## Uncomment to add pools (needs to be a list of IDs)
    add-pool: ['<Your pool if not doing auto-attach or activation key>']
    
    ## Uncomment to add or remove yum repos
    ##   (needs to be a list of repo IDs)
    disable-repo: ['rhel-7-server-aus-rpms', 'rhel-7-server-eus-rpms', 'rhel-7-server-htb-rpms', 'rhel-7-server-rt-beta-rpms', 'rhel-7-server-rt-htb-rpms', 'rhel-7-server-rt-rpms', 'rhel-ha-for-rhel-7-server-eus-rpms', 'rhel-ha-for-rhel-7-server-htb-rpms', 'rhel-ha-for-rhel-7-server-rpms', 'rhel-lb-for-rhel-7-server-htb-rpms', 'rhel-rs-for-rhel-7-server-eus-rpms', 'rhel-rs-for-rhel-7-server-htb-rpms', 'rhel-rs-for-rhel-7-server-rpms', 'rhel-sap-for-rhel-7-server-rpms', 'rhel-sap-hana-for-rhel-7-server-rpms', 'rhel-sjis-for-rhel-7-server-rpms']

    enable-repo: ['rhel-7-server-rpms', 'rhel-7-server-openstack-7.0-rpms']
    ## Uncomment to alter the baseurl in /etc/rhsm/rhsm.conf
    #rhsm-baseurl: http://url
    
    ## Uncomment to alter the server hostname in 
    ##  /etc/rhsm/rhsm.conf
    #server-hostname: foo.bar.com
packages: 
- openstack-trove-guestagent
- mariadb-server

# Write SSH public key as trove doesn't appear to have way to inject it
# You can get this from nova keypair-show 
ssh_authorized_keys:
  - "ssh-rsa ..."

# config file for trove guestagent - Get these values from /etc/trove/trove.conf
write_files:
- path: /etc/trove/trove-guestagent.conf
  content: |
    [DEFAULT]
    rabbit_hosts = <controller1>,<controller2>,<controller3>
    rabbit_password=<Your Rabbit PW>
    nova_proxy_admin_user = admin
    nova_proxy_admin_pass = <Your PW>
    nova_proxy_admin_tenant_name=service
    trove_auth_url=http://<internal VIP>:5000/v2.0

# restart trove-guestagent as the config has been changed
runcmd:
- systemctl enable mariadb
- systemctl start mariadb
- systemctl stop openstack-trove-guestagent
- systemctl start openstack-trove-guestagent
- systemctl enable openstack-trove-guestagent
EOF
```
You may want to test this cloud-init outside of trove.  guestagent will not start because it's not passed detail by trove.  But everything else should function.  If you want to test it, you can like the following: 
```
nova boot citest --flavor m1.medium --image rhel-7.2-20151102 --key-name yourkey --security-groups default --nic net-id=<your privnet ID> --user-data /etc/trove/cloudinit/mysql.cloudinit
```


### Trove Images via virt-customize
This approach was inspired by https://rwmj.wordpress.com/2015/10/03/tip-updating-rhel-7-1-cloud-images-using-virt-customize-and-subscription-manager/.
NOTE: You MUST use >= Fedora 22 OR RHEL 7.3 for this!  I've used F22.

ALSO NOTE: I've not completely tested this, but feel free to use as a starting point... 

Insert your subscription manager user, password, and pool below...
```
cp rhel-guest-image-7.2-20151102.0.x86_64.qcow2 rhel-guest-image-7.2-20151102.0.mysql_trove.x86_64.qcow2
virt-customize -a rhel-guest-image-7.2-20151102.0.mysql_trove.x86_64.qcow2 --sm-credentials '<SM User>:password:<SM Password>' --sm-register --sm-attach pool:<SM Pool> --run-command 'subscription-manager repos --disable=* --enable=rhel-7-server-rpms --enable=rhel-7-server-openstack-7.0-rpms'  
virt-customize -a rhel-guest-image-7.2-20151102.0.mysql_trove.x86_64.qcow2 --run-command 'yum -y install openstack-trove-guestagent mariadb-server'  
virt-customize -a rhel-guest-image-7.2-20151102.0.mysql_trove.x86_64.qcow2 --sm-unregister --sm-remove
# Write SSH key as trove doesn't appear to have a way to customize it
virt-copy-in -a rhel-guest-image-7.2-20151102.0.mysql_trove.x86_64.qcow2 ~/.ssh/id_rsa.pub /home/cloud-user/.ssh/authorized_keys

## Note - replace the values below to match your environment (check /etc/trove/trove.conf)
cat <<EOF > /tmp/trove-guestagent.conf
[DEFAULT]
rabbit_hosts = controller1,controller2,controller3
rabbit_password = RABBIT_PASS
nova_proxy_admin_user = admin
nova_proxy_admin_pass = ADMIN_PASS
nova_proxy_admin_tenant_name = service
trove_auth_url = http://controller:35357/v2.0
EOF
virt-customize -a rhel-guest-image-7.2-20151102.0.mysql_trove.x86_64.qcow2 --run-command 'mkdir /etc/trove'  
virt-copy-in -a rhel-guest-image-7.2-20151102.0.mysql_trove.x86_64.qcow2 /tmp/trove-guestagent.conf /etc/trove
virt-customize -a rhel-guest-image-7.2-20151102.0.mysql_trove.x86_64.qcow2 --run-command 'systemctl enable openstack-trove-guestagent'  
virt-customize -a rhel-guest-image-7.2-20151102.0.mysql_trove.x86_64.qcow2 --run-command 'systemctl enable mariadb'  
rm -f /tmp/trove-guestagent.conf
```

Once completed with the image modifications, load the image into glance.  Note I'm converting it to raw format for ceph For example:
```
qemu-img convert -f qcow2 -O raw rhel-guest-image-7.2-20151102.0.mysql_trove.x86_64.qcow2 rhel-guest-image-7.2-20151102.0.mysql_trove.x86_64.raw
glance image-create --name "rhel7.2-mysql-5.5" --disk-format raw --container-format bare --file rhel-guest-image-7.2-20151102.0.mysql_trove.x86_64.raw --is-public true
```

## Basic Trove Workflow

. Create a datastore with a default version (mysql-5.5)
trove datastore-list
trove-manage datastore_update mysql ""

. Add a version to the datastore
glance image-list
# trove-manage datastore_version_update <datastore> <version name> <datastore_manager> <glance ID> <packages> <active>
trove-manage datastore_version_update mysql mysql-5.5 mysql a463edc3-5f46-40c9-b91c-bf18f7f521d8 "" 1

. Make this version the default for mysql
trove-manage datastore_update mysql mysql-5.5

. Setup Validation rules
mysql and percona have a set of validation rules which ensures configuration mat
ches the rules.  Load these for later... 
trove-manage db_load_datastore_config_parameters mysql mysql-5.5 /usr/lib/python2.7/site-packages/trove/templates/mysql/validation-rules.json

. Validate your datastore exists 
trove datastore-list
trove datastore-version-list mysql

. Create an instance
trove create jjtest 3 --size 5 --datastore mysql --datastore_version mysql-5.5 --nic net-id=$PRIVNET1ID
  m1.medium wouldn't work.  Must specify flavor id
  size wouldn't allow more than 5GB.  Why?  

. Enabling ssh and ping access to your instance
This is kind of stupid.  I've not found a way from trove to set defaults for security groups.  Maybe use a jump server to access?  Or maybe just this: 
trove list
# with your instance ID from trove-list:
neutron security-group-list | grep <instance ID> 
neutron security-group-rule-create --protocol tcp --port-range-min 22 --port-range-max 22 --direction ingress <security group ID>
neutron security-group-rule-create --protocol icmp --direction ingress <security group ID>


. Enable root access to your database
trove list 
trove root-show <instance ID> 
trove root-enable <instance ID>

