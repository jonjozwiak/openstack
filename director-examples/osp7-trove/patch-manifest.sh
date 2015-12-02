#!/bin/bash
###############################################################################
# This script will patch the heat templates to add the ability to deploy Trove
###############################################################################

#Add the Trove implementation (including load balancer) to the puppet manifest
cat << \EOF >> /home/stack/templates/puppet/manifests/overcloud_controller_pacemaker.pp
# SERVICES STEP 7 - TROVE CUSTOMIZATION
if hiera('step') >= 7 {
  # Configure Trove Here
  # Create the load balancer setup
  $trove                = true
  $trove_certificate    = undef
  $controller_host      = undef
  #$controller_node_ips  = split(hiera('controller_node_ips'), ',')
  #$controller_node_names = split(downcase(hiera('controller_node_names')), ',')
  $controller_hosts     = $controller_node_ips
  $controller_hosts_names = $controller_node_names
  $public_virtual_ip    = hiera('tripleo::loadbalancer::public_virtual_ip')

  if !$controller_host and !$controller_hosts {
    fail('$controller_hosts or $controller_host (now deprecated) is a mandatory parameter')
  }
  if $controller_hosts {
    $controller_hosts_real = $controller_hosts
  } else {
    warning('$controller_host has been deprecated in favor of $controller_hosts')
    $controller_hosts_real = $controller_host
  }

  if !$controller_hosts_names {
    $controller_hosts_names_real = $controller_hosts_real
  } else {
    $controller_hosts_names_real = $controller_hosts_names
  }

  if $trove_certificate {
    $trove_bind_certificate = $trove_certificate
  } else {
    $trove_bind_certificate = $trove_certificate
  }

  # Assign Trove the same VIP as nova if it isn't already defined
  $trove_api_vip = hiera('nova_api_vip')
  if $trove_bind_certificate {
    $trove_bind_opts = {
      "${trove_api_vip}:8779" => [],
      "${public_virtual_ip}:8779" => ['ssl', 'crt', $trove_bind_certificate],
    }
    $trove_options = { 'balance' => 'roundrobin', }
  } else {
    $trove_bind_opts = {
      "${trove_api_vip}:8779" => [],
      "${public_virtual_ip}:8779" => [],
    }
    $trove_options = { 'balance' => 'roundrobin', }
  }

  if $trove {
    haproxy::listen { 'trove':
      bind             => $trove_bind_opts,
      collect_exported => false,
      options          => $trove_options,
    }
    haproxy::balancermember { 'trove':
      listening_service => 'trove',
      ports             => '8779',
      ipaddresses       => hiera('nova_api_node_ips'),
      server_names      => $controller_hosts_names_real,
      options           => ['check', 'inter 2000', 'rise 2', 'fall 5'],
    }
  }
  $rabbit_nodes = hiera('rabbit_node_ips')
  # Install Trove Services
  # Manually install trove-common as puppet seems to not do this properly
  exec{ 'install-trove':
    command => '/usr/bin/yum -y install openstack-trove',
  }
  $trove_nova_api_vip = hiera('nova_api_vip', "127.0.0.1")
  $trove_cinder_api_vip = hiera('cinder_api_vip', "127.0.0.1")
  $trove_swift_proxy_vip = hiera('swift_proxy_vip', "127.0.0.1")
  class { '::trove':
    rabbit_hosts                 => hiera('rabbit_node_ips'),
    rabbit_use_ssl               => False,
    rabbit_port                  => hiera('rabbitmq::port'),
    rabbit_userid                => hiera('trove::rabbit_userid'),
    rabbit_password              => hiera('trove::rabbit_password'),
    nova_proxy_admin_user        => hiera('trove::nova_proxy_admin_user'),
    nova_proxy_admin_tenant_name => hiera('trove::nova_proxy_admin_tenant_name'),
    nova_proxy_admin_pass        => hiera('trove::nova_proxy_admin_pass'),
    nova_compute_url             => "http://${trove_nova_api_vip}:8774/v2",
    cinder_url                   => "http://${trove_cinder_api_vip}:8776/v1",
    swift_url                    => "http://${trove_swift_proxy_vip}:8080/v1/AUTH_",
  }
  # Use nova's api bind host if trove's doesn't exist
  $bind_host = hiera('$trove_api_network', hiera('nova::api::api_bind_address'))
  $trove_auth_keystone_public_api_vip = hiera('keystone_public_api_vip', "127.0.0.1")
  $trove_auth_keystone_admin_api_vip = hiera('keystone_admin_api_vip', "127.0.0.1")
  $trove_auth_url = "http://${trove_auth_keystone_public_api_vip}:5000/v2.0"
  # Add a sleep to try to stop race condition on trove-manage db_sync
  unless $pacemaker_master  {
    exec { 'sleep on non-bootstrap node to avoid trove db_sync race' :
      command => "/usr/bin/sleep 60"
    }
  }
  class { '::trove::api':
    manage_service => false,
    enabled        => false,
    bind_host         => $bind_host,
    auth_host         => hiera('keystone_public_api_vip', "127.0.0.1"),
    auth_url          => $trove_auth_url,
  }
  class { '::trove::conductor':
    auth_url          => $trove_auth_url,
    manage_service => false,
    enabled        => false,
  }
  class { '::trove::taskmanager':
    auth_url          => $trove_auth_url,
    manage_service => false,
    enabled        => false,
  }

  # Set auth_uri and identity_uri as current Trove module does not
  $trove_auth_uri = "http://${trove_auth_keystone_public_api_vip}:5000"
  $trove_identity_uri = "http://${trove_auth_keystone_admin_api_vip}:35357/"
  trove_config {
    'keystone_authtoken/auth_uri':   value => $trove_auth_uri;
    'keystone_authtoken/identity_uri': value => $trove_identity_uri;
  }

  # Set neutron_url as current trove module does not
  $trove_neutron_api_vip = hiera('neutron_api_vip', "127.0.0.1")
  $neutron_url = "http://${trove_neutron_api_vip}:9696/"
  if $neutron_url {
    trove_config { 'DEFAULT/neutron_url': value => $neutron_url }
  }

  if $pacemaker_master {
    pacemaker::resource::service { $::trove::params::api_service_name :
      clone_params => 'interleave=true',
      require      => [Pacemaker::Resource::Service[$::keystone::params::service_name],
                       Haproxy::Listen['trove'],
                       Exec['install-trove']],
    }
    pacemaker::resource::service { $::trove::params::conductor_service_name :
      clone_params => 'interleave=true',
      require      => [Exec['install-trove']],
    }
    pacemaker::resource::service { $::trove::params::taskmanager_service_name :
      clone_params => 'interleave=true',
      require      => [Exec['install-trove']],
    }

    pacemaker::constraint::base { 'keystone-then-trove-api-constraint':
      constraint_type => 'order',
      first_resource  => "${::keystone::params::service_name}-clone",
      second_resource => "${::trove::params::api_service_name}-clone",
      first_action    => 'start',
      second_action   => 'start',
      require         => [Pacemaker::Resource::Service[$::trove::params::api_service_name],
                          Pacemaker::Resource::Service[$::keystone::params::service_name]],
    }
  }  # End If pacemaker_master
} # END SERVICES INIT (STEP 7 - CUSTOM)
EOF

