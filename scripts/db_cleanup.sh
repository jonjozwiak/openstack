#!/bin/bash
# 
# db_cleanup.sh - DB Cleanup Script for OpenStack.  
#
# This script checks and cleans up all Openstack Databases
# Originally this was written for Kilo and Liberty
# 
########################## Built in options available ################################
### /var/spool/cron/cinder
#PATH=/bin:/usr/bin:/usr/sbin SHELL=/bin/sh
#1 */24 * * * cinder-manage db purge 1 >>/dev/null 2>&1
####### NOTE Cinder Bug https://bugs.launchpad.net/cinder/+bug/1599830
### /var/spool/cron/keystone
#PATH=/bin:/usr/bin:/usr/sbin SHELL=/bin/sh
#*/1 0 * * * keystone-manage token_flush >>/dev/null 2>&1
### /var/spool/cron/nova
#PATH=/bin:/usr/bin:/usr/sbin SHELL=/bin/sh
#1 */12 * * * nova-manage db archive_deleted_rows --max_rows 100 >>/dev/null 2>&1
### NOTE This seemed to do nothing in Kilo and Liberty
### http://lists.openstack.org/pipermail/openstack-dev/2015-November/079701.html
### Should be fixed in Newton: https://bugzilla.redhat.com/show_bug.cgi?id=960644
### /var/spool/cron/ceilometer
#PATH=/bin:/usr/bin:/usr/sbin SHELL=/bin/sh
#1 0 * * * sleep $(($(od -A n -t d -N 3 /dev/urandom) % 86400)) && ceilometer-expirer
### /var/spool/cron/heat
#PATH=/bin:/usr/bin:/usr/sbin SHELL=/bin/sh
#1 0 * * * heat-manage purge_deleted -g days 1 >>/dev/null 2>&1
### NOTE This didn't clean up the service table on Kilo
### Glance has no build in DB purge. 
### Spec upstream at https://blueprints.launchpad.net/glance/+spec/database-purge
### Appears to have merged in December 2015: https://review.openstack.org/#/c/216782/
#######################################################################################

# Note, to describe all tables in a db: 
# db=nova
# mysql -Nse 'show tables' $db | while read table; do echo -n "-----$table-----"; mysql -Nse "describe $table" $db; done
#
# Note, to track down relationships: 
# mysql
# select TABLE_NAME,COLUMN_NAME,CONSTRAINT_NAME, REFERENCED_TABLE_NAME,REFERENCED_COLUMN_NAME FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE WHERE REFERENCED_TABLE_SCHEMA = 'glance' AND REFERENCED_TABLE_NAME='artifacts';


function usage {
  echo "Usage:	$0				# Runs all checks"
  echo "	$0 check			# Runs all checks"
  echo "	$0 check_cinder		# Checks Cinder"
  echo "	$0 check_glance		# Checks Glance"
  echo "	$0 check_heat		# Checks Heat"
  echo "	$0 check_nova		# Checks Nova"
  echo ""
  echo "	$0 clean_cinder		# Cleans up Cinder"
  echo "	$0 clean_glance		# Cleans up Glance"
  echo "	$0 clean_heat		# Cleans up Heat"
  echo "	$0 clean_nova		# Cleans up Nova"
  echo "	$0 clean_all		# Cleans Cinder, Glance, Heat, and Nova"
  exit 1
}

function check {

# Get list of databases 
case "$1" in 
    "glance" ) DATABASES="glance" ;;
    "cinder" ) DATABASES="cinder" ;;
    "heat" ) DATABASES="heat" ;;
    "nova" ) DATABASES="nova" ;;
    *) DATABASES=$(mysql -Nse "show databases;") ;;
esac

for db in $DATABASES 
do
  if [[ $db == "information_schema" ]] || [[ $db == "performance_schema" ]] || [[ $db == "mysql" ]] ; then
    continue
  fi

  # DB tables to skip (no 'deleted' column)
  case $db in 
      ceilometer )
          printf "*** Ceilometer does not store deleted items in the database \n\n"
          continue ;;
      cinder ) 
          SKIP_TABLES="('driver_initiator_data', 'image_volume_cache_entries', 'migrate_version')" ;;
      glance )
          SKIP_TABLES="('artifact_blob_locations', 'artifact_blobs', 'artifact_dependencies', 'artifact_properties', 'artifact_tags', 'metadef_namespace_resource_types', 'metadef_namespaces', 'metadef_objects', 'metadef_properties', 'metadef_resource_types', 'metadef_tags', 'migrate_version', 'task_info')" ;; 
      heat )
          SKIP_TABLES="('event', 'migrate_version', 'raw_template', 'resource', 'resource_data', 'snapshot', 'software_config', 'software_deployment', 'stack_lock', 'stack_tag', 'sync_point', 'user_creds', 'watch_data', 'watch_rule')" ;;
      ironic )
          printf "*** Ironic does not store deleted items in the database \n\n" 
          continue ;;
      keystone )
          printf "*** Keystone does not store deleted items in the database\n" 
          printf "*** Make certain to implement an expired token flush! \n"
          continue ;;
      neutron )
          printf "\n*** Neutron does not store deleted items in the database\n\n"
          continue ;;
      nova )
          SKIP_TABLES="('migrate_version', 'tags')" ;;
      sahara )
          printf "*** Sahara does not store deleted items in the database\n\n"
          continue ;;
      trove )
          SKIP_TABLES="('capabilities', 'capability_overrides', 'conductor_lastseen', 'datastore_versions', 'datastores', 'dns_records', 'migrate_version', 'quota_usages', 'quotas', 'reservations', 'root_enabled_history', 'service_images', 'service_statuses', 'usage_events')" ;;
      * )
          SKIP_TABLES="('')" ;;
  esac

# Check Database for deleted records: 
printf "+---------------+----------------------------------------+---------------+\n"
printf "|%-15s|%-40s|%-15s|\n" " Database" " Table" " Deleted Count"
printf "+---------------+----------------------------------------+---------------+\n"
#mysql -Nse "show tables from nova where tables_in_nova NOT LIKE ('shadow_%') AND tables_in_nova NOT IN ('migrate_version', 'tags');" nova | while read table 
#mysql -Nse "show tables from $db where tables_in_$db NOT LIKE ('shadow_%') AND tables_in_$db NOT IN ('migrate_version', 'tags');" $db | while read table 
mysql -Nse "show tables from $db where tables_in_$db NOT LIKE ('shadow_%') AND tables_in_$db NOT IN $SKIP_TABLES;" $db | while read table 
do
  COUNT=""
  #COUNT=$(mysql -Nse "select count(*) from $table where deleted != 0" $db;)
  COUNT=$(mysql -Nse "select count(*) from $table where deleted_at is not null" $db;)
  printf "|%-15s|%-40s|%-15s|\n" " $db" " $table" " $COUNT"
done

if [[ $(mysql -Nse 'show tables' $db | wc -l) -eq 0 ]]; then
  printf "|%-15s|%-40s|%-15s|\n" " $db" "" ""
fi


printf "+---------------+----------------------------------------+---------------+\n\n"

done

} # End function check

function clean_cinder {
  printf "***** Cleaning up Cinder Deleted Records *****\n\n"

  echo "Not touching backups, cgsnapshots, consistencygroups, encryption, iscsi_targets, or transfers"
  echo ""

  # Backups untested -- leaving commented out 
  #echo "Removing records from backups"
  #mysql --database='cinder' --execute "DELETE FROM backups WHERE deleted_at IS NOT NULL);"

  echo "Removing records from snapshot_metadata"
  mysql --database='cinder' --execute "DELETE FROM snapshot_metadata WHERE snapshot_id IN (SELECT id FROM snapshots WHERE deleted_at IS NOT NULL);"

  echo "Removing snapshot related records from volume_glance_metadata"
  mysql --database='cinder' --execute "DELETE FROM volume_glance_metadata WHERE snapshot_id IN (SELECT id FROM snapshots WHERE deleted_at IS NOT NULL);"

  echo "Removing records from snapshots"
  mysql --database='cinder' --execute "DELETE FROM snapshots WHERE volume_id IN (SELECT id FROM volumes WHERE deleted_at IS NOT NULL);"

  echo "Removing volume related records from volume_glance_metadata"
  mysql --database='cinder' --execute "DELETE FROM volume_glance_metadata WHERE volume_id IN (SELECT id FROM volumes WHERE deleted_at IS NOT NULL);"

  echo "Removing volume related records from volume_attachment"
  mysql --database='cinder' --execute "DELETE FROM volume_attachment WHERE volume_id IN (SELECT id FROM volumes WHERE deleted_at IS NOT NULL);"

  echo "Removing volume related records from volume_metadata"
  mysql --database='cinder' --execute "DELETE FROM volume_metadata WHERE volume_id IN (SELECT id FROM volumes WHERE deleted_at IS NOT NULL);"

  echo "Removing volume related records from volume_admin_metadata"
  mysql --database='cinder' --execute "DELETE FROM volume_admin_metadata WHERE volume_id IN (SELECT id FROM volumes WHERE deleted_at IS NOT NULL);"
  
  echo "Removing records from volumes"
  mysql --database='cinder' --execute "DELETE FROM volumes WHERE deleted_at IS NOT NULL;"

  echo "Removing records from reservations"
  mysql --database='cinder' --execute "DELETE FROM reservations WHERE deleted_at IS NOT NULL;"

  echo "Removing records from quotas"
  mysql --database='cinder' --execute "DELETE FROM quotas WHERE deleted_at IS NOT NULL;"

  echo "Removing records from quota_usages"
  mysql --database='cinder' --execute "DELETE FROM quota_usages WHERE deleted_at IS NOT NULL;"

  echo "Removing records from quota_classes"
  mysql --database='cinder' --execute "DELETE FROM quota_classes WHERE deleted_at IS NOT NULL;"

  echo "Removing records from volume_type_extra_specs"
  mysql --database='cinder' --execute "DELETE FROM volume_type_extra_specs WHERE volume_type_id IN (SELECT id FROM volume_types WHERE deleted_at IS NOT NULL);"

  echo "Removing records from volume_type_projects"
  mysql --database='cinder' --execute "DELETE FROM volume_type_projects WHERE volume_type_id IN (SELECT id FROM volume_types WHERE deleted_at IS NOT NULL);"

  echo "Removing records from volume_types"
  mysql --database='cinder' --execute "DELETE FROM volume_types WHERE deleted_at IS NOT NULL;"

  echo "Removing records from quality_of_service_specs"
  # Note specs_id references id in the same table.  Need to do this in 2 commands 
  ### Also note bug https://bugs.launchpad.net/cinder/+bug/1599830
  mysql --database='cinder' --execute "DELETE FROM quality_of_service_specs WHERE deleted_at IS NOT NULL AND specs_id IS NOT NULL;"
  mysql --database='cinder' --execute "DELETE FROM quality_of_service_specs WHERE deleted_at IS NOT NULL;"

  echo "Removing records from services"
  mysql --database='cinder' --execute "DELETE FROM services WHERE deleted_at IS NOT NULL;"

} # End function clean_cinder

function clean_glance {
  printf "***** Cleaning up Glance Deleted Records *****\n\n"

  echo "Not cleaning up artifacts tables as I could not test"
  echo ""

  #echo "Removing artifacts related records from artifact_blob_locations"
  #mysql --database='glance' --execute "DELETE FROM artifact_blob_locations WHERE blob_id IN (SELECT id FROM artifact_blobs WHERE artifact_id IN (SELECT id FROM artifacts WHERE deleted_at IS NOT NULL));"
    

  #echo "Removing artifacts related records from artifact_blobs"
  #mysql --database='glance' --execute "DELETE FROM artifact_blobs WHERE artifact_id IN (SELECT id FROM artifacts WHERE deleted_at IS NOT NULL);"

  #echo "Removing artifacts related records from artifact_dependencies"
  #mysql --database='glance' --execute "DELETE FROM artifact_dependencies WHERE artifact_source IN (SELECT id FROM artifacts WHERE deleted_at IS NOT NULL);"
  #mysql --database='glance' --execute "DELETE FROM artifact_dependencies WHERE artifact_dest IN (SELECT id FROM artifacts WHERE deleted_at IS NOT NULL);"
  #mysql --database='glance' --execute "DELETE FROM artifact_dependencies WHERE artifact_origin IN (SELECT id FROM artifacts WHERE deleted_at IS NOT NULL);"

  #echo "Removing artifacts related records from artifact_properties"
  #mysql --database='glance' --execute "DELETE FROM artifact_properties WHERE artifact_id IN (SELECT id FROM artifacts WHERE deleted_at IS NOT NULL);"

  #echo "Removing artifacts related records from artifact_tags"
  #mysql --database='glance' --execute "DELETE FROM artifact_tags WHERE artifact_id IN (SELECT id FROM artifacts WHERE deleted_at IS NOT NULL);"

  #echo "Removing records from artifacts"
  #mysql --database='glance' --execute "DELETE FROM artifacts WHERE deleted_at IS NOT NULL;"

  echo "Removing images related records from image_locations"
  mysql --database='glance' --execute "DELETE FROM image_locations WHERE image_id IN (SELECT id FROM images WHERE deleted_at IS NOT NULL);"

  echo "Removing images related records from image_members"
  mysql --database='glance' --execute "DELETE FROM image_members WHERE image_id IN (SELECT id FROM images WHERE deleted_at IS NOT NULL);"

  echo "Removing images related records from image_properties"
  mysql --database='glance' --execute "DELETE FROM image_properties WHERE image_id IN (SELECT id FROM images WHERE deleted_at IS NOT NULL);"

  echo "Removing images related records from image_tags"
  mysql --database='glance' --execute "DELETE FROM image_tags WHERE image_id IN (SELECT id FROM images WHERE deleted_at IS NOT NULL);"

  echo "Removing records from images"
  mysql --database='glance' --execute "DELETE FROM images WHERE deleted_at IS NOT NULL;"

  echo "Removing records from tasks"
  mysql --database='glance' --execute "DELETE FROM tasks WHERE deleted_at IS NOT NULL;"

} # End function clean_glance

function clean_heat {
  printf "***** Cleaning up Heat Deleted Records *****\n\n"

  echo "Removing records from service"
  mysql --database='heat' --execute "DELETE FROM service WHERE deleted_at IS NOT NULL;"

  echo "Removing records from event related to deleted stacks"
  mysql --database='heat' --execute "DELETE FROM event WHERE stack_id IN (SELECT id from stack WHERE deleted_at IS NOT NULL);"

  echo "Removing records from stack_tag related to deleted stacks"
  mysql --database='heat' --execute "DELETE FROM stack_tag WHERE stack_id IN (SELECT id from stack WHERE deleted_at IS NOT NULL);"

  echo "Removing records from stack"
  mysql --database='heat' --execute "DELETE FROM stack WHERE deleted_at IS NOT NULL;"

} # End function clean_heat

function clean_nova {
  printf "***** Cleaning up Nova Deleted Records *****\n\n"

  echo "Removing records from instance_type_extra_specs"
  mysql --database='nova' --execute "DELETE FROM instance_type_extra_specs WHERE instance_type_id IN (SELECT id from instance_types WHERE deleted_at IS NOT NULL);"

  echo "Removing records from instance_type_projects"
  mysql --database='nova' --execute "DELETE FROM instance_type_projects WHERE instance_type_id IN (SELECT id from instance_types WHERE deleted_at IS NOT NULL);"

  echo "Removing records from instance_types"
  mysql --database='nova' --execute "DELETE FROM instance_types WHERE deleted_at IS NOT NULL;"

  echo "Removing records from instance_group_policy"
  mysql --database='nova' --execute "DELETE FROM instance_group_policy WHERE group_id IN (SELECT id from instance_groups WHERE deleted_at IS NOT NULL);"

  echo "Removing records from instance_group_member"
  mysql --database='nova' --execute "DELETE FROM instance_group_member WHERE group_id IN (SELECT id from instance_groups WHERE deleted_at IS NOT NULL);"

  echo "Removing records from instance_groups"
  mysql --database='nova' --execute "DELETE FROM instance_groups WHERE deleted_at IS NOT NULL;"

  echo "Removing records from floating_ips"
  mysql --database='nova' --execute "DELETE FROM floating_ips WHERE deleted_at IS NOT NULL;"

  echo "Removing records from reservations"
  mysql --database='nova' --execute "DELETE FROM reservations WHERE deleted_at IS NOT NULL;"

  echo "Removing records from quotas"
  mysql --database='nova' --execute "DELETE FROM quotas WHERE deleted_at IS NOT NULL;"

  echo "Removing records from agent_builds"
  mysql --database='nova' --execute "DELETE FROM agent_builds WHERE deleted_at IS NOT NULL;"

  echo "Removing records from key_pairs"
  mysql --database='nova' --execute "DELETE FROM key_pairs WHERE deleted_at IS NOT NULL;"

  echo "Removing records from aggregate_metadata"
  mysql --database='nova' --execute "DELETE FROM aggregate_metadata WHERE aggregate_id IN (SELECT id from aggregates WHERE deleted_at IS NOT NULL);"

  echo "Removing records from aggregate_hosts"
  mysql --database='nova' --execute "DELETE FROM aggregate_hosts WHERE aggregate_id IN (SELECT id from aggregates WHERE deleted_at IS NOT NULL);"

  echo "Removing records from aggregates"
  mysql --database='nova' --execute "DELETE FROM aggregates WHERE deleted_at IS NOT NULL;"

  echo "Removing records from instance_faults"
  mysql --database='nova' --execute "delete from instance_faults where instance_faults.instance_uuid in (SELECT uuid FROM instances WHERE deleted_at IS NOT NULL);"

  echo "Removing records from compute_nodes"
  mysql --database='nova' --execute "DELETE FROM compute_nodes WHERE deleted_at IS NOT NULL"

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
} # End function clean_nova

function clean_trove {
  echo "This function not implemented.  Exiting"
  exit 0 
} # End function clean_trove


function clean_all {
  clean_cinder
  clean_glance
  clean_heat
  clean_nova
} # End function clean_all

############
### Main ### 
############

case "$1" in 
    "" ) check ;;
    "check" ) check ;;
    "check_cinder" ) check cinder ;;
    "check_glance" ) check glance ;;
    "check_nova" ) check nova ;;
    "check_heat" ) check heat ;;
    "clean_cinder" ) clean_cinder ;;
    "clean_glance" ) clean_glance ;;
    "clean_heat" ) clean_heat ;;
    "clean_nova" ) clean_nova ;;
    "clean_all" ) clean_all ;;
    *) usage ;;
esac
