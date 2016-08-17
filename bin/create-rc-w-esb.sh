#!/bin/bash

SCRIPT_DIR=$(dirname $0)
ROOT_DIR=${SCRIPT_DIR}/..

usage()
{
   echo "Usage: $(basename $0) <type>  <number of thor or roxie to create>"
   echo "  type is either thor or roxie"
   echo ""
   exit 1
}

function get_aws_zone()
{
   AWS_REGION=$(aws configure list | grep region | \
         sed -n 's/^  *//gp' | sed -n 's/  */ /gp' | cut -d' ' -f2)
   KUBE_AWS_ZONE=${AWS_REGION}b
}


[ -z "$1" ] || [ -z "$2" ] && usage
type=$1
CONF_DIR=${ROOT_DIR}/$type

# check it is integer
num=$2
echo $num | grep -q "^[[:digit:]][[:digit:]]*$"
if [ $? -ne 0 ]; then
   echo "<number of thor to create> must be an integer"
   usage
fi
if [ "$type" = "thor" ]
then
   VOLUME_SIZE=$THOR_VOLUME_SIZE
elif [ "$type" = "roxie" ]
then
   VOLUME_SIZE=$ROXIE_VOLUME_SIZE
else
   echo "type must be either thor or roxie"
   usage
fi

#-------------------------------------
# Get current deployed thor/roxie index
#
max_index=$(kubectl get pods | grep ${type}-rc | cut -d' ' -f 1 | sort -r | head -n 1 | \
  cut -d'-' -f2 | cut -d'c' -f2)

cur_index=$(echo "$max_index" | sed -n 's/^00*//gp')
[ -z "$cur_index" ] && cur_index=0


#-------------------------------------
# Loop number thor/roxie to create 
#
#get_aws_zone
source ${ROOT_DIR}/env
mkdir -p $CONF_DIR
i=0
while [ $i -lt $num ]
do
   i=$(expr $i \+ 1)
   cur_index=$(expr $cur_index \+ 1)
   padded_index=$(printf "%04d" $cur_index)
   #echo $padded_index

   # Create ESB volume
   VOLUME_ID=$(aws ec2 create-volume --availability-zone ${KUBE_AWS_ZONE} \
     --size $VOLUME_SIZE --volume-type gp2 | grep "VolumeId" | \
     cut -d':' -f2 | sed 's/.*\"\(.*\)\".*/\1/')
   echo "Volume id: $VOLUME_ID"

   sed  "s/<VOLUME_ID>/${VOLUME_ID}/g; s/<INDEX>/${padded_index}/g; " \
     ${ROOT_DIR}/${type}-rc-template.yaml > ${CONF_DIR}/${type}-rc${padded_index}.yaml

   # Create rc
   echo "kubectl create -f ${CONF_DIR}/${type}-rc${padded_index}.yaml"
   kubectl create -f ${CONF_DIR}/${type}-rc${padded_index}.yaml
   echo ""
done
