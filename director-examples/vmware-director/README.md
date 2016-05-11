# OSP Director on VMware

NOT TESTED / CONFIRMED 

By default, VMware will not allow MAC spoofing.  To enable, go into the vSwitch properties, Edit the vSwitch properties, and go to the security tab.  On this tab, make certain to change the *MAC Address Changes* to 'Accept'.  If not set to accept, it blocks any traffic from Director that isn't the hosts MAC address and this messes up Neutron. 

In addition you need to enable forged retransmits

Also I've seen the below set, but I think it is not required.  Just leaving it here in case... 

. Enable promiscuous mode

Reference: 
. https://access.redhat.com/solutions/1980283
. https://access.redhat.com/solutions/1985573
. http://www.dasblinkenlichten.com/vcp-vsphere-networking-standard-vswitches/

