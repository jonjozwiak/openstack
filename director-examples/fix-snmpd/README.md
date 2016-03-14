# How to fix 'Authentication failed for ro_snmp_user' 

OSP7 Director gives a lot of messages indicating that snmp auth fails in /var/log/ceilometer/central.log on the director host.  This is a bug as follows:

https://bugzilla.redhat.com/show_bug.cgi?id=1233251

Until fixed in deployment, you can manually resolve the issue as follows:

```
# On controller:
hiera snmpd_readonly_user_name
hiera snmpd_readonly_user_password

# On Director:
openstack-config --set /etc/ceilometer/ceilometer.conf hardware readonly_user_name <user from above>

openstack-config --set /etc/ceilometer/ceilometer.conf hardware readonly_user_password <password from above>

systemctl restart openstack-ceilometer-central.service
```
