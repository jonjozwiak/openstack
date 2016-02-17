# Steps to setup Microsoft Active Directory for OpenStack integration testing

This is roughly the process I followed for setting up my AD environment.  It's worth mentioning I don't really know Active Directory and this is just for a basic lab environment for testing.  This was hosted on my local KVM laptop (Fedora 22 at the time)

## Install Windows 
I followed these directions:
http://www.freeipa.org/page/Setting_up_Active_Directory_domain_for_testing_purposes

But I'll highlight here: 
* Download the Windows 2008R2 EE VHD: http://www.microsoft.com/en-us/download/details.aspx?id=2227
  * Note that 2012R2 is available here: https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2012-r2
* Unpack the images
```
mkdir -p /tmp/vhd
cd /tmp/vhd
wget http://download.microsoft.com/download/5/4/C/54C15FA1-B3AA-4A8B-B26C-47C3BA7A20E0/WS2008R2Fullx64Ent.part01.exe
wget http://download.microsoft.com/download/5/4/C/54C15FA1-B3AA-4A8B-B26C-47C3BA7A20E0/WS2008R2Fullx64Ent.part02.rar
wget http://download.microsoft.com/download/5/4/C/54C15FA1-B3AA-4A8B-B26C-47C3BA7A20E0/WS2008R2Fullx64Ent.part03.rar
unar WS2008R2Fullx64Ent.part01.exe
```
* Convert for KVM & take a coffee break
```
cd "/tmp/vhd/WS2008R2Fullx64Ent/WS2008R2Fullx64Ent/Virtual Hard Disks"
qemu-img convert -p -f vpc -O qcow2 WS2008R2Fullx64Ent.vhd WS2008R2Fullx64Ent.qcow2
```
* Copy the image to /var/lib/libvirt/images
* Use virt-manager to create a New VM 
** Import existing disk image
** Set host name, networks, etc as you wish.  Remember, your OpenStack environment will need to be able to talk to this host! 
* Server will boot, you'll answer some questions, and it will be ready for use


## Setup Active Directory Domain
I followed these directions (Steps 5-7):
http://stef.thewalter.net/how-to-create-active-directory-domain.html

* Set IP Address
  * Start -> Network -> Change adapter settings 
  * Right click Local Area Connection -> Properties
  * Click Internet protocol version 4 (TCP/IPv$) and then click properties
  * Set IP, subnet, gateway, and DNS appropriately
  * Click OK or close to save
* Set the Machnie Name 
  * Start -> Computer.  Right click on computer and choose properties
  * Click Change Settings 
  * In the Computer name tab click Change.  
  * Set the name to what you want.  Ignore the member of domain / workgroup stuff 
  * Click OK or Close
* Setup Active Directory 
  * Start -> Server Manager -> Dashboard -> Add roles and features
  * Click Next
  * Click Next for role or feature based install 
  * Click next to only apply on the current server
  * Select AD Domain Services and DNS Server.  Click Next until it goes through the install.  (Typically I'd expect a DHCP server as well, but I'm not using it)
  * In Win2012, Select promote this server to a domain controller prior to closing the window.  On Win 2008 you do Start -> Run -> dcpromo
  * Create a new domain in a new forest
  * FQDN of the forest root domain: cloud.example.com
  * Forest Level: 2008R2	# Or 2012 R2 if doing 2012
  * Checked DNS Server		# Win 2008 only
  * Choose yes for delegation of DNS server cannot be created
  * Leave default paths  	# Win2012 - Leave default netbios name too
  * Domain Admin Password choose what you want - Can be same or different than Administrator
  * Click Next to complete (after reviewing selections)
  * Reboot (It takes a while as it has some stuff to configure)

Note at this point you will just have base LDAP - port 389 (no LDAPS - port 636).  So everything is clear text.  It's functional, but you'd never use it in production.  

## Setup LDAPS 
I'm not sure these steps are the easiest or best way to do this, but they worked for me.  We're going to setup our domain controller as an enterprise root CA.  Afterwards we'll publish a cert for server authentication and then export it for use with OpenStack. 

References:
https://technet.microsoft.com/en-us/library/gg314535%28WS.10%29.aspx
https://technet.microsoft.com/en-us/library/gg314532%28v=ws.10%29.aspx (look at 'install an enterprise root CA')
http://social.technet.microsoft.com/wiki/contents/articles/2980.ldap-over-ssl-ldaps-certificate.aspx
https://technet.microsoft.com/en-us/library/cc875810.aspx

### Configure CA
* Server Manager -> click Roles  (Win2012R2 - Server Manager - Dashbard)
* Under roles summary click 'Add roles'
* Click next once to get to the 'Server Roles' selection.  
* Check 'Active Directory Certificate Services' and click Next (In Win2012R2 you need to configure the role after installing.  You do this by selecting the role in server manager's main view)
* Click next to move past role services.  
* Setup type should be enterprise.  
* CA type should be Root CA
* Create a new private key
* Click next to keep default cryptography
* Click next to keep default CA Name
* Click next to keep default validity period
* Click next to keep default cert database location 
* Click 'Install' after reviewing the settings
* Click 'Close' once completed

### Verify Correct install of the root CA
* Click Start -> Admin Tools -> Certification Authority 
* Verify the CA has a checkmark symbol
* Right-click the CA and click 'Properties'
* On the General tab, select 'Certificate #0' and click view certificate
* You can check the details tab to, but I think we're good here
* click OK and then Cancel 

### Publishing a Certificate that supports Server Authentication
   http://social.technet.microsoft.com/wiki/contents/articles/2980.ldap-over-ssl-ldaps-certificate.aspx --> Search for that title

* In the Certification Authority console (Start -> Admin Tools -> Certification Authority)
* Right click certificate templates and click 'Manage'
* In the certification templates console, right-click Kerberos Authentication and select 'Duplicate template' 
* You can leave as Windows Server 2003
* Set the template display name.  I chose 'LDAPoverSSL'
  * Validity period: 5 years... renewal: 6 week ... Could leave default 
* On Request Handling tab, check 'Allow private key to be exported'
* Click OK
* Go back to the Certification Authority console, expand your CA on the left, and click 'Certification Templates'
* On the right pane, right-click in an open area and click 'New' -> 'Certificate Template to Issue'
* In the Enable Certification Templates dialog box, select the template you created and click 'OK'

### Request the cert for your LDAPS domain controller 
* Click Start-> Run-> type 'mmc' and hit enter
* In the mmc window (console1), click File -> Add/Remove Snap in
* Select the 'Certificates' snap-in and click 'Add' 
  * Select 'Computer account' and click Next
  * Select 'Local computer' as we're going to use this cert for our local AD instance
  * Click 'OK' to finish
* In the console tree expand 'Certificates (Local Computer)' -> Personal 
* Right-click certificates (under Personal), click 'All Tasks', and then click 'Request New Certificate'
  * In certificate enrollment, click 'Next'
  * Leave active directory enrollment policy as is and click Next
  * Check the certificate you created above and click 'Enroll'
  * Click 'Finish' when done.  
* You should now see a new certificate in your window which you can double click to see the details.

Nearly done... Now we just need to export the cert for use while setting up our OpenStack clients to connect to AD...

### Export Certificate 
* In mmc console1 window as before, go to Certificates (local) -> personal -> certificates
* Right click the cert for your host and click All Tasks -> Export
* Click Next
* Ensure no, do not export the private key is checked and click 'Next' 
* DER encoded binary X.509 (.CER) -> Next
* choose your desired directory and name the file <fqdn>.cer.  (I think the default is /Users/<username>).  Click Next
* Click Finish
* Click OK when export is successful...

### Copy the certificate to your director node in /var/www
* I use putty for lack of a better option: http://www.chiark.greenend.org.uk/~sgtatham/putty/download.html


