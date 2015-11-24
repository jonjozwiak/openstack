# This is an OSP 7 puppet manifest to deploy trove in an HA deployment with 
# OSP Director
# This will only run on a host with 'controller' in the name.  It is meant to only execute on OpenStack controller nodes

if $hostname =~ /controller/ {
  notice("Controller Found - Applying Trove Configuration")

  # Create the load balancer setup
  $trove		= true,
  $trove_certificate	= undef,
  $controller_host      = undef,
  $controller_node_ips 	= split(hiera('controller_node_ips'), ',')
  $controller_node_names = split(downcase(hiera('controller_node_names')), ',')
  $controller_hosts     => $controller_node_ips,
  $controller_hosts_names => $controller_node_names,
  $public_virtual_ip	= hiera(tripleo::loadbalancer::public_virtual_ip)

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
  $trove_api_vip = hiera('$trove_api_vip', $nova_api_vip)
  if $trove_bind_certificate {
    $trove_bind_opts = {
      "${trove_api_vip}:8779" => [],
      "${public_virtual_ip}:13779" => ['ssl', 'crt', $trove_bind_certificate],
    }
  } else {
    $trove_bind_opts = {
      "${trove_api_vip}:8779" => [],
      "${public_virtual_ip}:8779" => [],
    }
  }

  if $trove {
    haproxy::listen { 'trove':
      bind             => $trove_bind_opts,
      collect_exported => false,
    }
    haproxy::balancermember { 'trove':
      listening_service => 'trove',
      ports             => '8779',
      ipaddresses       => hiera('trove_api_node_ips', $controller_hosts_real),
      server_names      => $controller_hosts_names_real,
      options           => ['check', 'inter 2000', 'rise 2', 'fall 5'],
    }
  }


  # Create the database schema
  if $::hostname == downcase(hiera('bootstrap_nodeid')) {
    $pacemaker_master = true
    $sync_db = true
  } else {
    $pacemaker_master = false
    $sync_db = false
  }

  if $sync_db {
    $allowed_hosts = ['%',hiera('mysql_bind_host'),hiera('mysql_vip')]
    class { '::trove::db::mysql':
      require       => Exec['galera-ready'],
      host	    => hiera('mysql_vip'),
      allowed_hosts => $allowed_hosts,
    }
  }

  $rabbit_nodes = hiera('rabbit_node_ips')
  # Install Trove Services
  class { '::trove
    $rabbit_hosts                 => hiera('rabbit_node_ips'),
    $rabbit_use_ssl               => False,
    $rabbit_port                  => hiera('rabbitmq::port'),
    $rabbit_userid                => hiera('trove::rabbit_userid'),
    $rabbit_password              => hiera('trove::rabbit_password'),
    $database_connection          => "mysql://${trove::db::mysql::user}:${trove::db::mysql::password}@${mysql_vip}/${trove::db::mysql::dbname}",
    $nova_proxy_admin_user        => hiera('trove::nova_proxy_admin_user'),
    $nova_proxy_admin_tenant_name => hiera('trove::nova_proxy_admin_tenant_name'),
    $nova_proxy_admin_pass        => hiera('trove::nova_proxy_admin_pass'),
    $nova_compute_url             => "http://${nova_api_vip}:8774/v2",
    $cinder_url                   => "http://${cinder_api_vip}:8776/v1",
    $swift_url                    => "http://${swift_proxy_vip}:8080/v1/AUTH_",
  }

  # Use nova's api bind host if trove's doesn't exist
  $bind_host = hiera('$trove_api_network', $nova::api::api_bind_address)
  $trove_auth_url = "http://${keystone_public_api_vip}:5000/v2.0"
  class { '::trove::api':
    manage_service => false,
    enabled        => false,
    bind_host         => $bind_host,
    enabled           => true,
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

  # Setup Pacemaker Resources
  pacemaker::resource::service { $::trove::params::api_service_name :
    clone_params => 'interleave=true',
    require      => Pacemaker::Resource::Service[$::trove::params::service_name],
  }
  pacemaker::resource::service { $::trove::params::conductor_service_name :
    clone_params => 'interleave=true',
  }
  pacemaker::resource::service { $::trove::params::taskmanager_service_name :
    clone_params => 'interleave=true',
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
	

  # Setup Trove Service/Endpoint in Keystone 
  class { '::trove::keystone::auth':
    region           => hiera('trove::keystone::auth::region'),
    password         => hiera('trove::keystone::auth::password'),
    admin_url        => "http://${::tripleo::loadbalancer::internal_api_virtual_ip}:8779/v1.0/%(tenant_id)s",
    internal_url     => "http://${::tripleo::loadbalancer::internal_api_virtual_ip}:8779/v1.0/%(tenant_id)s",
    public_url       => "http://${::tripleo::loadbalancer::public_virtual_ip}:8779/v1.0/%(tenant_id)s",
  }

} else { 
  notice("Host is not a controller.  Skipping Trove configuration")
}
