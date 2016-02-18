#!/usr/bin/python
import subprocess
import socket
import re

def setup_serialproxy_controller():
 haproxy_cfg_file = "/etc/haproxy/haproxy.cfg"
 nova_internal_vip = cmd(["hiera", "tripleo::loadbalancer::internal_api_virtual_ip"])
 public_virtual_ip = cmd(["hiera", "tripleo::loadbalancer::public_virtual_ip"])
 controller_node_names = cmd(["hiera", "controller_node_names"])
 nova_api_node_ips = cmd(["hiera", "nova_api_node_ips"])
 nova_api_bind_address = cmd(["hiera", "nova::api::api_bind_address"])
 compute_port_range = "10000:20000"
 compute_proxyclient_address = cmd(["hiera", "nova::compute::vncserver_proxyclient_address"])
 compute_proxy_host = cmd(["hiera", "nova::compute::vncproxy_host"])
 
 # Remove unneeded characters from hieradata
 nova_internal_vip = nova_internal_vip.translate(None, "\n")
 public_virtual_ip = public_virtual_ip.translate(None, "\n")
 nova_api_bind_address = nova_api_bind_address.translate(None, "\n")
 compute_proxyclient_address = compute_proxyclient_address.translate(None, "\n")
 compute_proxy_host = compute_proxy_host.translate(None, "\n")
 controller_node_names = controller_node_names.translate(None, " [\"]\n") 
 nova_api_node_ips = nova_api_node_ips.translate(None, " [\"]\n") 

 nova_api_node_ips = nova_api_node_ips.split(",")
 controller_node_names = controller_node_names.split(",")
 #controller_node_names = [controller_node_names]
 #nova_api_node_ips = [nova_api_node_ips]

 # Prints per character
 print "Controllers found:"
 for (host,ip) in zip(controller_node_names, nova_api_node_ips):
  print "host: ", host ,"; ip: ", ip

 try:
  print cmd(["yum", "-y", "install", "openstack-nova-serialproxy"])
 except:
  print "Yum install openstack-nova-serialproxy failed!"

 print cmd(["openstack-config", "--set", "/etc/nova/nova.conf", "serial_console", "enabled", "true"])
 print cmd(["openstack-config", "--set", "/etc/nova/nova.conf", "serial_console", "base_url", "ws://"+nova_api_bind_address+":6083"])
 print cmd(["openstack-config", "--set", "/etc/nova/nova.conf", "serial_console", "serialproxy_host", nova_api_bind_address])
 print cmd(["openstack-config", "--set", "/etc/nova/nova.conf", "serial_console", "serialproxy_port", "6083"])

 #test to see if haproxy.cfg has already been adjusted
 proxy_cfg_adjusted = False
 proxy_conf = open(haproxy_cfg_file,"r")
 for line in proxy_conf:
  if re.search('listen nova_serialproxy',line):
   proxy_cfg_adjusted = True
 proxy_conf.close()

 if not proxy_cfg_adjusted:
  proxy_conf = open(haproxy_cfg_file,"a")
  proxy_conf.write("\n\n")
  proxy_conf.write("listen nova_serialproxy\n")
  proxy_conf.write("  bind %s:6083\n" % nova_internal_vip)
  proxy_conf.write("  bind %s:6083\n" % public_virtual_ip)
  for (host,ip) in zip(controller_node_names, nova_api_node_ips):
    proxy_conf.write("  server %s %s:6083 check fall 5 inter 2000 rise 2\n" % (host, ip))
  proxy_conf.close()
  print cmd(["systemctl", "reload", "haproxy"])
 else:
  print "INFO: Not adjusting haproxy.cfg since it appears to have the nova serialproxy config already"

 no_firewall_rule = True
 iptables_save_output = cmd(["iptables-save"])
 for line in iptables_save_output.split('\n'):
  if re.search('6083', line):
   print "INFO: iptables rule already exists for port 6083"
   no_firewall_rule = False

 if no_firewall_rule:
  print cmd(["iptables", "-I", "INPUT", "-p", "tcp", "-m", "multiport", "--dports", "6083", "-m", "comment", "--comment", "nova serialproxy incoming", "-j", "ACCEPT"])
  try:
   iptables_config_file = open("/etc/sysconfig/iptables","w")
   iptables_save_output = cmd(["iptables-save"])
   for line in iptables_save_output:
    iptables_config_file.write(line)
   iptables_config_file.close()
  except:
   print "persisting iptables rules failed!"

 print cmd(["systemctl", "disable", "openstack-nova-serialproxy.service"])
 print cmd(["systemctl", "stop", "openstack-nova-serialproxy.service"])

 # Create Pacemaker Resources
 no_pacemaker_resource = True
 # Note - should update this to only run on the hiera(bootstrap_node)
 pcs_save_output = cmd(["pcs", "resource", "show"])
 for line in pcs_save_output.split('\n'):
  if re.search('openstack-nova-serialproxy', line):
   print "INFO: Pacemaker resource "+line+" already exists"
   no_pacemaker_resource = False
 
 if no_pacemaker_resource:  
  try:
   print cmd(["pcs", "resource", "create", "openstack-nova-serialproxy", "systemd:openstack-nova-serialproxy", "--clone", "interleave=true"])
   print cmd(["pcs", "constraint", "order", "start", "openstack-nova-consoleauth-clone", "then", "openstack-nova-serialproxy-clone"])
   print cmd(["pcs", "constraint", "colocation", "add", "openstack-nova-serialproxy-clone", "with", "openstack-nova-consoleauth-clone"])
  except:
   print "pcs commands failed!"

def setup_serialproxy_compute():
 compute_port_range = "10000:20000"
 compute_proxyclient_address = cmd(["hiera", "nova::compute::vncserver_proxyclient_address"])
 compute_proxy_host = cmd(["hiera", "nova::compute::vncproxy_host"])

 # Remove unneeded characters from hieradata
 compute_proxyclient_address = compute_proxyclient_address.translate(None, "\n")
 compute_proxy_host = compute_proxy_host.translate(None, "\n")

 try:
  print cmd(["yum", "-y", "install", "openstack-nova-serialproxy"])
 except:
  print "Yum install openstack-nova-serialproxy failed!"

 print cmd(["openstack-config", "--set", "/etc/nova/nova.conf", "serial_console", "enabled", "true"])
 print cmd(["openstack-config", "--set", "/etc/nova/nova.conf", "serial_console", "listen", "0.0.0.0"])
 print cmd(["openstack-config", "--set", "/etc/nova/nova.conf", "serial_console", "proxyclient_address", compute_proxyclient_address])
 print cmd(["openstack-config", "--set", "/etc/nova/nova.conf", "serial_console", "base_url", "ws://"+compute_proxy_host+":6083"])
 print cmd(["openstack-config", "--set", "/etc/nova/nova.conf", "serial_console", "port_range", compute_port_range])


 no_firewall_rule = True
 iptables_save_output = cmd(["iptables-save"])
 for line in iptables_save_output.split('\n'):
  if re.search(compute_port_range, line):
   print "INFO: iptables rule already exists for port "+compute_port_range
   no_firewall_rule = False

 if no_firewall_rule:
  print cmd(["iptables", "-I", "INPUT", "-p", "tcp", "-m", "multiport", "--dports", compute_port_range, "-m", "comment", "--comment", "nova serialproxy incoming", "-j", "ACCEPT"])
  try:
   iptables_config_file = open("/etc/sysconfig/iptables","w")
   iptables_save_output = cmd(["iptables-save"])
   for line in iptables_save_output:
    iptables_config_file.write(line)
   iptables_config_file.close()
  except:
   print "persisting iptables rules failed!"

 print cmd(["systemctl", "enable", "openstack-nova-serialproxy.service"])
 print cmd(["systemctl", "start", "openstack-nova-serialproxy.service"])

def cmd(args):
    return subprocess.check_output(args)

def main():
 hostname = socket.gethostname()
 if "controller" in hostname:
  print("This is a controller node... continuing")
  setup_serialproxy_controller()
 elif "compute" in hostname:
  print("This is a compute node... continuing")
  setup_serialproxy_compute()
 else:
  print("Not running on a controller or compute node, so I'm not doing anything")

if __name__ == '__main__':
	main()




