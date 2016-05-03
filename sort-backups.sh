#!/bin/bash
#set -x

# -------------------------------------------------------------------------------------------------------
# sort-backups.sh
# Author: Akshai Parthasarathy
# Company: NetApp
# Email: akshai@netapp.com
#
# Sorts backups by timestamp given the tag, provided that the tag IS PRESENT in the description field of 
# the backups. This will be the case when using create-backups.sh with a scheduled job (cron). In this 
# case, tag to use will be the instance name. If you would like, you can modify the table headers you 
# want to see in the list of sorted backups. 
#
# Tested in RDO with NetApp.
# -------------------------------------------------------------------------------------------------------


if [ "$#" -ne 1 ]; then
  echo 'ERROR. usage: ./sort-backups.sh <tag>'
  echo "The tag will be your instance name if you're using create-backups.sh"
  exit 1
fi

instance_name=$1
bk_list=$(cinder backup-list | grep "$instance_name" | cut -d '|' -f2)
bk_list=$(echo "$bk_list" | sed -e "s/ //g")

# ---------------------------------------------
# Modify the table headers needed for backups.
table_headers="id,name,created_at,status,size"
# ---------------------------------------------

bk_list=$(echo "$bk_list" | sed -e ':a;N;$!ba;s/\n/,/g')
IFS=','
echo -n 'Please wait, sorting backups...'
for bk_id in $bk_list; do
  tmp=$(cinder backup-show "$bk_id")
  IFS=','
  for t in $table_headers; do
    tmp2=$(echo "$tmp" | grep " $t " | cut -d '|' -f3)
    output+="$tmp2"
    output+=' | '
  done
  output+="\n"  
  echo -n "."
done
unset IFS

#setup the header for formatting. Header will customize automatically if table headers are changed.
bars=${output%%\\n*}
echo -e "\n"
bars=$(echo "$bars" | sed -e "s/[a-zA-Z0-9:,/._\-\\]/\-/g")
bars=$(echo "$bars" | sed -e "s/ /\-/g" | sed -e "s/|/+/g")
header=${bars}
header=$(echo ${header} | sed -e "s/+/,/g")
IFS=,
output_hd=''
set -- $(echo "$header")
for t in $table_headers; do
  t=$(echo "$t" | tr '[:lower:]' '[:upper:]')
  len_text=${#t}
  len_output_hd=${#1}
  let start="($len_output_hd/2)-($len_text/2)"
  tmp=$(echo "$1" | sed "s/./$t/$start")
  tmp=${tmp:0:$len_output_hd}
  output_hd="$output_hd"'|'"$tmp"
  shift
done
output_hd=${output_hd:1}
output_hd="$output_hd"'|'
output_hd=$(echo $output_hd | sed -e "s/\-/ /g")
output_hd=$(echo $output_hd | sed -e "s/,/|/g")
unset IFS

#output header
echo -e "$bars\n$output_hd\n$bars"
#output sorted list of backups
echo -e "$output" | sort -k3 


