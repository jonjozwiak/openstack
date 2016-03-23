#!/bin/bash

### This script tested with RHEL OSP 7 - Kilo

# Write a list of the instances we'll delete...
if [[ -f /tmp/instances_to_delete.txt ]]; then
  rm -f /tmp/instances_to_delete.txt
fi

mysql --database='nova' --execute "SELECT uuid FROM instances WHERE deleted_at IS NOT NULL INTO OUTFILE '/tmp/instances_to_delete.txt';"

# Efficiently remove the records (rather than looping one by one
echo "Removing records from instance_faults"
mysql --database='nova' --execute "delete from instance_faults where instance_faults.instance_uuid in (SELECT uuid FROM instances WHERE deleted_at IS NOT NULL);"
echo "Removing records from instance_metadata"
mysql --database='nova' --execute "delete from instance_metadata where instance_metadata.instance_uuid in (SELECT uuid FROM instances WHERE deleted_at IS NOT NULL);"
echo "Removing records from instance_extra"
mysql --database='nova' --execute "delete from instance_extra where instance_extra.instance_uuid in (SELECT uuid FROM instances WHERE deleted_at IS NOT NULL);"
echo "Removing records from migrations"
mysql --database='nova' --execute "delete from migrations where migrations.instance_uuid in (SELECT uuid FROM instances WHERE deleted_at IS NOT NULL);"
echo "Removing records from instance_id_mappings"
mysql --database='nova' --execute "delete from instance_id_mappings where instance_id_mappings.uuid in (SELECT uuid FROM instances WHERE deleted_at IS NOT NULL)"
echo "Removing records from instance_info_caches"
mysql --database='nova' --execute "delete from instance_info_caches where instance_info_caches.instance_uuid in (SELECT uuid FROM instances WHERE deleted_at IS NOT NULL);"
echo "Removing records from instance_system_metadata"
mysql --database='nova' --execute "delete from instance_system_metadata where instance_system_metadata.instance_uuid in (SELECT uuid FROM instances WHERE deleted_at IS NOT NULL);"
echo "Removing records from security_group_instance_association"
mysql --database='nova' --execute "delete from security_group_instance_association where security_group_instance_association.instance_uuid in (SELECT uuid FROM instances WHERE deleted_at IS NOT NULL);"
echo "Removing records from block_device_mapping"
mysql --database='nova' --execute "delete from block_device_mapping where block_device_mapping.instance_uuid in (SELECT uuid FROM instances WHERE deleted_at IS NOT NULL);"
echo "Removing records from fixed_ips"
mysql --database='nova' --execute "delete from fixed_ips where fixed_ips.instance_uuid in (SELECT uuid FROM instances WHERE deleted_at IS NOT NULL);"
echo "Removing records from instance_actions_events"
mysql --database='nova' --execute "delete from instance_actions_events where instance_actions_events.action_id in (select id from instance_actions where instance_actions.instance_uuid in (SELECT uuid FROM instances WHERE deleted_at IS NOT NULL) );"
echo "Removing records from instance_actions"
mysql --database='nova' --execute "delete from instance_actions where instance_actions.instance_uuid in (SELECT uuid FROM instances WHERE deleted_at IS NOT NULL);"
echo "Removing records from virtual_interfaces"
mysql --database='nova' --execute "delete from virtual_interfaces where virtual_interfaces.instance_uuid in (SELECT uuid FROM instances WHERE deleted_at IS NOT NULL);"
echo "Removing records from instances"
mysql --database='nova' --execute "delete from instances where deleted_at IS NOT NULL;"
