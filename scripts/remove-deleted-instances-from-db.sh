#!/bin/bash

##### DON'T USE THIS.  USE THE LARGE DATASET SCRIPT INSTEAD

if [[ -f /tmp/instances_to_delete.txt ]]; then
  rm -f /tmp/instances_to_delete.txt
fi

mysql --database='nova' --execute "SELECT uuid FROM instances WHERE deleted_at IS NOT NULL INTO OUTFILE '/tmp/instances_to_delete.txt';"

# Write string of UUIDs to delete 
#INSTANCES=""
#cat /tmp/instances_to_delete.txt | while read uuid
#do 
#  if [[ $INSTANCES == "" ]]; then 
#    INSTANCES=$uuid
#  else 
#    INSTANCES="$INSTANCES, $uuid" 
#  fi 
#done

cat /tmp/instances_to_delete.txt | while read uuid
do
  mysql --database='nova' --execute "delete from instance_faults where instance_faults.instance_uuid = '$uuid';"
  mysql --database='nova' --execute "delete from instance_extra where instance_extra.instance_uuid = '$uuid';"
  mysql --database='nova' --execute "delete from migrations where migrations.instance_uuid = '$uuid';"
  mysql --database='nova' --execute "delete from instance_id_mappings where instance_id_mappings.uuid = '$uuid'"
  mysql --database='nova' --execute "delete from instance_info_caches where instance_info_caches.instance_uuid = '$uuid';"
  mysql --database='nova' --execute "delete from instance_system_metadata where instance_system_metadata.instance_uuid = '$uuid';"
  mysql --database='nova' --execute "delete from security_group_instance_association where security_group_instance_association.instance_uuid = '$uuid';"
  mysql --database='nova' --execute "delete from block_device_mapping where block_device_mapping.instance_uuid = '$uuid';"
  mysql --database='nova' --execute "delete from fixed_ips where fixed_ips.instance_uuid = '$uuid';"
  mysql --database='nova' --execute "delete from instance_actions_events where instance_actions_events.action_id in (select id from instance_actions where instance_actions.instance_uuid = '$uuid');"
  mysql --database='nova' --execute "delete from instance_actions where instance_actions.instance_uuid = '$uuid';"
  mysql --database='nova' --execute "delete from virtual_interfaces where virtual_interfaces.instance_uuid = '$uuid';"
  mysql --database='nova' --execute "delete from instances where instances.uuid = '$uuid';"
done
