# Integrating Keystone with Active Director
This set of templates allows integrating RHEL OSP 7 with Active Directory.  It is based on this document: https://access.redhat.com/documentation/en/red-hat-enterprise-linux-openstack-platform/7/integrate-with-identity-service/chapter-1-active-directory-integration.  Also note this article has similar detail: https://access.redhat.com/articles/1193253

These templates will migrate the overcloud to Keystone v3 and allow read-only access to Active Directory.  Users and Groups (Identity) come from AD while assignment (mapping users to roles) comes from OpenStack

## Pre-requisites

* A running/installed OSP Director host with heat templates copied to a working directory
``` 
cp -rp /usr/share/openstack-tripleo-heat-templates /home/stack/templates
```
* A working Active Directory environment.  See these references for assistance
  * I have some rough steps in this repo in README-ad-lab.md

## Active Directory Pre-work
There is some configuration detail you need from AD.  In addition, you will want to create a service account (an account which Keystone users to connect to AD).

* Verify your domain name (This IS case sensitive)
```
# Open a Power Shell terminal get your domain name 
Get-ADDomain | select NetBIOSName
```
If Get-ADDomain fails, you need to import the module.  It should be there in a base install.  I'm told that it could need Windows Management Framework 4.0 or Remote Server Administration Tools (RSAT).  But mine had the module.  I imported it as follows: 
```
Get-Module --ListAvailable
Import-Module ActiveDirectory
```
Reference: http://www.tomsitpro.com/articles/powershell-active-directory-cmdlets,2-801.html

* Create your LDAP lookup account
```
New-ADUser -SamAccountName svc-openstack -Name "svc-openstack" -GivenName LDAP -Surname Lookups -UserPrincipalName svc-openstack@example.com  -Enabled $false -PasswordNeverExpires $true -Path 'CN=Users,DC=example,DC=com'
## NOTE: You can find Path with Get-ADDomain | select UsersContainer
```

* Set your LDAP account password
```
Set-ADAccountPassword svc-openstack -PassThru | Enable-ADAccount
# <enter> for current password.  Then type your desired password twice
```

* Create a group for OpenStack Users.  
```
New-ADGroup -name "grp-openstack" -groupscope Global -path "CN=Users,DC=example,DC=com"
```

* Add your service account to that group
```
Add-ADGroupMember "grp-openstack" -members "svc-openstack"
```

NOTE: If your service account is disabled, you will NOT be able to bind to the domain.  Go into Active Directory Users and Computers.  Within your domain click Users, then double-click your new svc-openstack user, and go to the account tab.  Scroll down in account options and make certain the account is not disabled

* Get your LDAPS certificate public key (x509 .cer file)
http://windowsitpro.com/active-directory/how-use-ldap-over-ssl-lock-down-ad-traffic

NOTE: If you want to list a user to know what fields you are mapping, you can use 'Get-ADUser <UserName>
NOTE: If you want to list a group, Get-ADGroup <GroupName> (or Get-ADGroup <GroupName> -Filter {SamAccountName -like "Project*"})

* Save the certificate on your OSP director host in /var/www.  (The script running on the controllers will pull this in
** If you need help with this, I have steps in README-ad-lab.md with the header 'Export Certificate'

  
* Verify you can connect on port 636 (really only needed in a new lab environment)
  * Start -> Run - ldp.exe
  * Connection -> Connect
  * Server = <your fully qualified AD controller name>
  * Port = 636 
  * Leave the boxes unchecked.  
  * You should see a connection established and not see any errors.  If that is the case it works and is accepting connections.  
  * Connection -> Disconnect

## Deploy your overcloud with AD integration enabled
* Deploy your overcloud and validate standard functionality
* Create a subdirectory in your local templates directory `mkdir /home/stack/templates/custom`
* Place all files from this repo in /home/stack/templates/custom
```
cd /home/stack
git clone https://github.com/jonjozwiak/openstack.git
cp openstack/director-examples/ad-integration/* /home/stack/templates/custom
```
* Modify the ad-post-deploy.yaml variables to align with your environment
```
vi /home/stack/templates/custom/ad-post-deploy.yaml
  ldap_domain is found with Get-ADDomain | select NetBIOSName (i.e. EXAMPLE)
  ldap_server is the name of your AD server (i.e. ldaps://<fqdn>:636)
     IMPORTANT: You must be able to resolve your LDAP host name (via DNS or /etc/hosts).  
	LDAPS cannot use IP addresses due to SSL
	(Alternatively, ldap://<fqdn>:389)
  ldap_user is the account you created for ldap access (i.e. CN=svc-openstack,CN=Users,DC=example,DC=com)
  ldap_password is the password you set for the account
  ldap_suffix: The suffix of your distinguished name (i.e. DC=example,DC=com)
  ldap_user_tree is the tree where users are created in AD (i.e. CN=Users,DC=example,DC=com)
  ldap_enabled_group is the group you created in AD.  Users in this group will be visible to OpenStack 
        (i.e. CN=grp-openstack,CN=Users,DC=Users,DC=example,DC=com)
  ldap_group_tree is the path where groups are created in AD (i.e. CN=Groups,DC=example,DC=com)
  ldap_group_filter: Only groups in this filter will be seen in OpenStack 
        (i.e. CN=grp-openstack,CN=Users,DC=Users,DC=example,DC=com)
  ldap_cert_name: File name of the X509 Cert from your AD server (i.e. dc1.example.com.cer)
  ldap_cert_url: URL on the director host where overcloud can grab this file 
        (i.e. http://192.168.0.10/dc1.example.com.cer)
    NOTE: Use the provisioning IP for the director host
    NOTE: leave ldap_cert_name and ldap_cert_url blank if not doing LDAPS
```
* Execute the overcloud deploy with the new templates added:
``` 
-e /home/stack/templates/custom/ad-post-deploy.yaml
```
NOTE: You cannot have multiple NodeExtraConfigPost definitions.  If you want to
do multiple SoftwareConfigs in post deploy, you can create something like config
-post-deploy.yaml that calls a single config yaml.  Then in that config yaml you
 can have multiple SoftwareConfig and SoftwareDeployments resources.  Also, you
can use 'depends_on: deploymentname' in the definition of a SoftwareConfig if yo
u need one to complete before the other.  So in this example, copy ad-post-deploy.yaml to custom-post-deploy.yaml having the NodeExtraConfigPost pointing to custom-config.yaml.  Then in custom-config.yaml copy in the SoftwareConfig and SoftwareDeployment and parameters from ad-config.yaml.  Finally, add '-e /home/stack/templates/custom-post-deploy.yaml'... 


## Validate your Openstack AD Integration
The AD config script will create a credentials file on your controllers: /root/overcloudrc_admin_v3.  We'll source that and use if for validation
```
# Allow AD users to access projects:
LDAPDOMAIN="EXAMPLE"
openstack project create --domain $LDAPDOMAIN --enable --description "LDAP User Testing" ldaptestproject
openstack user list --domain $LDAPDOMAIN
openstack role list 
openstack role add --project ldaptestproject --user <user id> < _member_ role id>
#openstack role add --project <project name> --user <user id> < admin role id>
openstack role assignment list --role admin --user <user ID> --domain $LDAPDOMAIN
# You should now be able to log into the dashboard as this user with their AD password

# Allow AD group (and all it's users) to access projects
### NOTE - Adding an AD group does NOT give a user access to login to openstack!  
### It only gives them access to the project you've associated.  
### You still need to add the user to the grp-openstack in AD ... 
openstack project create --domain $LDAPDOMAIN --enable --description "LDAP Group Testing" ldaptestproject2
openstack group list --domain $LDAPDOMAIN
openstack role list 
openstack role add --project ldaptestproject2 --group <group id> <_member_ role id>
openstack role assignment list --role _member_ --group <group ID> 
```


## Troubleshooting 
These are just a few notes for troubleshooting.  They are by no means extensive but just a few things I ran into.  

* Look in /var/log/keystone/keystone.log.  If there are any LDAP connectivity issues they will be logged here

* LDAPS and LDAP use different ports so use the right one for your connection type.  (389 for ldap, 636 for ldaps)

* Verify you can contact the domain controller 
```
  nc -v -i 5 -w 5 dc1.example.com 636   # Or 389 for LDAP
```
  This should connect, idle for 5 seconds, and then disconnect.  
  If you get a 'Connection reset by peer' than the connection is not working correctly

* Outside of keystone, validate you can bind to the domain:
  * Non SSL - likely not possible with AD
  ```
ldapsearch -h <AD IP address> -D cn=svc-openstack,cn=users,dc=example,dc=com -w <password> 
```
  * SSL 
  ```
ldapsearch -x -H ldaps://<ad fqdn>:636 -D  cn=svc-openstack,cn=users,dc=example,dc=com -w <password> 
```
  * Add -d 1 to this command to get more verbose feedback

* If you receive an error when logging into the dashboard which says "Error: Unauthorized: Unable to retrieve usage information", there is likely a message in the nova-api.log which has "Unable to find authentication token in headers".  Make certain Nova is setup for v3 auth.  


