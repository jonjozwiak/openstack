# Trove for RHEL OSP 7 / Director
This set of templates and puppet manifests are used to install and configure Trove on a RHEL OSP 7 installation deployed by OSP Director.  It uses the NodeExtraConfig hook as well as adding some hieradata and a puppet module for configuration.

Pre-requisites:
1) A running/installed OSP Director host with heat templates copied to a working directory 
``` 
cp -rp /usr/share/openstack-tripleo-heat-templates /home/stack/templates
```

**IMPORTANT:** This is ONLY developed for an HA OpenStack deployment.  It will more than likely not work on a non-HA OpenStack deployed from Director

2) Overcloud controllers MUST have repository access to install packages.  This can be local repos, Satellite, or CDN.  

# Steps to deploy Trove on OSP7 with Director

1) Get the repository as the stack user on your director host
cd /home/stack
git clone http://github.com/jonjozwiak/openstack.git

2) Add the Trove-specific data to your controller hieradata.  Note this generates a password for some parameters.  Feel free to modify the values in the yaml afterwards.
```
chmod 755 /home/stack/openstack/director-examples/osp7-trove/update-hieradata.sh
/home/stack/openstack/director-examples/osp7-trove/update-hieradata.sh
```

2) Copy puppet manifest to your manifests directory 
```
cp /home/stack/openstack/director-examples/osp7-trove/osp7-controller-trove-pacemaker.pp /home/stack/templates/puppet/manifests
```

3) Create a post-deployment override file.  Basically all the post-config hooks are described in overcloud-resource-registry-puppet.yaml.  We're just overriding the location of the post-deploy script.   Adjust this location if your templates aren't in /home/stack/templates.
```
cat << EOF > ~/templates/post-deployment.yaml
resource_registry:
  OS::TripleO::NodeExtraConfigPost: /home/stack/templates/puppet/trove-puppet.yaml
EOF
```
NOTE: I've not found a controller-specific post config capability.  Instead my puppet manifest just does a hostname regex to only match controllers

4) Copy the trove puppet yaml into the directory specified in post-deployment.yaml
```
cp /home/stack/openstack/director-examples/osp7-trove/trove-puppet.yaml /home/stack/templates/puppet/
```

5) Deploy as usual, but with '-e ~/templates/post-deployment.yaml.  For example, here's my deployment command with my advanced networking and storage customizations called out:
```
openstack overcloud deploy --templates ~/templates/ --ntp-server 108.61.56.35 --libvirt-type kvm --control-flavor control --compute-flavor compute --ceph-storage-flavor ceph --control-scale 3 --compute-scale 2 --ceph-storage-scale 3 --log-file overcloud_deployment.log --neutron-bridge-mappings datacentre:br-ex,tenant:br-tenant --neutron-network-type vlan --neutron-network-vlan-ranges tenant:1603:1610 --neutron-disable-tunneling -e ~/templates/environments/storage-environment.yaml -e ~/templates/advanced-networking.yaml -e ~/templates/post-deployment.yaml
```
 
