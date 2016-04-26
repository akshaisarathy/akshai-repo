#!/bin/bash
set -x

# -------------------------------------------------------------------------------------------------------
# 
# This script calls manila manage on an existing share and auto-mounts it on a tenant. It will have to be
# run on the Manila Controller, and the admin account on the controller has to be able to ssh to the 
# tenant, so that it can modify it's fstab entry and mount the new export location remotely. 
# 
# Usage:  
# ./automount-share  	<current-export-location>  <current-mount-point>  <friendly-share-name>  
# 			<share-type>  <pool-name>  <nfs-client-login>  <nfs-client-ip>
# 
# Example: 
# ./automount-share.sh  "10.250.118.52:/test_share"  "/home/centos/test_share"  test_share 
#			"ontap_share"  "osk-mitaka@netapp#aggr1"  centos  10.250.117.203
# 
# --------------------------------------------------------------------------------------------------------



if [ -f automount-share.log ]; then
  echo '' > automount-share.log
fi
exec 1> >(tee -a automount-share.log) 2>&1

#fill these values in accordingly
if [ "$#" -ne 7 ]; then
  echo 'ERROR. usage: ./automount-share  <current-export-location>  <current-mount-point>  <friendly-share-name>  <share-type>  <pool-name>  <nfs-client-login>  <nfs-client-ip>'
  exit 1
fi

old_export_path=$1
old_mount_point=$2
share_name=$3
share_type=$4
pool_name=$5
nfs_client_login=$6
nfs_client_ip=$7

id=$(manila manage --name "$share_name" --share-type "$share_type" "$pool_name" nfs "$old_export_path")
id=$(echo "$id" | grep ' id ' | cut -d '|' -f 3 | sed -e 's/ //g')

status=$(manila show "$id" | grep ' status ' | cut -d '|' -f 3 | sed -e 's/ //g')
while [ "$status" != 'available' ]; do
  status=$(manila show "$id" | grep ' status ' | cut -d '|' -f 3 | sed -e 's/ //g')
  sleep 1
done

export_path=$(manila show "$id" | grep "path" | cut -d '|' -f 3 | sed -e "s/ //g")
export_path=$(echo "$export_path" | sed -e "s/path=\(.*\)/\1/g")

#enable access to the manila share from NFS client
source keystonerc_admin
manila access-allow "$id" ip "$nfs_client_ip"

# fstab modification
# original_ip:/original_share  /opt/wordpress-4.4.2-3/apps/wordpress/htdocs/wordpress_media/   nfs  defaults  0 0    
# ---change to--->
# new_ip:/new_share  /opt/wordpress-4.4.2-3/apps/wordpress/htdocs/wordpress_media/   nfs  defaults  1 0

old_ip="${old_export_path%%:/*}"
ip="${export_path%%:/*}"
old_exp=$(echo "${old_export_path##*:}")
exp=$(echo "${export_path##*:}")
ssh -t "$nfs_client_login"@"$nfs_client_ip" "sudo cp /etc/fstab /etc/fstab.bk"
ssh -t "$nfs_client_login"@"$nfs_client_ip" "sudo sed -i \"s|$old_ip|$ip|1\" /etc/fstab"
ssh -t "$nfs_client_login"@"$nfs_client_ip" "sudo sed -i \"s|$old_exp|$exp|1\" /etc/fstab"
ssh -t "$nfs_client_login"@"$nfs_client_ip" "sudo umount $old_mount_point"
ssh -t "$nfs_client_login"@"$nfs_client_ip" "sudo mount -a"

exit 0
