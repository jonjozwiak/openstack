= Ansible playbooks Related to OpenStack

* To install Ansible on RHEL 7 host (such as undercloud)
```
sudo yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
sudo yum -y install ansible
```

* Create inventory on undercloud 
```
. stackrc
# Grab from this repo 
sudo mv /etc/ansible/hosts /etc/ansible/hosts.$(date +%m%d%y%H%M)
sudo ./nova_ansible_inventory.sh > /etc/ansible/hosts

# Test ping 
ansible -m ping all
```


