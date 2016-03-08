# Plotting OpenStack Network Configuration 
plotnetcfg can be used to graph the network configuration of an OpenStack deployment.  This is a set of scripts that sets up a web-based view of these network graphs on a Director host.

## Steps to setup
Ansible will be used to deploy and configure plotnetcfg.  All commands should be run as the *stack* user.  Install ansible on your director host as follows:
```
sudo yum -y localinstall https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
sudo yum-config-manager --disable epel
sudo yum -y install --enablerepo=epel ansible
```

Generate your ansible inventory via a script
```
cd ~
git clone https://github.com/jonjozwiak/openstack.git
. ~/stackrc
cd openstack/plotnetcfg
sudo sh -c '. ~/stackrc; ./ansible_inventory.sh > /etc/ansible/hosts'
```

Run the Ansible playbook to setup plotnetcfg and graphing jobs/site
```
ansible-playbook plotnet.yml

# Run an initial graph collection
ansible-playbook create_graphs.yml
```

Note that now you should get graphs generated daily and cleaned up after 30 days

## View Graphs
Open a browser and go to http://<diretor ip address>/html/netcfg

You should see a list of graphs that have been collected and can select between them 

## References
* http://redhatstackblog.redhat.com/2015/10/15/troubleshooting-networking-with-rhel-openstack-platform-meet-plotnetcfg/
* https://code.google.com/archive/p/canviz/
