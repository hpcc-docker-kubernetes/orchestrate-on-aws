#!/bin/bash


SCRIPT_DIR=$(dirname $0)
ROOT_DIR=${SCRIPT_DIR}/..

if [ -z "$1" ]
then
   echo "Usage  $(basename $0)  <type>"
   echo "  type is either thor or roxie"
   echo ""
   exit 1
fi
type=$1
CONF_DIR=${ROOT_DIR}/$type

#-------------------------------------
# For each created thor/roxie
#
kubectl get pods | grep ${type}-rc  | cut -d' '  -f 1 | \
while read pod_name
do
   volume_id=$(kubectl get pod $pod_name -o json | grep -i volumeID | \
               cut -d':' -f2 | sed 's/.*\"\(.*\)\".*/\1/')
   type_rc=$(echo $pod_name | sed "s/\(${type}-rc[^-]*\)-.*/\1/" )
   echo "kubectl delete -f ${CONF_DIR}/${type_rc}.yaml"
   kubectl delete -f ${CONF_DIR}/${type_rc}.yaml

   while [ 1 ]  
   do
      kubectl get pods | grep $type_rc 
      [ $? -ne 0 ] && break
      sleep 3
   done
   #rm -rf ${CONF_DIR}/${type_rc}.yaml

   sleep 20
   echo "aws ec2 delete-volume --volume-id $volume_id" 
   aws ec2 delete-volume --volume-id $volume_id
   echo ""
done
