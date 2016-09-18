#!/bin/bash

SCRIPT_DIR=$(dirname $0)
ROOT_DIR=${SCRIPT_DIR}/..
CONF_DIR=${ROOT_DIR}/conf
PV_DIR=${ROOT_DIR}/pv
ROXIE_DIR=${ROOT_DIR}/roxie

usage()
{
   echo "Usage: $(basename $0) <options>"
   echo "  -i  interactive mode"
   echo ""
   exit 1
}


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

   if [ ${NUM_ROXIE_SHARED_VOLUME} -gt 0 ]
   then
     for i in $(seq 1 ${NUM_ROXIE_SHARED_VOLUME})
     do
       sed  "s/<NFS_SERVICE_IP>/${nfs_service_ip}/g; \
             s/<INDEX>/${i}/g"  \
            ${ROOT_DIR}/config-roxie-pv-template.yaml > ${PV_DIR}/config-roxie-${i}-pv.yaml
        create_one ${PV_DIR}/config-roxie-${i}-pv.yaml

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

   if [ ${NUM_ROXIE_SHARED_VOLUME} -gt 0 ]
   then
     for i in $(seq 1 ${NUM_ROXIE_SHARED_VOLUME})
     do
        sed "s/<INDEX>/${i}/g"  \
            ${ROOT_DIR}/config-roxie-pvc-template.yaml > ${PV_DIR}/config-roxie-${i}-pvc.yaml
        create_one ${PV_DIR}/config-roxie-${i}-pvc.yaml

        sed  "s/<INDEX>/${i}/g; s/<ROXIE_VOLUME_SIZE>/${ROXIE_VOLUME_SIZE}/g; " \
           ${ROOT_DIR}/roxie-data-pvc-template.yaml > ${PV_DIR}/roxie-data-${i}-pvc.yaml
        create_one ${PV_DIR}/roxie-data-${i}-pvc.yaml
     done
   fi
}

function press_key_to_continue()
{
  echo "Press any key to continue."
  read input
}

interactive=0
[ -n "$1" ] && [ "$1" = "-i" ] && interactive=1


[ ! -d $CONF_DIR ] && mkdir -p $CONF_DIR 
[ ! -d $PV_DIR ] && mkdir -p $PV_DIR 
[ ! -d $ROXIE_DIR ] && mkdir -p $ROXIE_DIR 

#get_aws_region_and_zone
source ${SCRIPT_DIR}/../env


#------------------------------------------------
# Create NFS server and its service 
#
if [ $interactive -eq 1 ]
then
   echo ""
   echo "Create shared volumes and NFS server/service"
   echo "============================================"
fi
${SCRIPT_DIR}/create-nfs.sh
if [ $interactive -eq 1 ]
then
   echo ""
   echo "kubectl get pod | grep nfs-server"
   kubectl get pod | grep nfs-server
   echo ""
   echo "kubectl get service | grep nfs"
   kubectl get service | grep nfs

   cat << EOF

Export directories:
   /hpcc-config 
   /roxie-data-1
     
EOF
  press_key_to_continue
fi

#------------------------------------------------
# Create Persistent Volumes (PV) 
#
if [ $interactive -eq 1 ]
then
   echo ""
   echo "Create Persistent Volumes (PV)"
   echo "=============================="
fi
create_pv
if [ $interactive -eq 1 ]
then
  echo ""
  echo "kubectl get pv"
  kubectl get pv
  press_key_to_continue
fi

#------------------------------------------------
# Create Persistent Volume Claims (PVC)
#
if [ $interactive -eq 1 ]
then
   echo ""
   echo "Create Persistent Volume Claims (PVC)"
   echo "===================================="
fi
create_pvc
if [ $interactive -eq 1 ]
then
  echo ""
  echo "kubectl get pvc"
  kubectl get pvc
  press_key_to_continue
fi

#------------------------------------------------
# Create Roxie pods and load balancer service
#
if [ $interactive -eq 1 ]
then
   echo ""
   echo "Create Roxie and proxy service"
   echo "=============================="
fi
if [ ${NUM_ROXIE_SHARED_VOLUME} -gt 0 ]
then
  for i in $(seq 1 ${NUM_ROXIE_SHARED_VOLUME})
  do
    sed  "s/<INDEX>/${i}/g; \
          s/<NUM_ROXIE_PER_SET>/${NUM_ROXIE_PER_SET}/g;" \
           ${ROOT_DIR}/roxie-share-rc-template.yaml > ${ROXIE_DIR}/roxie-rc${i}.yaml
    sed  "s/<INDEX>/${i}/g;" \
           ${ROOT_DIR}/roxie-service-template.yaml > ${ROXIE_DIR}/roxie-service${i}.yaml
    create_one ${ROXIE_DIR}/roxie-rc${i}.yaml
    create_one ${ROXIE_DIR}/roxie-service${i}.yaml
  done
else
  ${SCRIPT_DIR}/create-rc-w-esb.sh roxie $NUM_ROIXIE 
fi
if [ $interactive -eq 1 ]
then
  echo ""
  echo "kubectl get pods | grep roxie"
  kubectl get pods | grep roxie
  if [ ${NUM_ROXIE_SHARED_VOLUME} -gt 0 ]
  then
     echo ""
     echo "kubectl get service | grep roxie"
     kubectl get service | grep roxie
  fi
  press_key_to_continue
fi

#------------------------------------------------
# Create Esp pods and load balancer service
#
if [ $interactive -eq 1 ]
then
   echo ""
   echo "Create Esp and Load Balancer"
   echo "============================"
fi
create_one ${ROOT_DIR}/esp-rc.yaml
create_one ${ROOT_DIR}/esp-service.yaml
if [ $interactive -eq 1 ]
then
  echo ""
  echo "kubectl get pods | grep esp"
  kubectl get pods | grep esp
  echo ""
  echo "kubectl get service | grep esp"
  kubectl get service | grep esp
  press_key_to_continue
fi

#------------------------------------------------
# Create Thor Volumes and pods 
if [ $interactive -eq 1 ]
then
   echo ""
   echo "Create Thor"
   echo "==========="
fi
${SCRIPT_DIR}/create-rc-w-esb.sh  thor $NUM_THOR 
if [ $interactive -eq 1 ]
then
  echo ""
  echo "kubectl get pods | grep thor"
  kubectl get pods | grep thor
  press_key_to_continue
fi

#------------------------------------------------
# Create Dali (HPCC support) pod 
if [ $interactive -eq 1 ]
then
   echo ""
   echo "Create Dali/Support"
   echo "==================="
fi
create_one ${ROOT_DIR}/dali-rc.yaml
if [ $interactive -eq 1 ]
then
  echo ""
  echo "kubectl get pods | grep dali"
  kubectl get pods | grep dali
  press_key_to_continue
fi

#------------------------------------------------
# Create HPCC Ansible  pod 
if [ $interactive -eq 1 ]
then
   echo ""
   echo "Create Ansible Pod"
   echo "=================="
fi
sed  "s/<NUM_ROXIE_LB>/${NUM_ROXIE_SHARED_VOLUME}/g;" \
      ${ROOT_DIR}/hpcc-ansible-template.yaml > ${CONF_DIR}/hpcc-ansible.yaml
create_one ${CONF_DIR}/hpcc-ansible.yaml
if [ $interactive -eq 1 ]
then
  echo ""
  echo "kubectl get pods"
  kubectl get pods
  echo ""
fi
