  # Setup Trove Service/Endpoint in Keystone
  $trove_admin_vip = hiera('tripleo::loadbalancer::internal_api_virtual_ip')
  $trove_internal_vip = hiera('tripleo::loadbalancer::internal_api_virtual_ip')
  $trove_public_vip = hiera('tripleo::loadbalancer::public_virtual_ip')
  class { '::trove::keystone::auth':
    region           => hiera('trove::keystone::auth::region'),
    password         => hiera('trove::keystone::auth::password'),
    admin_url        => "http://${trove_admin_vip}:8779/v1.0/%(tenant_id)s",
    internal_url     => "http://${trove_internal_vip}:8779/v1.0/%(tenant_id)s",
    public_url       => "http://${trove_public_vip}:8779/v1.0/%(tenant_id)s",
  }

