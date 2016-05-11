# Deploying Sahara with RHEL OSP 8 Director

Sahara is fully supported with RHEL OSP 8, but is not currently integrated with director for deployment.  It appears that all of the work was completed in the Liberty cycle, but never made it to release.  It is fairly invasive to the tripleo heat templates and may be difficult for ongoing support or upgrades as packages change.

The following are the links to the necessary template changes:

* Main Entry: https://review.openstack.org/#/c/220863/
* Abandoned Liberty Merge: https://review.openstack.org/#/c/272614/
* Load balancer puppet module change: https://review.openstack.org/#/c/220859/4/manifests/loadbalancer.pp


## Modifying Templates for Sahara

In general I don't have a good way to explain these steps.  Basically, I looked through the changes in the liberty merge entry and manually replayed them in my templates.  I've included the templates in this repo and move them as shown below.  You may want to review the changes and manually patch as the tripleo templates are likely to change...

```
# On the undercloud as the stack user
mkdir /home/stack/templates
cp -rp /usr/share/openstack-tripleo-heat-templates /home/stack/templates
cd /home/stack
git clone https://github.com/jonjozwiak/openstack.git
# Templates in openstack/director-examples/sahara-osp8

# Copy the updated Sahara templates into your templates directory
cp ~/openstack/director-examples/sahara-osp8/endpoint_map.yaml /home/stack/templates/network/endpoints/endpoint_map.yaml
cp ~/openstack/director-examples/sahara-osp8/overcloud.yaml /home/stack/templates/overcloud.yaml
cp ~/openstack/director-examples/sahara-osp8/all-nodes-config.yaml /home/stack/templates/puppet/all-nodes-config.yaml
cp ~/openstack/director-examples/sahara-osp8/controller.yaml /home/stack/templates/puppet/controller.yaml
cp ~/openstack/director-examples/sahara-osp8/hieradata/controller.yaml /home/stack/templates/puppet/hieradata/controller.yaml
cp ~/openstack/director-examples/sahara-osp8/hieradata/database.yaml /home/stack/templates/puppet/hieradata/database.yaml
cp ~/openstack/director-examples/sahara-osp8/overcloud_controller.pp /home/stack/templates/puppet/manifests/overcloud_controller.pp
cp ~/openstack/director-examples/sahara-osp8/overcloud_controller_pacemaker.pp /home/stack/templates/puppet/manifests/overcloud_controller_pacemaker.pp
```

If you happen to be using SSL you will also need to update your enable-tls.yaml to include the Sahara endpoints:
```
vi ~/templates/enable-tls.yaml
### Below the 3 Swift endpoints add the following:
    SaharaAdmin: {protocol: 'http', port: '8386', host: 'IP_ADDRESS'}
    SaharaInternal: {protocol: 'http', port: '8386', host: 'IP_ADDRESS'}
    SaharaPublic: {protocol: 'https', port: '13386', host: 'CLOUDNAME'}
```

## Modifying Triple-O client and os_cloud_config for Sahara
The tripleo client needs to be updated to set the Sahara password during deployment.  In addition, os_cloud_config needs to be modified ONLY IF using SSL.  I've included patched client files, but feel free to manually patch as well.

If you want to update manually:
```
cp /usr/lib/python2.7/site-packages/tripleoclient/v1/overcloud_deploy.py /usr/lib/python2.7/site-packages/tripleoclient/v1/overcloud_deploy.py.orig
vi /usr/lib/python2.7/site-packages/tripleoclient/v1/overcloud_deploy.py
# RedisPassword line: parameters['RedisPassword'] = passwords['OVERCLOUD_REDIS_PASSWORD']
# Add these lines below (ensuring correct indentation):
        parameters['SaharaPassword'] = (
            passwords['OVERCLOUD_SAHARA_PASSWORD'])

cp /usr/lib/python2.7/site-packages/tripleoclient/utils.py /usr/lib/python2.7/site-packages/tripleoclient/utils.py.orig
vi /usr/lib/python2.7/site-packages/tripleoclient/utils.py
# Add below OVERCLOUD_REDIS_PASSWORD line:
    "OVERCLOUD_SAHARA_PASSWORD",

cp /usr/lib/python2.7/site-packages/tripleoclient/constants.py /usr/lib/python2.7/site-packages/tripleoclient/constants.py.orig
vi /usr/lib/python2.7/site-packages/tripleoclient/constants.py
# Add below swift password_field line
    'sahara': {'password_field': 'OVERCLOUD_SAHARA_PASSWORD'},

cp /usr/lib/python2.7/site-packages/os_cloud_config/keystone.py /usr/lib/python2.7/site-packages/os_cloud_config/keystone.py.orig
vi /usr/lib/python2.7/site-packages/os_cloud_config/keystone.py
# In the Sahara stanza, add a comma at the end of the port entry and add SSL port below
        'port': 8386,
        'ssl_port': 13386,
```

If you want to update programmatically:
```
cp /usr/lib/python2.7/site-packages/tripleoclient/v1/overcloud_deploy.py /usr/lib/python2.7/site-packages/tripleoclient/v1/overcloud_deploy.py.orig
sed -i -e "/RedisPassword/a \ \ \ \ \ \ \ \ parameters['SaharaPassword'] = passwords['OVERCLOUD_SAHARA_PASSWORD']" /usr/lib/python2.7/site-packages/tripleoclient/v1/overcloud_deploy.py

cp /usr/lib/python2.7/site-packages/tripleoclient/utils.py /usr/lib/python2.7/site-packages/tripleoclient/utils.py.orig
sed -i -e '/OVERCLOUD_REDIS_PASSWORD/a \ \ \ \ "OVERCLOUD_SAHARA_PASSWORD",' /usr/lib/python2.7/site-packages/tripleoclient/utils.py

cp /usr/lib/python2.7/site-packages/tripleoclient/constants.py /usr/lib/python2.7/site-packages/tripleoclient/constants.py.orig
sed -i -e "/OVERCLOUD_SWIFT_PASSWORD/a \ \ \ \ 'sahara': {'password_field': 'OVERCLOUD_SAHARA_PASSWORD'}," /usr/lib/python2.7/site-packages/tripleoclient/constants.py

cp /usr/lib/python2.7/site-packages/os_cloud_config/keystone.py /usr/lib/python2.7/site-packages/os_cloud_config/keystone.py.orig
sed -i -e "s/        'port': 8386/        'port': 8386,/" /usr/lib/python2.7/site-packages/os_cloud_config/keystone.py
sed -i -e "/        'port': 8386,/a \ \ \ \ \ \ \ \ 'ssl_port': 13386," /usr/lib/python2.7/site-packages/os_cloud_config/keystone.py
```

Or you can just copy in my version of all files.  However, it might not align with the current package version as things get updated...

```
cp ~/openstack/director-examples/sahara-osp8/overcloud_deploy.py /usr/lib/python2.7/site-packages/tripleoclient/v1/overcloud_deploy.py
cp ~/openstack/director-examples/sahara-osp8/overcloud_deploy.py /usr/lib/python2.7/site-packages/tripleoclient/utils.py
cp ~/openstack/director-examples/sahara-osp8/overcloud_deploy.py /usr/lib/python2.7/site-packages/tripleoclient/constants.py
cp ~/openstack/director-examples/sahara-osp8/keystone.py /usr/lib/python2.7/site-packages/os_cloud_config/keystone.py
```

## Modify overcloud image to include Sahara packages

The default undercloud images do not include the necessary Sahara packages.  We could do a custom image build just to include these.  I tried using virt-customize and was struggling with the image getting corrupted.  I ended up settling on a firstboot script to point to a local repo (on my provisioning network) and do the yum install.

I've included these files in my repo:
firstboot.yaml
firstboot-install-sahara.yaml

Review the firstboot-install-sahara.yaml file as it has local repos that are specific to my deployment.  You will want to modify these appropriately.  Of course alternatively you could register with RHN or a Satellite to accomplish the same thing.  

One other issue is that the load balancer puppet manifest on the overcloud image does not have the code to create the Sahara haproxy configuration.  I've included the necessary changes in the firstboot script.  However, if the openstack-puppet-modules package happens to get updated this will likely wipe out the changes and they will need to be reapplied prior to running a new deploy to update the environment.  

I've included a script called patch-loadbalancer-manifest.sh which contains the individual sed statements

```

## Deploy OpenStack

Here's an example of deploying using network isolation and Ceph backend.  Obviously your install command may vary.  There is nothing specific to call out for Sahara here as it's all built into the core of the templates.
```
openstack overcloud deploy --templates ~/templates/ --ntp-server 0.fedora.pool.ntp.org --libvirt-type kvm --control-flavor control --compute-flavor compute --ceph-storage-flavor ceph-storage --control-scale 3 --compute-scale 2 --ceph-storage-scale 3 --neutron-tunnel-types vxlan --neutron-network-type vxlan -e ~/templates/environments/storage-environment.yaml -e ~/templates/environments/network-isolation.yaml -e ~/templates/firstboot.yaml
```
