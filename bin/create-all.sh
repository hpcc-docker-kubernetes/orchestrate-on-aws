#!/bin/bash

SCRIPT_DIR=$(dirname $0)
ROOT_DIR=${SCRIPT_DIR}/..
CONF_DIR=${ROOT_DIR}/conf

function get_aws_region_and_zone()
{
   AWS_REGION=$(aws configure list | grep region | \
         sed -n 's/^  *//gp' | sed -n 's/  */ /gp' | cut -d' ' -f2)
   AWS_ZONE=${AWS_REGION}b
   aws ec2 describe-availability-zones --region $AWS_REGION | grep -q $AWS_ZONE
   if [ $? -ne 0 ]; then
      echo "We assume availability-zone is {AWS_ZONE} but it doesn't exist"
      echo "Check with \" aws ec2 describe-availability-zones --region $AWS_REGION\"" 
      exit 1
   fi
   echo "AWS Region: ${AWS_REGION}, ZONE: $AWS_ZONE "
   echo ""
}

function create_volumes()
{
  VOLUME_CONF=$(aws ec2 create-volume --availability-zone ${AWS_ZONE} \
     --size 1 --volume-type gp2 | grep "VolumeId" | \
     cut -d':' -f2 | sed 's/.*\"\(.*\)\".*/\1/')

  VOLUME_ROXIE=$(aws ec2 create-volume --availability-zone ${AWS_ZONE} \
     --size 10 --volume-type gp2 | grep "VolumeId" | \
     cut -d':' -f2 | sed 's/.*\"\(.*\)\".*/\1/')
}

function create_one()
{
   [ -z $1 ] && return
   config_file=$1

   echo "kubectl create -f ${config_file}"
   kubectl create -f ${config_file}
   echo ""
}


[ ! -d $CONF_DIR ] && mkdir -p $CONF_DIR 
#rm -rf ${CONF_DIR}/* 

get_aws_region_and_zone

#------------------------------------------------
# Create EBS volumes for NFS server
#
create_volumes
echo $VOLUME_CONF
echo $VOLUME_ROXIE


#------------------------------------------------
# Create NFS server and its service 
#
sed  "s/<VOLUME_CONF>/${VOLUME_CONF}/g; s/<VOLUME_ROXIE>/${VOLUME_ROXIE}/g " \
    ${ROOT_DIR}/nfs-server-rc-template.yaml > ${CONF_DIR}/nfs-server-rc.yaml
create_one ${CONF_DIR}/nfs-server-rc.yaml
create_one ${ROOT_DIR}/nfs-server-service.yaml

#------------------------------------------------
# Create /hpcc-config/default, /hpcc-config/roxie and 
# /hpcc-config-esp on NFS server
#
sleep 15
nfs_pod=$(kubectl get pod | grep nfs-server | cut -d' ' -f1)
echo "kubectl exec $nfs_pod -- mkdir -p /hpcc-config/default"
kubectl exec ${nfs_pod} -- mkdir -p /hpcc-config/default
sleep 2
echo "kubectl exec $nfs_pod -- mkdir -p /hpcc-config/roxie"
kubectl exec ${nfs_pod} -- mkdir -p /hpcc-config/roxie 
sleep 2
echo "kubectl exec $nfs_pod -- mkdir -p /hpcc-config/esp"
kubectl exec ${nfs_pod} -- mkdir -p /hpcc-config/esp
echo ""

#------------------------------------------------
# Create Persisent Volumes (PV) 
#
nfs_service_ip=$(kubectl get service | grep nfs-server | \
    sed -n 's/  */ /gp' | cut -d' ' -f2)

sed  "s/<NFS_SERVICE_IP>/${nfs_service_ip}/g" \
    ${ROOT_DIR}/config-default-pv-template.yaml > ${CONF_DIR}/config-default-pv.yaml
create_one ${CONF_DIR}/config-default-pv.yaml

sed  "s/<NFS_SERVICE_IP>/${nfs_service_ip}/g" \
    ${ROOT_DIR}/config-esp-pv-template.yaml > ${CONF_DIR}/config-esp-pv.yaml
create_one ${CONF_DIR}/config-esp-pv.yaml

sed  "s/<NFS_SERVICE_IP>/${nfs_service_ip}/g" \
    ${ROOT_DIR}/config-roxie-pv-template.yaml > ${CONF_DIR}/config-roxie-pv.yaml
create_one ${CONF_DIR}/config-roxie-pv.yaml

sed  "s/<NFS_SERVICE_IP>/${nfs_service_ip}/g" \
    ${ROOT_DIR}/data-pv-template.yaml > ${CONF_DIR}/data-pv.yaml
create_one ${CONF_DIR}/data-pv.yaml

#------------------------------------------------
# Create Persisent Volume Claims (PVC)
#
create_one ${ROOT_DIR}/config-default-pvc.yaml
create_one ${ROOT_DIR}/config-esp-pvc.yaml
create_one ${ROOT_DIR}/config-roxie-pvc.yaml
create_one ${ROOT_DIR}/data-pvc.yaml

#------------------------------------------------
# Create Roxie pods and load balancer service
#
create_one ${ROOT_DIR}/roxie-rc.yaml
create_one ${ROOT_DIR}/roxie-service.yaml


#------------------------------------------------
# Create Esp pods and load balancer service
#
create_one ${ROOT_DIR}/esp-rc.yaml
create_one ${ROOT_DIR}/esp-service.yaml

#------------------------------------------------
# Create Thor Volumes and pods 
${SCRIPT_DIR}/create-thor.sh 2

#------------------------------------------------
# Create Dali (HPCC support) pod 
create_one ${ROOT_DIR}/dali-rc.yaml

#------------------------------------------------
# Create HPCC Ansible  pod 
create_one ${ROOT_DIR}/hpcc-ansible.yaml
