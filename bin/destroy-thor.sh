#!/bin/bash


SCRIPT_DIR=$(dirname $0)
ROOT_DIR=${SCRIPT_DIR}/..
THOR_DIR=${ROOT_DIR}/thor

#-------------------------------------
# For each created tor
#
kubectl get pods | grep thor-rc  | cut -d' '  -f 1 | \
while read thor_pod
do
   volume_id=$(kubectl get pod $thor_pod -o json | grep -i volumeID | \
               cut -d':' -f2 | sed 's/.*\"\(.*\)\".*/\1/')
   thor_rc=$(echo $thor_pod | sed 's/\(thor-rc[^-]*\)-.*/\1/' )
   echo "kubectl delete -f ${THOR_DIR}/${thor_rc}.yaml"
   kubectl delete -f ${THOR_DIR}/${thor_rc}.yaml

   while [ 1 ]  
   do
      kubectl get pods | grep $thor_rc 
      [ $? -ne 0 ] && break
      sleep 3
   done
   rm -rf ${THOR_DIR}/${thor_rc}.yaml

   sleep 20
   echo "aws ec2 delete-volume --volume-id $volume_id" 
   aws ec2 delete-volume --volume-id $volume_id
   echo ""
done
