# Wiping Disks on Deployment
If you need to wipe disks prior to deployment you can do this with a firstboot script.  

Create a wipe disk firstboot script as shown below.  Note that you have the option of running this based on hostname if you want to only wipe one node types disks.

```
mkdir -p ~/templates/custom
cat << EOF > ~/templates/custom/wipe_disk.yaml
heat_template_version: 2014-10-16 

resources: 
  userdata: 
    type: OS::Heat::MultipartMime 
    properties: 
      parts: 
      - config: {get_resource: wipe_disk} 

  wipe_disk: 
    type: OS::Heat::SoftwareConfig 
    properties: 
      config: | 
        #!/bin/bash 
        #case "$(hostname)" in 
        #  strg*) 
            for i in {b,c,d,e,f,g,i,j,k,l,m,n}; do 
              if [ -b /dev/sd${i} ]; then 
                echo "(II) Wiping disk /dev/sd${i}..." 
                sgdisk -Z /dev/sd${i} 
              fi 
            done 
        #  ;; 
        #esac 

outputs:  
  OS::stack_id: 
    value: {get_resource: userdata}
EOF
```

Create a resource registry item to call this script as follows:
```
cat << EOF > ~/templates/custom/wipe_disk_deploy.yaml
resource_registry:
 OS::TripleO::NodeUserData: /home/stack/templates/custom/wipe_disk.yaml
EOF
```

Now run your openstack overcloud deploy while referencing this script by adding:
```
-e ~/templates/custom/wipe_disk_deploy.yaml
```
