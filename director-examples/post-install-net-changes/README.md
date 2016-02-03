# Post Install Network Changes 

If you need to make network changes after deployment of the overcloud, doing a stack update will NOT modify the network.  This is because it would be very disruptive by impacting services, possibly resulting in pacemaker fencing a node.  Instead, follow this procedure:

* Perform stack-update.  This updates `/etc/os-net-config/config.json`
* Stop OpenStack services on the target node
* Run `sudo os-net-config -c /etc/os-net-config/config.json` optionally adding `--debug`
* Validate the network.  Then repeat this procedure on other hosts

Note that you may be better off making changes to the files in /etc/sysconfig/network-scripts post-deploy rather than relying on on-net-config.  

 

