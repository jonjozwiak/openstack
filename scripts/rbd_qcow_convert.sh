#!/bin/bash
#
# This script uploads a qcow2 to Ceph, converts to raw, and registers with Glance
#
# Usage:
# . keystonerc_admin	# Source OpenStack credentials
# ./rbd_qcow_convert.sh <image to convert>
# ie: ./rbd_qcow_convert.sh cirros-0.3.4-x86_64-disk.img
# 
# *  The file must be in the directory you're running 
# * You may need to modify the pool name to match your config. 
#   You can check it: grep rbd_store_pool /etc/glance/glance-api.conf
# * You need the v1 glance API (and glance CLI).  v2 or openstack cli will not work
# * Image uploaded will be the qcow2 file name minus extension
# 
# This process is shown here: 
# https://www.sebastien-han.fr/blog/2014/11/11/openstack-glance-import-images-and-convert-them-directly-in-ceph/


QCOW2_IMAGE=$1
RBD_POOL=images

GLANCE_IMAGE_NAME="${QCOW2_IMAGE%.*}"

if [[ ! -f $QCOW2_IMAGE ]]; then
  echo "File < $QCOW2_IMAGE > not found"
  exit 1
fi 

# Verify it's qcow2
if [[ $(qemu-img info $QCOW2_IMAGE | grep format | grep qcow2| wc -l) -eq 0 ]]; then
  echo "File < $QCOW2_IMAGE > is not a qcow2 file format" 
  exit 1
fi

# Verify default format - snapshots will fail if not 2
if [[ $(grep "rbd default format" /etc/ceph/ceph.conf | grep 2 | wc -l) -eq 0 ]]; then
  echo "'rbd default format = 2' not found in /etc/ceph/ceph.conf.  Exiting"
  exit 1 
fi

QCOW2_UUID=$(uuidgen)
RAW_UUID=$(uuidgen)

# Import qcow2 image
rbd -p $RBD_POOL --image-format 2 import $QCOW2_IMAGE $QCOW2_UUID

# Convert qcow2 to raw
qemu-img convert -O raw rbd:$RBD_POOL/$QCOW2_UUID rbd:$RBD_POOL/$RAW_UUID

# Verify raw image created 
if [[ $(qemu-img info rbd:$RBD_POOL/$RAW_UUID | grep format | grep raw| wc -l) -eq 0 ]]; then
  echo "An error occurred creating raw file < rbd:$RBD_POOL/$RAW_UUID >"
  exit 1
fi

# Remove qcow2 UUID
rbd -p $RBD_POOL rm $QCOW2_UUID

# Snapshot and protect raw image so it is compliance with glance
rbd -p $RBD_POOL snap create --snap snap $RAW_UUID
rbd -p $RBD_POOL snap protect --image $RAW_UUID --snap snap

# Add to glance
glance --os-image-api-version 1 image-create --name "$GLANCE_IMAGE_NAME" --id $RAW_UUID --container-format bare --disk-format raw --location rbd://$(ceph fsid)/$RBD_POOL/$RAW_UUID/snap --is-public True

