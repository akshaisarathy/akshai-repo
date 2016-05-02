# ---------------------------------------------------------------------------------------
# Installs OpenStack Liberty using PackStack: MANILA only
# Author: Akshai Parthasarathy
# Company: NetApp
# Email: akshai@netapp.com
# ---------------------------------------------------------------------------------------

#!/bin/bash
set -x

if [ -f provision-packstack-liberty.log ]; then
  echo '' > provision-packstack-liberty.log
fi
exec 1> >(tee -a provision-packstack-liberty.log) 2>&1

#fill these values in accordingly
if [ "$#" -ne 8 ]; then
  echo 'ERROR. usage: ./provision-packstack-liberty.sh <answer-file-name> <cluster-mgt-lif-ip> <svm-name> <cdot-username> <cdot-password> <external-eth-interface> <private-eth-interface> <storage-eth-interface>'
  exit 1
fi
answer_file_name="$1"
cloudONTAP_cluster_mgt_ip="$2"
svm_name="$3"
cdot_username="$4"
cdot_password="$5"
iface1="$6"
iface2="$7"
iface3="$8"

#Install PackStack

if [ -z "$(yum list installed | grep openstack-packstack | grep liberty)" ]; then
  sudo yum update -y
  sudo yum install -y "https://repos.fedorapeople.org/repos/openstack/openstack-liberty/rdo-release-liberty-1.noarch.rpm"
  sudo yum install -y openstack-packstack
  #re-install httpd
  sudo yum erase -y httpd
  sudo yum install -y httpd

  if [ $? -eq 0 ]; then
    echo Completed packstack install
  else
    echo !!!!!Error in packstack install!!!!!
    exit 1
  fi
fi

#set selinux to disabled
sudo setenforce 0
sudo sed -i "s/^\(SELINUX=\).*/\1disabled/g" /etc/sysconfig/selinux
sudo sed -i "s/^\(SELINUX=\).*/\1disabled/g" /etc/selinux/config

#stop openstack nova services. If still up, packstack install won't complete
svcs='openstack-nova-api,openstack-nova-cert,openstack-nova-consoleauth,openstack-nova-scheduler,openstack-nova-conductor,openstack-nova-compute,openstack-nova-novncproxy'

IFS=,
for s in $svcs; do
  st=$(service "$s" status)
  if [[ ! $st == *"dead"* ]]; then
    sudo service "$s" stop
  fi
done
unset IFS

#generate an answer file
sudo packstack --gen-answer-file "$answer_file_name"

#change the answer file
sudo sed -i -r "s/(CONFIG_DEFAULT_PASSWORD=).*/\1Netapp123/g" "$answer_file_name"

#install OpenStack packages
sudo sed -i -r "s/(CONFIG_MARIADB_INSTALL=).*/\1y/g" "$answer_file_name"
sudo sed -i -r "s/(CONFIG_GLANCE_INSTALL=).*/\1y/g" "$answer_file_name"
sudo sed -i -r "s/(CONFIG_CINDER_INSTALL=).*/\1y/g" "$answer_file_name"
sudo sed -i -r "s/(CONFIG_MANILA_INSTALL=).*/\1y/g" "$answer_file_name"
sudo sed -i -r "s/(CONFIG_NOVA_INSTALL=).*/\1y/g" "$answer_file_name"
sudo sed -i -r "s/(CONFIG_NEUTRON_INSTALL=).*/\1y/g" "$answer_file_name"
sudo sed -i -r "s/(CONFIG_HORIZON_INSTALL=).*/\1y/g" "$answer_file_name"
sudo sed -i -r "s/(CONFIG_SWIFT_INSTALL=).*/\1n/g" "$answer_file_name"
sudo sed -i -r "s/(CONFIG_CEILOMETER_INSTALL=).*/\1n/g" "$answer_file_name"
sudo sed -i -r "s/(CONFIG_HEAT_INSTALL=).*/\1n/g" "$answer_file_name"
sudo sed -i -r "s/(CONFIG_SAHARA_INSTALL=).*/\1n/g" "$answer_file_name"
sudo sed -i -r "s/(CONFIG_TROVE_INSTALL=).*/\1n/g" "$answer_file_name"
sudo sed -i -r "s/(CONFIG_IRONIC_INSTALL=).*/\1n/g" "$answer_file_name"
sudo sed -i -r "s/(CONFIG_CLIENT_INSTALL=).*/\1y/g" "$answer_file_name"
sudo sed -i -r "s/(CONFIG_NAGIOS_INSTALL=).*/\1n/g" "$answer_file_name"
sudo sed -i -r "s/(CONFIG_USE_EPEL=).*/\1y/g" "$answer_file_name"
sudo sed -i -r "s/(CONFIG_PROVISION_DEMO=).*/\1n/g" "$answer_file_name"

#neutron configurations in packstack
sudo sed -i -r "s/(CONFIG_NEUTRON_ML2_TYPE_DRIVERS=).*/\1vxlan,flat/g" "$answer_file_name"
sudo sed -i -r "s/(CONFIG_NEUTRON_L3_EXT_BRIDGE=).*/\1br-ex/g" "$answer_file_name"
sudo sed -i -r "s/(CONFIG_NEUTRON_OVS_BRIDGE_MAPPINGS=).*/\1exnet:br-ex,prinet:br-pri,stgnet:br-stg/g" "$answer_file_name"
sudo sed -i -r "s/(CONFIG_NEUTRON_OVS_BRIDGE_IFACES=).*/\1br-ex:$iface1,br-pri:$iface2,br-stg:$iface3/g" "$answer_file_name"
#manila configurations in packstack
sudo sed -i -r "s/(CONFIG_MANILA_BACKEND=).*/\1netapp/g" "$answer_file_name"
sudo sed -i -r "s/(CONFIG_MANILA_NETAPP_DRV_HANDLES_SHARE_SERVERS=).*/\1false/g" "$answer_file_name"
sudo sed -i -r "s/(CONFIG_MANILA_NETAPP_TRANSPORT_TYPE=).*/\1http/g" "$answer_file_name"
sudo sed -i -r "s/(CONFIG_MANILA_NETAPP_LOGIN=).*/\1$cdot_username/g" "$answer_file_name"
sudo sed -i -r "s/(CONFIG_MANILA_NETAPP_PASSWORD=).*/\1$cdot_password/g" "$answer_file_name"
sudo sed -i -r 's/(CONFIG_MANILA_NETAPP_SERVER_HOSTNAME=).*/\1'"$cloudONTAP_cluster_mgt_ip"'/g' "$answer_file_name"
sudo sed -i -r "s/(CONFIG_MANILA_NETAPP_SERVER_PORT=).*/\180/g" "$answer_file_name"
sudo sed -i -r "s/(CONFIG_MANILA_NETAPP_VSERVER=).*/\1$svm_name/g" "$answer_file_name"
sudo sed -i -r "s/(CONFIG_MANILA_NETWORK_TYPE=).*/\1neutron/g" "$answer_file_name"

#enable for debugging purposes
sudo sed -i -r "s/(CONFIG_DEBUG_MODE=).*/\1y/g" "$answer_file_name"

sudo packstack --answer-file "$answer_file_name"
status="$?"
runthrice=1
while [ $runthrice -lt 4 ]; do
  if  [ $status -ne 0 ] && ([ -n $(grep 'Could not prefetch glance_image provider' provision-packstack-liberty.log) ] || [ -n $(grep 'Error: cinder type-create iscsi returned 1 instead of one of [0]' provision-packstack-liberty.log) ]); then
    echo "!!!!WARNING: $runthrice install attempt failure. Retrying!!!!"
    sudo packstack --answer-file "$answer_file_name"
    status="$?"
    ((runthrice++))
  else 
    break
  fi
done

if [ $runthrice -lt 4 ]; then
  sudo cp /root/keystonerc_admin /home/rdouser/keystonerc_admin
  sudo chown rdouser:wheel /home/rdouser/keystonerc_admin 
  source /home/rdouser/keystonerc_admin
  #in order to successfully launch instances, we wait until all the services are up and then proceed with activities like creating instances. If instances are created immediately after, there could be errors in creation due to block devices or networking
  sleep 10

  #start any nova and neutron services that are not started 
  svcs='openstack-nova-api,openstack-nova-cert,openstack-nova-consoleauth,openstack-nova-scheduler,openstack-nova-conductor,openstack-nova-novncproxy,neutron-server,neutron-dhcp-agent,neutron-l3-agent,neutron-metadata-agent,neutron-openvswitch-agent,dnsmasq'
  IFS=,
  for s in $svcs; do
    st=$(service "$s" status)
    if [[ ! $st == *"running"* ]]; then
      sudo service "$s" start
    fi
  done
  unset IFS
  exit 0
fi

echo "!!!!!Packstack install failure: $status!!!!!!"
exit "$status"
