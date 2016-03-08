= OSP Director on VMware

NOT TESTED / CONFIRMED 

By default, VMware will not allow MAC spoofing.  To enable, go into the vSwitch properties, Edit the vSwitch properties, and go to the security tab.  On this tab, make certain to change the *MAC Address Changes* to 'Accept'.  If not set to accept, it blocks any traffic from Director that isn't the hosts MAC address and this messes up Neutron. 

Reference:
http://www.dasblinkenlichten.com/vcp-vsphere-networking-standard-vswitches/

Also for a VMware based OpenStack I *think* these are needed but not 100% certain
* Enable promiscuous mode
* Enable forged retransmits
