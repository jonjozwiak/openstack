#!/bin/bash

STACKRC=/home/stack/stackrc
HOSTSFILE=/etc/ansible/hosts

if [[ -f $STACKRC ]]; then
  source $STACKRC
else
  echo "ERROR: $STACKRC doesn't exist"
  exit 1
fi

if [[ -f $HOSTSFILE ]]; then
  mv $HOSTSFILE $HOSTSFILE.$(date +%m%d%y_%H%M)
fi

echo "[all:vars]" >> /etc/ansible/hosts
echo "ansible_ssh_user=heat-admin" >> /etc/ansible/hosts

for i in controller cephstorage compute
do
  echo "" >> /etc/ansible/hosts
  echo "[$i]" >> /etc/ansible/hosts
  #count how many nodes of the same type do we have
  count=`nova list | grep ctlplane | grep $i | wc -l`
  if [[ $count -ne 0 ]] ; then
    for j in `eval echo {1..$count}`
    do
      #gather ip address of the node
      ip=`nova list | grep ctlplane | grep $i | awk {' print $12 '} | sed 's/ctlplane=//g'| head -n $j | tail -n 1`

      #gather hostname of the node
      hostname=`nova list | grep ctlplane | grep $i | awk {' print $4 '} | head -n $j | tail -n 1`
      echo "$hostname ansible_ssh_host=$ip" >> /etc/ansible/hosts

    done
  fi
done
