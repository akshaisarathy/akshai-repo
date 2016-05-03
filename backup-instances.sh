#!/bin/bash
set -x

# -------------------------------------------------------------------------------------------------------
# backup-instances.sh 
# Author: Akshai Parthasarathy
# Company: NetApp
# Email: akshai@netapp.com
# 
# Creates a backup of multiple instances in your environment, and should be used according to a schedule.
# Set your scheduled jobs sufficiently far apart so that the previous backup completes. It is not possible 
# to take multiple backups of the same volume simultaneously. 
# 
# Tested in RDO with NetApp. Should work with other distributions. 
# 
# Example of cron job for every 90 minutes:
# 0 0,3,6,9,12,15,18,21 * * * "/root/backup-instances.sh" "vdi-ubuntu" "0" "4" "/home/centos/keystonerc_admin"
# 30 1,4,7,10,13,16,19,22 * * * "/root/backup-instances.sh" "vdi-ubuntu" "0" "4" "/home/centos/keystonerc_admin"
# 
# This will take backups the following way: 
# vdi-ubuntu0 at 0:00 (12am)
# vdi-ubuntu1 at 0:00
# vdi-ubuntu2 at 0:00
# vdi-ubuntu3 at 0:00
# vdi-ubuntu4 at 0:00
# vdi-ubuntu0 at 1:30 (1:30am)
# vdi-ubuntu1 at 1:30
# vdi-ubuntu2 at 1:30
# vdi-ubuntu3 at 1:30
# vdi-ubuntu4 at 1:30
# ...
# ...
# -------------------------------------------------------------------------------------------------------

dir=$(pwd)
exec 1> >(tee -a "$dir"'/backup-instances.log') 2>&1

echo "--------------------"
echo "Beginning new backup"
echo "$(date)"

if [ "$#" -ne 4 ]; then
  echo 'ERROR. usage: ./backup-instances.sh <instance_prefix> <begin-instance-suffix> <end-instance-suffix> <keystonerc_admin file path>'
  exit 1
fi


#function to cleanup nova images, cinder snapshots and cinder volumes
cleanup() {
  list_command=$1
  delete_command=$2
  addl_filter=$3
  id=$($list_command | grep "from_script_temporary_for_backup_" | grep -m 1 "$addl_filter" | cut -d '|' -f 2 | sed 's/ //g')
  while [ -n "$id" ]; do
     $delete_command "$id"
     id=$($list_command | grep "from_script_temporary_for_backup_" | grep -m 1 "$addl_filter" | cut -d '|' -f 2 | sed 's/ //g')
     #it takes a few seconds for openstack to delete
     sleep 5
 done    
}

source "$4"
instance_prefix="$1"
begin="$2"
end="$3"

#cleanup old images, temporary volumes, snapshots
cleanup "glance image-list" "glance image-delete" ""
cleanup "cinder snapshot-list" "cinder snapshot-delete" "available"
cleanup "cinder list" "cinder delete" "available"


#create new consistent backup
i="$begin"
while [ "$i" -le "$end" ]; do
  #create a temporary image, wait for it to become available
  instance_id=$(nova list | grep -m 1 "$instance_prefix$i")
  instance_id=$(echo "$instance_id" | cut -d '|' -f 2 | sed -r 's/ //g')
  random=$(uuidgen)
  nova image-create $instance_id "from_script_temporary_for_backup_$random"
  sleep 5

  #get the temporary snapshot
  snap_id=$(cinder snapshot-list | grep -m 1 "from_script_temporary_for_backup_$random")
  snap_id=$(echo "$snap_id" | cut -d '|' -f 2 | sed -r s/' '//g)
  snap_status=$(cinder snapshot-list | grep "from_script_temporary_for_backup_$random" | cut -d '|' -f 4 | sed -e 's/ //g')
  while [ "$snap_status" != "available" ]; do
   snap_status=$(cinder snapshot-list | grep "from_script_temporary_for_backup_$random" | cut -d '|' -f 4 | sed -e 's/ //g')
   sleep 2
  done

  #create a temporary cinder volume, wait for it to become available
  vol_id=$(cinder create --snapshot-id "$snap_id" --name "from_script_temporary_for_backup_$random" 10)
  vol_id=$(echo "$vol_id" | grep " id " | cut -d '|' -f 3 | sed -e 's/ //g')
  vol_status=$(cinder list | grep "from_script_temporary_for_backup_$random" | cut -d '|' -f 3 | sed -e 's/ //g')
  error_flag=0
  while [ "$vol_status" != "available" ]; do
    vol_status=$(cinder list | grep "from_script_temporary_for_backup_$random" | cut -d '|' -f 3 | sed -e 's/ //g')
    if [ "$vol_status" = "error" ]; then
      error_flag=1
      break 
    fi
    sleep 2
  done

  #create a backup
  if [ "$error_flag" -eq 0 ]; then
    cinder --debug backup-create --name "backup_script_for_instance name: vdi-ubuntu$i, instance-id: $instance_id" "$vol_id"
  else 
    echo "!!!!!ERROR: There is no volume to be backed up for $instance_prefix$i!!!!"
    echo "!!!!!ERROR: The volume is not in \"available\" status so that it can be backed up. Check logs.!!!!!"
  fi
  let "i++"
done

echo "Finished kicking-off back up from $instance_prefix$begin to $instance_prefix$end" 
echo "$(date)"
exit 0

