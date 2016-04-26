# OSP Director on RHEV

With Director hosted in a RHEV VM, in order for PXE booting work mac spoofing must be enabled at the RHEV platform level.  If not, it will go through introspection fine, but the deployment will fail to assign IPs to the mac addresses.

The below link shows what is required to run OSP Director on RHEV:
https://access.redhat.com/solutions/2060423 
  -> This highlights the changes needed for director

Don't forget to shutdown director VM, edit -> show advanced options -> custom properties -> add macspoof=true 

RHEV/VMware Overcloud Nodes: https://access.redhat.com/solutions/1598553
  -> Talks about fencing if controllers are on RHEV 
   as well as https://access.redhat.com/solutions/2060423
