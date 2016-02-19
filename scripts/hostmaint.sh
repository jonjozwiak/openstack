#!/bin/bash
###############################################################################
# This script is used to put an OpenStack Compute Node into maintenance mode.  
# In this case, that means disabling scheduling to the node and migrating all
# instances off of it
# NOTE: This requires shared storage for instances. 
###############################################################################

usage ()
{
    echo "Usage: $0 [OPTIONS]"
    echo " -h                   Get help"
    echo " -n <node>		Hypervisor Node to change (in form of hostname)"
    echo " -a <action> 		check - check status of node"
    echo "                      disable - disable node and migrate instances off"
    echo "                      enable - enable node"
    echo " -k <keystonerc file> Path to the keystone credentials file"
    echo " 			OpenStack credentials are needed"
}

while getopts 'h:n:a:k:' OPTION
do
    case $OPTION in
        h)
            usage
            exit 0
            ;;
        n)
            export NODE=$OPTARG
            ;;
        a)
            export ACTION=$OPTARG
            if [[ ! $ACTION =~ ^(check|disable|enable)$ ]]; then 
              usage
              exit 3
            fi
            ;;
        k)
            export KEYSTONE=$OPTARG
            if [[ ! -f $KEYSTONE ]]; then
              echo "ERROR: Keystone file ($KEYSTONE) does not exist"
              exit 3
            else
              source $KEYSTONE
            fi
            ;;
        *)
            usage
            exit 3
            ;;
    esac
done

check_hypervisor ()
{
  # Check scheduling to this node
  NOVA=$(nova-manage service list | grep $NODE)
  NOVASTATE=$(echo $NOVA | awk '{print $4}')
  echo "+---------------------------------------------------------------------------+"
  echo "Scheduling Status for $NODE: $NOVASTATE"
  echo "+---------------------------------------------------------------------------+"
  echo $NOVA
 
  echo ""
  # Check instances running on this node
  INSTANCE_COUNT=$(nova hypervisor-servers $NODE | grep -v "\-\-\-\-\-" | grep -v "Hostname" | wc -l)
  echo "+---------------------------------------------------------------------------+"
  echo "$NODE is currently running $INSTANCE_COUNT instances"
  echo "+---------------------------------------------------------------------------+"
  nova hypervisor-servers $NODE | grep -v "\-\-\-\-\-" | awk '{print $2" "$4}' | column -t
  echo ""
}

disable_hypervisor ()
{
  # Disable Scheduling to the node 
  nova-manage service disable $NODE nova-compute

  # Verify Scheduling is disabled
  if [[ $(nova-manage service list | grep $NODE | grep disabled | wc -l) -eq 0 ]] ; then
     echo "Error: nova-compute not disabled on $NODE"
     nova-manage service list | grep $NODE
     exit 1
  fi

  # Check instances on the host
  INSTANCE_COUNT=$(nova hypervisor-servers $NODE | grep -v "\-\-\-\-\-" | grep -v "Hostname" | wc -l)
  
  if [[ $INSTANCE_COUNT -eq 0 ]]; then
    echo "No instances running on host $NODE."
    
    echo "OK to begin maintenance on $NODE"
  else
    # Check instances on Host 
    echo "$NODE is currently running $INSTANCE_COUNT instances"
    echo ""
    echo "Live migration will be attempted for the following instances:"
    echo ""
    nova hypervisor-servers $NODE

    # Live migrate instances off the host
    nova host-evacuate-list $NODE
    #nova live-migration <instance> <host>  # Another option here

    # Validate no instances remain 
    INSTANCE_COUNT=0
    INSTANCE_COUNT=$(nova hypervisor-servers $NODE | grep -v "\-\-\-\-\-" | grep -v "Hostname" | wc -l)
    if [[ $INSTANCE_COUNT -eq 0 ]]; then
      echo "Migration(s) successful.  No instances running on host $NODE."
      echo "OK to begin maintenance on $NODE"
    else 
      echo "ERROR: Migration failed.  $INSTANCE_COUNT instances still remain on $NODE" 
      echo ""
      echo "List of remaining instances"
      echo ""
      nova hypervisor-servers $NODE
      exit 1
    fi
  fi

}

enable_hypervisor ()
{
  # Enable Scheduling to the node 
  nova-manage service enable $NODE nova-compute

  # Verify Scheduling is enabled
  if [[ $(nova-manage service list | grep $NODE | grep enabled | wc -l) -eq 0 ]] ; then
     echo "Error: nova-compute not enabled on $NODE"
     nova-manage service list | grep $NODE
     exit 1
  fi

}

# Main 
if [[ $NODE == "" ]]; then
  echo "ERROR: Node is null"
  exit 1
fi

# Validate OpenStack credentials 
if [[ -z $OS_AUTH_URL || -z $OS_TENANT_NAME || -z $OS_USERNAME || -z $OS_PASSWORD ]] ; then
  echo "ERROR: One or more OpenStack variables not specified"
  exit 1
fi

# Validate you can access nova
nova hypervisor-list > /dev/null 2>&1
if [[ $? -ne 0 ]]; then
  echo "ERROR: nova not responding.  Are your OpenStack credentials correct?"
  exit 1
fi

# Validate you can locate the hypervisor specified 
if [[ $(nova hypervisor-list | grep " $NODE " | wc -l) -eq 0 ]]; then
  echo "ERROR: nova hypervisor ($NODE) not found"
  exit 1
fi

if [[ $ACTION == "check" ]]; then
  check_hypervisor
elif [[ $ACTION == "disable" ]]; then
  disable_hypervisor
elif [[ $ACTION == "enable" ]]; then
  enable_hypervisor
else
  echo "ERROR: Action ($ACTION) not known" 
  exit 1
fi
