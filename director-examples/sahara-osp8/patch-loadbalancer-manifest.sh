#!/bin/bash
###################################################################################
# This script uses sed to add in that sahara components to the loadbalancer.pp 
# Based on: https://review.openstack.org/#/c/220859/4/manifests/loadbalancer.pp
###################################################################################
sed -i -e '/  $swift_certificate         = undef,/a \ \ $sahara_certificate        = undef,' /etc/puppet/modules/tripleo/manifests/loadbalancer.pp
sed -i -e '/  $swift_proxy_server        = false,/a \ \ $sahara                    = false,' /etc/puppet/modules/tripleo/manifests/loadbalancer.pp

sed -i -e '/    manila_api_ssl_port => 13786,/a \ \ \ \ sahara_api_port => 8386,' /etc/puppet/modules/tripleo/manifests/loadbalancer.pp
sed -i -e '/    sahara_api_port => 8386,/a \ \ \ \ sahara_api_ssl_port => 13386,' /etc/puppet/modules/tripleo/manifests/loadbalancer.pp

sed -i -e '/  if $manila_certificate {/i \ \ if $sahara_certificate { \
    $sahara_bind_certificate = $sahara_certificate \
  } else { \
    $sahara_bind_certificate = $service_certificate \
  }' /etc/puppet/modules/tripleo/manifests/loadbalancer.pp

# Note \x27 to escape the single ticks 

sed -i -e '/  $nova_api_vip = hiera/i \ \ $sahara_api_vip = hiera(\x27sahara_api_vip\x27, $controller_virtual_ip) \
  if $sahara_bind_certificate { \
    $sahara_bind_opts = { \
      "${sahara_api_vip}:${ports[sahara_api_port]}" => $haproxy_listen_bind_param, \
      "${public_virtual_ip}:${ports[sahara_api_ssl_port]}" => union($haproxy_listen_bind_param, [\x27ssl\x27, \x27crt\x27, $sahara_bind_certificate]), \
    } \
  } else { \
    $sahara_bind_opts = { \
      "${sahara_api_vip}:${ports[sahara_api_port]}" => [], \
      "${public_virtual_ip}:${ports[sahara_api_port]}" => [], \
    } \
  } \
' /etc/puppet/modules/tripleo/manifests/loadbalancer.pp

sed -i -e '/  if $glance_api {/i \ \ if $sahara { \ 
    haproxy::listen { \x27sahara\x27: \ 
      bind             => $sahara_bind_opts, \ 
      collect_exported => false, \ 
    } \ 
    haproxy::balancermember { \x27sahara\x27: \ 
      listening_service => \x27sahara\x27, \ 
      ports             => \x278386\x27, \ 
      ipaddresses       => hiera(\x27sahara_api_node_ips\x27, $controller_hosts_real), \ 
      server_names      => $controller_hosts_names_real, \ 
      options           => [\x27check\x27, \x27inter 2000\x27, \x27rise 2\x27, \x27fall 5\x27], \ 
    } \ 
  } \
' /etc/puppet/modules/tripleo/manifests/loadbalancer.pp

