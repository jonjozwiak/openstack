# Device Mapper in Overcloud

The device-mapper-multipath package is currently not part of overcloud images.  This is a current bug: https://bugzilla.redhat.com/show_bug.cgi?id=1257903

To add this, here is one approach: 

1. Create local repos for osp/osp-d and local repo file
2. Install package into image
```
virt-customize -v --upload rhelosp.repo:/etc/yum.repos.d/rhelosp.repo -a overcloud-full.qcow2
virt-customize -v --no-logfile -a overcloud-full.qcow2 --install device-mapper-multipath
virt-customize -v --no-logfile -a overcloud-full.qcow2 --run-command 'rm -f /etc/yum.repos.d/rhelosp.repo'
```
3. Upload the image to your undercloud as normal

