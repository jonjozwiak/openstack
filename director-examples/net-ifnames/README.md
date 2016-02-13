# Set netif names for standard nic naming

This states how to modify overcloud images for default nic naming (eth0, eth1, etc) rather than enp2s0, enp3s0, etc

Do this in the image prior to image upload into glance
```
guestfish -a overcloud-full.qcow2
run 
list-filesystems
mount /dev/sda /
vi /etc/default/grub
# Add to the GRUB_CMDLINE_LINUX
net.ifnames=0 biosdevnames=0
exit
virt-customize -a overcloud-full.qcow2 --run-command 'sudo grub2-mkconfig -o /boot/grub2/grub.cfg'
openstack overcloud image upload --image-path /home/stack/images --update-existing
```
