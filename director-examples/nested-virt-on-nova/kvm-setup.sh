#!/bin/bash
#########################################################################
# This script is used to setup a RHEL instance as a KVM host 
#########################################################################

# Set these variables 
RHNUSER="<youruser>"
RHNPASS="<yourpassword>"

# Verify CPU has virt extensions passed through 
if [[ $(egrep 'svm|vmx' /proc/cpuinfo | wc -l) -eq 0 ]]; then
  echo "ERROR: Virtualization extentions are not passed through"
  exit 1
fi

# Validate name resolution - Add 8.8.8.8 if not resolving
ping -c 1 www.redhat.com 2> /dev/null 1> /dev/null
if [[ $? != "0" ]]; then
  echo "Adding 8.8.8.8 to /etc/resolv.conf"
  cp /etc/resolv.conf /etc/resolv.conf.orig.$(date +%m%d%y%H%M)
  cat <<-EOF > /etc/resolv.conf
$(echo "nameserver 8.8.8.8")
$(cat /etc/resolv.conf)
EOF
fi

# Register to RHN 
subscription-manager register --username=$RHNUSER --password=$RHNPASS --auto-attach
subscription-manager repos --disable='*'
subscription-manager repos --enable='rhel-7-server-rpms'

# Install KVM packages and enable libvurt
yum -y install qemu-kvm libvirt libvirt-python libguestfs-tools virt-install
systemctl enable libvirtd && systemctl start libvirtd

# Clean up RHN Registration
subscription-manager unregister

# Enable ip forwarding 
echo "net.ipv4.ip_forward = 1" /etc/sysctl.conf
sysctl -p /etc/sysctl.conf

