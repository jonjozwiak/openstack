# RHEL Host Registration to CDN or Satellite

Extra Configuration templates are provided to enable RHEL registration of your overcloud hosts.  These are part of the openstack-tripleo-heat-templates package.  On your director host the files are here: 

/usr/share/openstack-tripleo-heat-templates/extraconfig/pre_deploy/rhel-registration/

To use these, make a copy of the templates as follows:
```
cp -rp /usr/share/openstack-tripleo-heat-templates /home/stack/templates
```

Next, modify the environment file to match your RHN details.  For example:
```
vi /home/stack/templates/extraconfig/pre_deploy/rhel-registration/environment-rhel-registration.yaml
```

An Example of a RHN/CDN portal registration with activation key is as follows:
```
parameter_defaults:
  rhel_reg_activation_key: "[Activation Key]"
  rhel_reg_password: "[Your Password]"
  # find pool with 'subscription-manager list --available'
  rhel_reg_pool_id: "[Your Pool]"
  rhel_reg_repos: "rhel-7-server-rpms rhel-7-server-rh-common-rpms rhel-7-server-openstack-7.0-rpms rhel-ha-for-rhel-7-server-rpms rhel-7-server-optional-rpms"
  rhel_reg_user: "[Your User]"
  rhel_reg_method: "portal"
```
*NOTE:* To create an activation key in the portal, go to https://access.redhat.com/management/activation_keys and click *New Activation Key*

*IMPORTANT:* I like to disable all repos before enabling those I've selected.  To do this I actually need to patch the script as follows: 
```
cp ~/templates/extraconfig/pre_deploy/rhel-registration/scripts/rhel-registration ~/templates/extraconfig/pre_deploy/rhel-registration/scripts/rhel-registration.orig
sed -i -e 's/^repos=.*/repos="repos --disable=* --enable rhel-7-server-rpms"/' ~/templates/extraconfig/pre_deploy/rhel-registration/scripts/rhel-registration
```

An Example of a Satellite registration (requiring activation key).  The activation key should have the same repos as listed above

IMPORTANT: Use http.  NOT https.  This will grab the katello rpm via http.  Then it will configure your actual Satellite registration with https.
```
parameter_defaults:
  rhel_reg_activation_key: "[Activation Key]"
  rhel_reg_org: "[Satellite Org ID]"
  rhel_reg_sat_url: "http://satellite-hostname"
  rhel_reg_method: "satellite"
```

Finally, to include this, just pass the resource registry override and the environment file on your _openstack overcloud deploy_ command line: 
```
-e ~/templates/extraconfig/pre_deploy/rhel-registration/environment-rhel-registration.yaml \
-e ~/templates/extraconfig/pre_deploy/rhel-registration/rhel-registration-resource-registry.yaml
```

An alternative to using the extra config files is to specify the details directly on the 'openstack overcloud deploy' command line as follows:
```
--rhel-reg --reg-method satellite --reg-org <ORG ID#> --reg-sat-url <satellite URL> --reg-activation-key <KEY>
```
