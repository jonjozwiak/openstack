# Nova Serial Proxy for OSP7 Director
This collection of templates shows how to setup nova-serialproxy and Serial Consoles on RHEL OSP 7 with Director.  Reference details as follows: 

. https://blueprints.launchpad.net/horizon/+spec/serial-console
. https://bugzilla.redhat.com/show_bug.cgi?id=974199
. http://blog.oddbit.com/2014/12/22/accessing-the-serial-console-of-your-nova-servers/


## Pre-requisites

* A running/installed OSP Director host with heat templates copied to a working directory 
``` 
cp -rp /usr/share/openstack-tripleo-heat-templates /home/stack/templates
```
* A copy of the overcloud images in /home/stack/images 
```
# Files are accessible from:
# https://access.redhat.com/downloads/content/191/ver=7/rhel---7/7/x86_64/product-software
# Or https://access.redhat.com/downloads/ and download latest for RHEL OSP
cd /home/stack/images
for tarfile in *.tar; do tar -xf $tarfile; done
```
* A Local RHEL OSP 7 repo
Assuming you have your Director host registered to RHN, you can reposync it as follows
``` 
# As Root - note this takes about 233mb
yum -y install createrepo
mkdir /var/www/html/repos
reposync --gpgcheck -lnm --repoid=rhel-7-server-openstack-7.0-rpms --download_path=/var/www/html/repos
createrepo /var/www/html/repos/rhel-7-server-openstack-7.0-rpms
```

## Image Updates
The default overcloud images do not ship with the openstack-nova-serialproxy package.  I will show updating the image prior to upload.  However, you could also register the system with RHN or use local repos when provisioning the overcloud and install as a pre-step.  

This step assumes you have created a local repo as described above

```
# As stack user
sudo yum -y install libguestfs-tools
cd /home/stack/images

# Ensure the IP matches your director provisioning IP address
### Note this uses /etc/httpd/conf.d/10-horizon_vhost.conf
cat << EOF >> /home/stack/images/rhelosp7temp.repo
[rhel-7-server-openstack-7.0-rpms]
name=rhel-7-server-openstack-7.0-rpms
baseurl=http://192.168.220.10/html/repos/rhel-7-server-openstack-7.0-rpms/
gpgcheck=0
enabled=1
EOF

cp overcloud-full.qcow2 overcloud-full-orig.qcow2
# Note - virt-customize can be run with '-v' for verbose
virt-customize -a overcloud-full.qcow2 --upload rhelosp7temp.repo:/etc/yum.repos.d
virt-customize -a overcloud-full.qcow2 --update 
virt-customize -a overcloud-full.qcow2 --run-command 'yum -y install openstack-nova-serialproxy'

guestfish -a overcloud-full.qcow2 -m /dev/sda
cat /tmp/builder.log	# Will show output of the yum install
ls /usr/bin   # check for nova-serialproxy....

virt-customize -a overcloud-full.qcow2 --delete /etc/yum.repos.d/rhelosp7temp.repo

# Update only images that have been changed
source ~/stackrc
openstack overcloud image upload --image-path /home/stack/images --update-existing
```

## Deploy your overcloud with serial console enabled

* Deploy your overcloud and validate standard functionality
* Create a subdirectory in your local templates directory `mkdir /home/stack/templates/custom`
* Place all files in this repo in /home/stack/templates/custom
```
cd /home/stack
git clone https://github.com/jonjozwiak/openstack.git
cp openstack/director-examples/serialproxy/* /home/stack/templates/custom
```
* Execute the overcloud deploy with the new templates added:
``` 
-e /home/stack/templates/custom/nova-serialproxy-post-deploy.yaml
```

## Validate serial console functionality 
The Nova serial console requires websockets and is not available just by telnet or ssh.  There is a simple python wrapper for this written by Lars Kellogg-Stedman which we will use.  Below shows the process to boot a server and connect to it's console.  This assumes your OpenStack environment has already been verified and has networks, images, and keypairs ready.  

```
# Boot instance and verify you can connect
neutron net-list
PRIVNET1ID=fb777762-4047-4f32-a1de-4367cfc546aa
nova boot testserver --flavor m1.tiny --image cirros-0.3.4-x86_64 --key-name adminkey \
  --security-groups default --nic net-id=$PRIVNET1ID
FLOATINGIP=$(neutron floatingip-create pubnet1 | grep floating_ip_address | awk '{print $4}')
nova add-floating-ip testserver $FLOATINGIP
ping -c 1 $FLOATINGIP

# Verify you get a web socket address for the instance
nova get-serial-console testserver

# Get and test a WebSockets Client
cd /root
git clone https://github.com/larsks/novaconsole.git
cd novaconsole
python setup.py install
cd /root

# Connect to the console
novaconsole testserver
```

## Caveats
Enabling Nova serialproxy results in the 'nova console-log' capability no longer functioning.  It is one or the other.  You will get an error like the following when trying to access the logs:

ERROR (ClientException): The server has either erred or is incapable of performing the requested operation. (HTTP 500) (Request-ID: req-4f2fd582-9c6b-438e-a45b-76abe3b97ab5)


