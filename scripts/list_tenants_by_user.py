#!/usr/bin/python
#
# This script lists all tenants that a user belongs to
#
## You must have your environment variables set
## OS_USERNAME, OS_PASSWORD, and OS_AUTH_URL

from keystoneclient.v2_0 import client
from keystoneclient.v2_0 import tokens

import os
import requests
import sys
import prettytable

# Pull in env variables.  Error if unset
os_username=os.environ.get('OS_USERNAME')
os_password=os.environ.get('OS_PASSWORD')
os_auth_url=os.environ.get('OS_AUTH_URL')

if not os_username:
    try: 
        raise Exception("You must provide a user name through env[OS_USERNAME].")
    except Exception as error:
        print(error)
        sys.exit(1)


if not os_password:
    try:
        raise Exception("You must provide a password through env[OS_PASSWORD].")
    except Exception as error:
        print(error)
        sys.exit(1)

if not os_auth_url:
    try:
        raise Exception("You must provide a auth url through env[OS_AUTH_URL].")
    except Exception as error:
        print(error)
        sys.exit(1)

# keystone = client.Client(username=username, password=password, tenant_name=tenant_name, auth_url=auth_url)
keystone = client.Client(username=os_username, password=os_password, auth_url=os_auth_url)
token = keystone.auth_token
headers = {'X-Auth-Token': token }
#tenant_url = auth_url
tenant_url = os_auth_url
tenant_url += '/tenants'
r = requests.get(tenant_url, headers=headers)
tenant_data = r.json()
print ""
print "User '" + os_username + "' belongs to the following tenants:"
tenants_list = tenant_data['tenants']

pt = prettytable.PrettyTable(["ID", "Name"], caching=False)
pt.aligns = ['l', 'l']
for tenant in tenants_list:
    pt.add_row([tenant['id'], tenant['name']])
print pt

