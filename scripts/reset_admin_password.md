= Reset OpenStack admin password 
If for some reason you lose the OpenStack keystone admin password, the service token can be used to reset the admin password.  This process was tested with the Kilo release.  

```
export OS_SERVICE_TOKEN=$(grep admin_token /etc/keystone/keystone.conf | grep -v "^#" | awk -F '=' '{print $2}' | sed 's/ //g')
IP=<ip>
export OS_SERVICE_ENDPOINT=http://${IP}:35357/v2.0

keystone user-password-update --pass <NewPassword> admin
unset OS_SERVICE_TOKEN
unset OS_SERVICE_ENDPOINT
```

Once the password is updated, update your overcloudrc (or keystonerc_admin) and source the new file
