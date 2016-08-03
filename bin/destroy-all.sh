#!/bin/bash

SCRIPT_DIR=$(dirname $0)
ROOT_DIR=${SCRIPT_DIR}/..
CONFIG_DIR=${ROOT_DIR}/conf


function delete_one()
{
   [ -z "$1" ] && [ -z "$2" ] || [ -z "$3" ] && return
   type=$1
   name=$2
   config_file=$3
   kubectl get $type | grep -q -i "^${name}" 
   if [ $? -eq 0 ]; then
      echo "kubectl delete -f ${config_file}"
      kubectl delete -f ${config_file}
      echo ""
   fi
}

#------------------------------------------------
# Destroy Esp pods and load balancer service
#
delete_one service esp ${ROOT_DIR}/esp-service.yaml
delete_one pod esp-rc ${ROOT_DIR}/esp-rc.yaml


#------------------------------------------------
# Destroy Roxie pods and load balancer service
#
delete_one service roxie ${ROOT_DIR}/roxie-service.yaml
delete_one pod roxie-rc ${ROOT_DIR}/roxie-rc.yaml

#------------------------------------------------
# Destroy Thor pods and volumes
#
${SCRIPT_DIR}/destroy-thor.sh

#------------------------------------------------
# Destroy Dali pod
#
delete_one pod dali-rc ${ROOT_DIR}/dali-rc.yaml

#------------------------------------------------
# Destroy HPCC Ansible pod
#
delete_one pod hpcc-ansible ${ROOT_DIR}/hpcc-ansible.yaml

#------------------------------------------------
# Destroy Persistent Volume Claims (PVC)
#
kubectl get pvc | cut -d' ' -f1 | grep -v "^NAME$" | \
while read pvc_name
do
   delete_one pvc ${pvc_name} ${ROOT_DIR}/${pvc_name}-pvc.yaml
done

#------------------------------------------------
# Destroy  Persisent Volumes (PV) 
#
kubectl get pv | cut -d' ' -f1 | grep -v "^NAME$" | \
while read pv_name
do
   delete_one pv ${pv_name} ${CONFIG_DIR}/${pv_name}-pv.yaml
done

#------------------------------------------------
# Destroy NFS server service  
#
delete_one service nfs-server ${ROOT_DIR}/nfs-server-service.yaml

#------------------------------------------------
# Destroy NFS server and volumes   
#
nfs_rc=$(kubectl get pods | grep nfs-server  | cut -d' '  -f 1)
if [ -n "$nfs_rc" ]; then
   volume_ids=$(kubectl get pod $nfs_rc -o json | grep -i volumeID | \
               cut -d':' -f2 | sed 's/.*\"\(.*\)\".*/\1/')
   delete_one pod nfs-server ${CONFIG_DIR}/nfs-server-rc.yaml
   while [ 1 ]
   do
      kubectl get pods | grep -q ${nfs_rc}
      [ $? -ne 0 ] && break
      sleep 3
   done

   sleep 20
   for vid in $volume_ids 
   do
      echo "aws ec2 delete-volume --volume-id $vid"
      aws ec2 delete-volume --volume-id $vid
      echo ""
   done
fi
#------------------------------------------------
# Check   
#
kubectl get pods
kubectl get services
kubectl get pv
kubectl get pvc
