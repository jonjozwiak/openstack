# Set netif names for standard nic naming

This states how to modify glance images for default nic naming (eth0, eth1, etc) rather than enp2s0, enp3s0, etc

Do this in the image prior to image upload into glance
```
virt-customize -a overcloud-full.qcow2 --run-command 'sudo sed -i s/net.ifnames=0/net.ifnames=1/g /etc/default/grub'
virt-customize -a overcloud-full.qcow2 --run-command 'sudo grub2-mkconfig -o /boot/grub2/grub.cfg'
openstack overcloud image upload --image-path /home/stack/images
```
