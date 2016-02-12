# Set root password for the overcloud

Do this in the image prior to image upload into glance
```
virt-customize -a overcloud-full.qcow2 --root-password password:MyPassword
```
