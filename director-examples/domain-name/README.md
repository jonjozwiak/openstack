# Setting domain name for Overcloud Nodes
By default OSP Director sets a domain name of 'localdomain'.  Most people want their domain to match that of their organization.  Before deploying your overcloud, you can set this appropriately with the following: 

On your director undercloud node: 
```
sudo sed -i 's/dhcp_domain=localdomain/dhcp_domain=example.com/' /etc/nova/nova.conf
sudo openstack-service restart nova
```

And in your heat templates (again on the director undercloud node: 
```
find /home/stack/templates/ -type f -exec sed -i 's/localdomain/example.com/g' {} \; 
```

