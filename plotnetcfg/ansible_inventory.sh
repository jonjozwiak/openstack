#!/bin/bash

echo "[all:vars]"
echo "ansible_ssh_user=heat-admin"

for i in controller cephstorage compute 
do
  echo ""
  echo "[$i]"
  #count how many nodes of the same type do we have
  count=`nova list | grep ctlplane | grep $i | wc -l`
  for j in `eval echo {1..$count}`
  do
    #gather ip address of the node
    ip=`nova list | grep ctlplane | grep $i | awk {' print $12 '} | sed 's/ctlplane=//g'| head -n $j | tail -n 1`
    #gather hostname of the node
    hostname=`nova list | grep ctlplane | grep $i | awk {' print $4 '} | head -n $j | tail -n 1`
    echo "$hostname ansible_ssh_host=$ip"
  done
done

echo ""
echo "[director]"
echo "localhost ansible_connection=local"
