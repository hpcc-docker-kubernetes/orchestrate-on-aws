#!/bin/bash

SCRIPT_DIR=$(dirname $0)
ROOT_DIR=${SCRIPT_DIR}/..
CONF_DIR=${ROOT_DIR}/conf
PV_DIR=${ROOT_DIR}/pv
ROXIE_DIR=${ROOT_DIR}/roxie

function get_aws_region_and_zone()
{
   AWS_REGION=$(aws configure list | grep region | \
         sed -n 's/^  *//gp' | sed -n 's/  */ /gp' | cut -d' ' -f2)
   KUBE_AWS_ZONE=${AWS_REGION}b
   aws ec2 describe-availability-zones --region $AWS_REGION | grep -q $KUBE_AWS_ZONE
   if [ $? -ne 0 ]; then
      echo "We assume availability-zone is {KUBE_AWS_ZONE} but it doesn't exist"
      echo "Check with \" aws ec2 describe-availability-zones --region $AWS_REGION\"" 
      exit 1
   fi
   echo "AWS Region: ${AWS_REGION}, ZONE: $KUBE_AWS_ZONE "
   echo ""
}

function create_volumes()
{
  VOLUME_CONF=$(aws ec2 create-volume --availability-zone ${KUBE_AWS_ZONE} \
     --size 1 --volume-type gp2 | grep "VolumeId" | \
     cut -d':' -f2 | sed 's/.*\"\(.*\)\".*/\1/')


  [ ${NUM_ROXIE_SHARED_VOLUME} -lt 1 ] && return
  for i in $(seq 1 ${NUM_ROXIE_SHARED_VOLUME})
  do
     VOLUME_ROXIE[$i]=$(aws ec2 create-volume --availability-zone ${KUBE_AWS_ZONE} \
        --size 10 --volume-type gp2 | grep "VolumeId" | \
        cut -d':' -f2 | sed 's/.*\"\(.*\)\".*/\1/')
  done
}

function create_one()
{
   [ -z $1 ] && return
   config_file=$1

   echo "kubectl create -f ${config_file}"
   kubectl create -f ${config_file}
   echo ""
}

function create_pv()
{
   nfs_service_ip=$(kubectl get service | grep nfs-server | \
      sed -n 's/  */ /gp' | cut -d' ' -f2)

   sed  "s/<NFS_SERVICE_IP>/${nfs_service_ip}/g" \
      ${ROOT_DIR}/config-default-pv-template.yaml > ${PV_DIR}/config-default-pv.yaml
   create_one ${PV_DIR}/config-default-pv.yaml

   sed  "s/<NFS_SERVICE_IP>/${nfs_service_ip}/g" \
      ${ROOT_DIR}/config-esp-pv-template.yaml > ${PV_DIR}/config-esp-pv.yaml
   create_one ${PV_DIR}/config-esp-pv.yaml

   sed  "s/<NFS_SERVICE_IP>/${nfs_service_ip}/g" \
      ${ROOT_DIR}/config-roxie-pv-template.yaml > ${PV_DIR}/config-roxie-pv.yaml
   create_one ${PV_DIR}/config-roxie-pv.yaml

   if [ ${NUM_ROXIE_SHARED_VOLUME} -gt 0 ]
   then
     for i in $(seq 1 ${NUM_ROXIE_SHARED_VOLUME})
     do
        sed  "s/<NFS_SERVICE_IP>/${nfs_service_ip}/g; \
              s/<INDEX>/${i}/g;  \
              s/<ROXIE_VOLUME_SIZE>/${ROXIE_VOLUME_SIZE}/g; " \
           ${ROOT_DIR}/roxie-data-pv-template.yaml > ${PV_DIR}/roxie-data-${i}-pv.yaml
        create_one ${PV_DIR}/roxie-data-${i}-pv.yaml
     done
   fi

}

function create_pvc()
{
   cp ${ROOT_DIR}/config-default-pvc.yaml ${PV_DIR}/
   create_one ${PV_DIR}/config-default-pvc.yaml
  
   cp ${ROOT_DIR}/config-esp-pvc.yaml ${PV_DIR}/
   create_one ${PV_DIR}/config-esp-pvc.yaml

   cp ${ROOT_DIR}/config-roxie-pvc.yaml ${PV_DIR}/
   create_one ${PV_DIR}/config-roxie-pvc.yaml

   if [ ${NUM_ROXIE_SHARED_VOLUME} -gt 0 ]
   then
     for i in $(seq 1 ${NUM_ROXIE_SHARED_VOLUME})
     do
        sed  "s/<INDEX>/${i}/g; s/<ROXIE_VOLUME_SIZE>/${ROXIE_VOLUME_SIZE}/g; " \
           ${ROOT_DIR}/roxie-data-pvc-template.yaml > ${PV_DIR}/roxie-data-${i}-pvc.yaml
        create_one ${PV_DIR}/roxie-data-${i}-pvc.yaml
     done
   fi
}


[ ! -d $CONF_DIR ] && mkdir -p $CONF_DIR 
[ ! -d $PV_DIR ] && mkdir -p $PV_DIR 
[ ! -d $ROXIE_DIR ] && mkdir -p $ROXIE_DIR 

#get_aws_region_and_zone
source ${SCRIPT_DIR}/../env


#------------------------------------------------
# Create NFS server and its service 
#
${SCRIPT_DIR}/create-nfs.sh

#------------------------------------------------
# Create Persisent Volumes (PV) 
#
create_pv

#------------------------------------------------
# Create Persisent Volume Claims (PVC)
#
create_pvc

#------------------------------------------------
# Create Roxie pods and load balancer service
#
if [ ${NUM_ROXIE_SHARED_VOLUME} -gt 0 ]
then
  for i in $(seq 1 ${NUM_ROXIE_SHARED_VOLUME})
  do
    sed  "s/<INDEX>/${i}/g;" \
           ${ROOT_DIR}/roxie-share-rc-template.yaml > ${ROXIE_DIR}/roxie-rc${i}.yaml
    sed  "s/<INDEX>/${i}/g;" \
           ${ROOT_DIR}/roxie-service-template.yaml > ${ROXIE_DIR}/roxie-service${i}.yaml
    create_one ${ROXIE_DIR}/roxie-rc${i}.yaml
    create_one ${ROXIE_DIR}/roxie-service${i}.yaml
  done
else
  ${SCRIPT_DIR}/create-rc-w-esb.sh roxie 2 
fi

#------------------------------------------------
# Create Esp pods and load balancer service
#
create_one ${ROOT_DIR}/esp-rc.yaml
create_one ${ROOT_DIR}/esp-service.yaml

#------------------------------------------------
# Create Thor Volumes and pods 
${SCRIPT_DIR}/create-rc-w-esb.sh   thor 2 

#------------------------------------------------
# Create Dali (HPCC support) pod 
create_one ${ROOT_DIR}/dali-rc.yaml

#------------------------------------------------
# Create HPCC Ansible  pod 
sed  "s/<NUM_ROXIE_LB>/${NUM_ROXIE_SHARED_VOLUME}/g;" \
      ${ROOT_DIR}/hpcc-ansible-template.yaml > ${CONF_DIR}/hpcc-ansible.yaml
create_one ${CONF_DIR}/hpcc-ansible.yaml
