# Using NFS to back Cinder and Glance

If you want to setup NFS as your storage backend, create shares on your NFS Server for cinder and glance with options /nfsshare_cinder *(rw,no_root_squash).  They could be 777 or correct the ownership so they will be accessible.  In my case, I kept my NFS shares with 755 permissions and then just did a chown so they were owned by the glance and cinder groups respectively.  (chown 161:161 glance ; chown 165:165 cinder)  Then configure director to use the storage:
```
cp ~/templates/environments/storage-environment.yaml ~/templates/environments/storage-environment.yaml.orig
vi ~/templates/environments/storage-environment.yaml
  CinderEnableRbdBackend: false
  CinderEnableNfsBackend: true
  NovaEnableRbdBackend: false
  GlanceBackend: file

  # If you omit or leave NfsMountOptions blank the install will fail
  # https://bugzilla.redhat.com/show_bug.cgi?id=1281870
  CinderNfsMountOptions: 'rw'
  CinderNfsServers: 'xxx.xxx.xxx.xxx:/nfsshare_cinder'

  GlanceFilePcmkManage: true
  GlanceFilePcmkFstype: nfs
  GlanceFilePcmkDevice: 'xxx.xxx.xxx.xxx:/nfsshare_glance'
  GlanceFilePcmkOptions: 'context=system_u:object_r:glance_var_lib_t:s0'
```

NOTE: Nova ephemeral instances go to your compute nodes local disk!
# You could add a pre-script to mount a share to /var/lib/nova/instances if desired.  This could enable live migration

