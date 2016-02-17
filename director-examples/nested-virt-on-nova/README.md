# Nested Virt on Nova
This details how to setup nested virtualization with Nova on RHEL OSP 7 and deployed using OSP Director.  This will include the following layers: 

* L0 = OpenStack Nova Compute node on physical hardware
* L1 = RHEL 7 virtual machine running KVM
* L2 = nested virtual guest running on top of the L1 hypervisor

Note that this setup passes through the host's CPU to the virtual instances.  Keep in mind that if you are also planning to use live migration, all hosts in the cluster MUST then have the exact same CPU model.

## Pre-requisites

* A running/installed OSP Director host with heat templates copied to a working directory
``` 
cp -rp /usr/share/openstack-tripleo-heat-templates /home/stack/templates
```
* Access to RHN for your RHEL guest to install KVM

## Deploy your overcloud with nested virtualization enabled

* Deploy your overcloud and validate standard functionality
* Create a subdirectory in your local templates directory `mkdir /home/stack/templates/custom`
* Place all files in this repo in /home/stack/templates/custom
```
cd /home/stack
git clone https://github.com/jonjozwiak/openstack.git
cp openstack/director-examples/nested-virt-on-nova/* /home/stack/templates/custom
```
* Execute the overcloud deploy with the new templates added:
``` 
-e /home/stack/templates/custom/nested-virt-post-deploy.yaml
```
NOTE: You cannot have multiple NodeExtraConfigPost definitions.  If you want to 
do multiple SoftwareConfigs in post deploy, you can create something like config
-post-deploy.yaml that calls a single config yaml.  Then in that config yaml you
 can have multiple SoftwareConfig and SoftwareDeployments resources.  Also, you 
can use 'depends_on: deploymentname' in the definition of a SoftwareConfig if yo
u need one to complete before the other. 

TODO: Nova compute requires a restart at this point. 

## Validate nested virtualization 
To validate nested virtualization we will boot a RHEL 7 instance, configure it as a hypervisor, and then provision an instance underneath that.  

NOTE: This requires access to RHN (or a local repo)

* Prepare your RHEL KVM virtual machine 
  * Get a RHEL 7 glance image (https://access.redhat.com/downloads -> Red Hat Enterprise Linux -> KVM Guest Image -> Download Now)
  ```
. overcloudrc
glance image-create --name "rhel-7.2-x86_64" --disk-format qcow2 --container-format bare \
   --file rhel-guest-image-7.2-20151102.0.x86_64.qcow2 --is-public true
  ```
  * Boot your nova instance - make certain you have enough memory to run a guest within this instance
  ```
neutron net-list
PRIVNET1ID=<your privnet>
nova boot nestedhypervisor --flavor m1.medium --image rhel-7.2-x86_64 \
  --key-name adminkey --security-groups default --nic net-id=$PRIVNET1ID

FLOATINGIP=$(neutron floatingip-create pubnet1 | grep floating_ip_address | awk '{print $4}')
nova add-floating-ip nestedhypervisor $FLOATINGIP
ping -c 1 $FLOATINGIP

ssh -i adminkey.pem cloud-user@$FLOATINGIP
sudo su - 
  ```
  * Setup the host for KVM.  I provided a script you can used called `kvm-setup.sh` but you must put in your own RHN credentials

* Create your L2 nested guest

Here we will use the existing RHEL qcow that we have previously used.  Copy this to the L1 hypervisor instance (nestedhypervisor).  Also we'll use a NAT network called virbr0 on 192.168.122.0 which KVM sets up by default

NOTE: ensure /var/lib/libvirt/images/rhel-guest-image-7.2-20151102.0.x86_64.qcow2 exists

  * Create cloud-init source

  Cloud images expect a cloud-init source in order to do post-build customization such as setting hostname and password.  We will create an iso to pass this data
  ```
mkdir /tmp/cidata
cat << EOF > /tmp/cidata/meta-data
instance-id: l2guest
local-hostname: l2guest
EOF

cat << EOF > /tmp/cidata/user-data
#cloud-config
ssh_pwauth: True
chpasswd:
  list: |
     root:redhat
     cloud-user:redhat
  expire: False
EOF

genisoimage -o /var/lib/libvirt/images/l2guest.iso -V cidata -r -J \
  /tmp/cidata/meta-data /tmp/cidata/user-data
  ``` 
  * Boot your instance & validate
  ```
virt-install -n l2guest -r 2048 --os-type=linux --os-variant=rhel7 \
  --disk /var/lib/libvirt/images/rhel-guest-image-7.2-20151102.0.x86_64.qcow2,device=disk,bus=virtio \
  -w bridge=virbr0,model=virtio 
  --disk path=/var/lib/libvirt/images/l2guest.iso,device=cdrom \
  --vnc --noautoconsole --import

virsh console l2guest
# You should be able to connet with either root or cloud-user
# with the password set in the CI data
 
# Validate external connectivity
ping 8.8.8.8
  ```
 
  Alternatively if you do not want to go through the cloud-init setup, you can test with a cirros image as it has a password already set:
  ```
virt-install -n l2guest -r 512 --os-type=linux \
  --disk /var/lib/libvirt/images/cirros-0.3.4-x86_64-disk.img,device=disk,bus=virtio \
  -w bridge=virbr0,model=virtio --vnc --noautoconsole --import

virsh console l2guest 
## User is cirros, password is cubswin:)

# Validate external connectivity 
ping 8.8.8.8 
  ````


