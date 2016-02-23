= Wordpress Single Instance
This template deploys a single VM and installs wordpress on it.  

Tested in RHEL OSP 7 / Kilo with CentOS 7 guest

heat stack-create -f wordpress_single_instance.yaml -e wordpress_single_instance-env.yaml wordpress

heat stack-show wordpress 

Open a browser and connect to http://<output ip>
