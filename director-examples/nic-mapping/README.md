# Per node NIC mapping 
If you cannot get your NICs to deploy in the correct order, you can introduce per-node NIC mapping: 

Apply per-node mapping: 
* https://github.com/openstack/tripleo-heat-templates/blob/master/puppet/extraconfig/pre_deploy/per_node.yaml

* https://github.com/openstack/tripleo-heat-templates/blob/master/puppet/extraconfig/pre_deploy/per_node.yaml

Then each node needs an /etc/os-net-config/mapping.yaml
https://github.com/openstack/os-net-config/blob/master/etc/os-net-config/samples/mapping.yaml
