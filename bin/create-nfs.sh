#!/bin/bash

SCRIPT_DIR=$(dirname $0)
ROOT_DIR=${SCRIPT_DIR}/..
CONF_DIR=${ROOT_DIR}/conf

flag=$1

nfs_pod=$(kubectl get pods | grep nfs-server) 
if [ -n "$nfs_service_ip" ]
then
  echo "nfs-server pod already exists"
  exit
fi

function get_aws_region_and_zone()
{
   AWS_REGION=$(aws configure list | grep region | \
         sed -n 's/^  *//gp' | sed -n 's/  */ /gp' | cut -d' ' -f2)
   AWS_ZONE=${AWS_REGION}b
   aws ec2 describe-availability-zones --region $AWS_REGION | grep -q $KUBE_AWS_ZONE
   if [ $? -ne 0 ]; then
      echo "We assume availability-zone is {KUBE_AWS_ZONE} but it doesn't exist"
      echo "Check with \" aws ec2 describe-availability-zones --region $AWS_REGION\"" 
      exit 1
   fi
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
        --size ${ROXIE_VOLUME_SIZE} --volume-type gp2 | grep "VolumeId" | \
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

function create_rc_yaml()
{
  cat << EOF >    ${CONF_DIR}/nfs-server-rc.yaml
apiVersion: v1
kind: ReplicationController
metadata:
  name: nfs-server
spec:
  replicas: 1
  selector:
    role: nfs-server
  template:
    metadata:
      labels:
        role: nfs-server
    spec:
      containers:
      - name: nfs-server
        image: hpccsystems/nfs-server:latest
        command:
          - /usr/local/bin/run_nfs.sh
        args:
          - /hpcc-config
EOF
  if [ ${NUM_ROXIE_SHARED_VOLUME} -gt 0 ]
  then
    for i in $(seq 1 ${NUM_ROXIE_SHARED_VOLUME})
    do
      cat << EOF >>    ${CONF_DIR}/nfs-server-rc.yaml
          - /roxie-data-${i}
EOF
    done
  fi

  cat << EOF >>    ${CONF_DIR}/nfs-server-rc.yaml
        ports:
          - name: nfs
            containerPort: 2049
          - name: mountd
            containerPort: 20048
          - name: rpcbind
            containerPort: 111
        securityContext:
          privileged: true
        volumeMounts:
          - mountPath: /hpcc-config
            name: hpcc-config

EOF
  if [ ${NUM_ROXIE_SHARED_VOLUME} -gt 0 ]
  then
    for i in $(seq 1 ${NUM_ROXIE_SHARED_VOLUME})
    do
      cat << EOF >>    ${CONF_DIR}/nfs-server-rc.yaml
          - mountPath: /roxie-data-${i}
            name: roxie-data-${i}
EOF
    done
  fi
  cat << EOF >>    ${CONF_DIR}/nfs-server-rc.yaml
      volumes:
        - name: hpcc-config
          awsElasticBlockStore:
            volumeID: ${VOLUME_CONF}
            fsType: ext4
EOF
  if [ ${NUM_ROXIE_SHARED_VOLUME} -gt 0 ]
  then
    for i in $(seq 1 ${NUM_ROXIE_SHARED_VOLUME})
    do
      cat << EOF >>    ${CONF_DIR}/nfs-server-rc.yaml
        - name: roxie-data-${i}
          awsElasticBlockStore:
            volumeID: ${VOLUME_ROXIE[$i]}
            fsType: ext4
EOF
    done
  fi
}


[ ! -d $CONF_DIR ] && mkdir -p $CONF_DIR 
#rm -rf ${CONF_DIR}/* 

#get_aws_region_and_zone
source ${ROOT_DIR}/env

#------------------------------------------------
# Create EBS volumes for NFS server
#
[ -z "${NUM_ROXIE_SHARED_VOLUME}" ] && NUM_ROXIE_SHARED_VOLUME=0
VOLUME_ROXIE=()
create_volumes
echo "Volume for configuration: $VOLUME_CONF"
if [ ${NUM_ROXIE_SHARED_VOLUME} -gt 0 ]
then
  echo "${NUM_ROXIE_SHARED_VOLUME} shared roxie volume(s) requested:"
  for i in $(seq 1 ${NUM_ROXIE_SHARED_VOLUME})
  do
    echo ${VOLUME_ROXIE[$i]}
  done
fi


create_rc_yaml


sleep 20
#------------------------------------------------
# Create NFS server and its service 
#
create_one ${CONF_DIR}/nfs-server-rc.yaml
create_one ${ROOT_DIR}/nfs-server-service.yaml

#------------------------------------------------
# Create /hpcc-config/default, /hpcc-config/roxie and 
# /hpcc-config-esp on NFS server
#
#should test instead wait
while [ 1 ]
do
   kubectl get pods | grep nfs-server | grep Running
   [ $? -eq 0 ] && break
   sleep 3
done

sleep 3
nfs_pod=$(kubectl get pod | grep nfs-server | cut -d' ' -f1)
#echo "kubectl exec $nfs_pod -- mkdir -p /hpcc-config/default"
#kubectl exec ${nfs_pod} -- mkdir -p /hpcc-config/default
if [ ${NUM_ROXIE_SHARED_VOLUME} -gt 0 ]
then
  for i in $(seq 1 ${NUM_ROXIE_SHARED_VOLUME})
  do
    echo "kubectl exec $nfs_pod -- mkdir -p /hpcc-config/roxie/$i"
    kubectl exec ${nfs_pod} -- mkdir -p /hpcc-config/roxie/$i 
  done
fi
echo "kubectl exec $nfs_pod -- mkdir -p /hpcc-config/esp"
kubectl exec ${nfs_pod} -- mkdir -p /hpcc-config/esp
echo ""
