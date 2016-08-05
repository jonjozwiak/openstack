#!/usr/bin/env python
#
# This script checks for Orphans (where resource exists but tenant does not)
# This includes the following: 
#
# Cinder: Volumes, Snapshots, Backups
# Glance: Images
# Heat: Stacks
# Ironic: Bare Metal Nodes are tied to Nova instances and not tenants.  No Cleanup needed.
# Neutron: Networks, Subnets, Routers, Floating IPs, Ports, Security Groups
# Nova: Instances, Key Pairs 
#
# Not Checking:
# Ironic: Bare Metal Nodes are tied to Nova instances and not tenants.  No Cleanup needed.
# Keystone: Could check users with no tenants...  But not necessarily a problem
# Swift: The account reaper should do this? http://docs.openstack.org/developer/swift/overview_reaper.html

import os
import sys
import prettytable
import keystoneclient.v2_0.client as ksclient
import neutronclient.v2_0.client as neutronclient
import novaclient.client as novaclient
import glanceclient.v2.client as glanceclient
import heatclient.exc as hc_exc
import heatclient.client as heatclient
import cinderclient.v2.client as cinderclient

import prettytable


def usage():
    print "listorphans.py <object> where object is one or more of",
    print "'all'"
    print "Neutron: 'networks', 'routers', 'subnets', 'floatingips', 'security_groups', or 'ports'"
    print "Nova: 'servers', 'keypairs'"
    print "Glance: 'images'"
    print "Heat: 'stacks'"
    print "Cinder: 'volumes', 'snapshots'"

def get_credentials():
    d = {}
    d['username'] = os.environ['OS_USERNAME']
    d['password'] = os.environ['OS_PASSWORD']
    d['auth_url'] = os.environ['OS_AUTH_URL']
    d['tenant_name'] = os.environ['OS_TENANT_NAME']
    if 'OS_REGION_NAME' in os.environ:
        d['region_name'] = os.environ['OS_REGION_NAME']
    return d

def get_nova_credentials():
    d = {}
    d['username'] = os.environ['OS_USERNAME']
    d['api_key'] = os.environ['OS_PASSWORD']
    d['auth_url'] = os.environ['OS_AUTH_URL']
    d['project_id'] = os.environ['OS_TENANT_NAME']
    if 'OS_REGION_NAME' in os.environ:
        d['region_name'] = os.environ['OS_REGION_NAME']
    return d


credentials = get_credentials()
novacredentials = get_nova_credentials()
keystone = ksclient.Client(**credentials)
cinder = cinderclient.Client(**novacredentials)
neutron = neutronclient.Client(**credentials)
nova = novaclient.Client('2', **novacredentials)

glance_endpoint = keystone.service_catalog.url_for(service_type='image',endpoint_type='publicURL')
glance = glanceclient.Client(glance_endpoint,token=keystone.auth_token) 

heat_endpoint = keystone.service_catalog.url_for(service_type='orchestration',endpoint_type='publicURL')
heat = heatclient.Client('1', endpoint=heat_endpoint, token=keystone.auth_token)

def get_tenantids():
    return [tenant.id for tenant in keystone.tenants.list()]

def get_userids():
    return [user.id for user in keystone.users.list()]

def get_orphaned_neutron_objects(object):
    objects = getattr(neutron, 'list_' + object)()
    tenantids = get_tenantids()
    orphans = []
    names_to_skip = ['HA network tenant', 'HA subnet tenant', 'HA port tenant']
    device_owner_to_skip = ['network:floatingip', 'network:router_gateway', 'network:router_ha_interface']
    for object in objects.get(object):
        if object['tenant_id'] not in tenantids:
            skip=False
            for skipname in names_to_skip:
                if skipname in object['name']:
                    skip=True
            for key, value in object.items(): 
                if key == 'device_owner': 
                    for skipname in device_owner_to_skip:
                        if skipname in object['device_owner']:
                            skip=True
            if not skip:
                orphans.append([object['id'], object['name']])
    return orphans

def get_orphaned_floatingips(object):
    objects = getattr(neutron, 'list_' + object)()
    tenantids = get_tenantids()
    orphans = []
    for object in objects.get(object):
        if object['tenant_id'] not in tenantids:
            orphans.append([object['id'], object['fixed_ip_address'], object['floating_ip_address']])
    return orphans

#def get_orphaned_nova_objects(object):
def get_orphaned_nova_instances():
    objects = nova.servers.list(search_opts={'all_tenants': 1})
    tenantids = get_tenantids()
    orphans = []
    for object in objects:
        if object.tenant_id not in tenantids:
            orphans.append([object.id, object.name])
    return orphans

def get_orphaned_keypairs():
    objects = nova.keypairs.list()
    userids = get_userids()
    orphans = []
    
    for object in objects:
        kp = nova.keypairs.get(object)
        #print kp.id, kp.name, kp.user_id
        if kp.user_id not in userids:
            orphans.append([kp.id, kp.user_id])
    return orphans

def get_orphaned_images():
    objects = glance.images.list()
    tenantids = get_tenantids()
    orphans = []
   
    for object in objects:
        if object.owner not in tenantids:
            orphans.append([object.id, object.name])
    return orphans

def get_orphaned_stacks():
    # Note special policy is needed to allow listing global stacks
    # in /etc/heat/policy.json: "stacks:global_index": "rule:deny_everybody",
    # Needs to be: "stacks:global_index": "rule:context_is_admin",
    ### http://www.gossamer-threads.com/lists/openstack/dev/46973

    kwargs = {'global_tenant': True}
    
    #try: 
    #    objects = heat.stacks.list(**kwargs)
    #except Exception, e:
    #   raise e 
    #   print "/etc/heat/policy.json must have the following line to allow global heat listing by admin"
    #   print 'stacks:global_index": "rule:context_is_admin",' 
    #except exc.HTTPForbidden:
    #   print "bla"
    #   raise 'bla'
    #except:
    #   print 'stupid'
    #   raise

    objects = heat.stacks.list(**kwargs)
    tenantids = get_tenantids()
    orphans = []
    try: 
        for object in objects:
            if object.project not in tenantids:
                orphans.append([object.id, object.stack_name])
        return orphans
    except hc_exc.HTTPForbidden:
        print "***** Listing heat stacks for all users is forbidden!!! *****"
        print "Check /etc/heat/policy.json.  The stacks:global_index should read:"
        print '    "stacks:global_index": "rule:context_is_admin",'
        
        print "\n"
        print "Alternatively, get the data direct from the database with:"
        print "mysql -e 'SELECT id, name FROM stack WHERE deleted_at IS NULL AND tenant NOT IN (SELECT id FROM keystone.project);' heat"
        print "*************************************************************"
        return orphans

def get_orphaned_cinder_objects(object):
    if object == "volumes": 
        objects = cinder.volumes.list(search_opts={'all_tenants': 1})
    elif object == "snapshots":
        objects = cinder.volume_snapshots.list(search_opts={'all_tenants': 1})
    elif object == "backups":
        objects = cinder.backups.list(search_opts={'all_tenants': 1})

    tenantids = get_tenantids()
    orphans = []
    for obj in objects:
        if object == "volumes": 
            tenant_id = getattr(obj, 'os-vol-tenant-attr:tenant_id')
        elif object == "snapshots":
            tenant_id = obj.project_id
        elif object == "backups":
            #print dir(obj)
            #print obj
            tenant_id = obj.project_id 

        if tenant_id not in tenantids:
            orphans.append([obj.id, obj.name])
    return orphans



def print_result(objs, objtype, fields):
    print len(objs), 'orphaned', objtype
    if len(objs) != 0:
        pt = prettytable.PrettyTable([f for f in fields], caching=False)
        pt.align = 'l'
        for obj in objs:
            pt.add_row(obj)
        print(pt.get_string())
        print '\n'
    else:
        print '\n'



if __name__ == '__main__':
    if len(sys.argv) > 1:
        if sys.argv[1] == 'all':
            objects = [ 'networks', 'routers', 'subnets', 'floatingips', 'security_groups', 'ports', 'keypairs', 'servers', 'images', 'stacks', "volumes", "snapshots" ]
        else:
            objects = sys.argv[1:]
        for object in objects:
            if object in [ 'networks', 'routers', 'subnets', 'security_groups', 'ports' ]:
                orphans = get_orphaned_neutron_objects(object)
                fields = ['ID', 'Name']
            elif object == 'floatingips':
                orphans = get_orphaned_floatingips(object)
                fields = ['ID', 'Fixed IP Address', 'Floating IP Address']
            elif object in [ 'volumes', 'snapshots' ]:
                orphans = get_orphaned_cinder_objects(object)
                fields = ['ID', 'Name']
            elif object == 'servers':
                orphans = get_orphaned_nova_instances()
                fields = ['ID', 'Name']
            elif object == 'keypairs':
                print "NOTE: Check for Orphaned Keypairs does not work"
                print "Do this instead: mysql -e 'SELECT name, user_id FROM key_pairs WHERE deleted_at IS NULL AND user_id NOT IN (SELECT id FROM keystone.user);' nova"
                print ""
                orphans = get_orphaned_keypairs()
                fields = ['ID', 'User ID ']
            elif object == 'images':
                orphans = get_orphaned_images()
                fields = ['ID', 'Name']
            elif object == 'stacks':
                orphans = get_orphaned_stacks()
                fields = ['ID', 'Name']
            else: 
                print 'object type (', object, ') not recognized'
                sys.exit()

            print_result(orphans, object, fields)

    else:
        usage()
sys.exit(1)
