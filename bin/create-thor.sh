#!/bin/bash

SCRIPT_DIR=$(dirname $0)
ROOT_DIR=${SCRIPT_DIR}/..
THOR_DIR=${ROOT_DIR}/thor

usage()
{
   echo "Usage: $(basename $0) <number of thor to create>"
   echo ""
   exit 1
}

function get_aws_zone()
{
   AWS_REGION=$(aws configure list | grep region | \
         sed -n 's/^  *//gp' | sed -n 's/  */ /gp' | cut -d' ' -f2)
   AWS_ZONE=${AWS_REGION}b
}


[ -z "$1" ] && usage

# check it is integer
num=$1
echo $num | grep -q "^[[:digit:]][[:digit:]]*$"
if [ $? -ne 0 ]; then
   echo "<number of thor to create> must be an integer"
   usage
fi

#-------------------------------------
# Get current deployed thor index
#
max_index=$(kubectl get pods | grep thor-rc | cut -d' ' -f 1 | sort -r | head -n 1 | \
  cut -d'-' -f2 | cut -d'c' -f2)

cur_index=$(echo "$max_index" | sed -n 's/^00*//gp')
[ -z "$cur_index" ] && cur_index=0


#-------------------------------------
# Loop number thor to create 
#
get_aws_zone
mkdir -p $THOR_DIR
i=0
while [ $i -lt $num ]
do
   i=$(expr $i \+ 1)
   cur_index=$(expr $cur_index \+ 1)
   padded_index=$(printf "%04d" $cur_index)
   #echo $padded_index

   # Create ESB volume
   VOLUME_THOR=$(aws ec2 create-volume --availability-zone ${AWS_ZONE} \
     --size 10 --volume-type gp2 | grep "VolumeId" | \
     cut -d':' -f2 | sed 's/.*\"\(.*\)\".*/\1/')
   echo "thor volume: $VOLUME_THOR"

   sed  "s/<VOLUME_ID>/${VOLUME_THOR}/g; s/<INDEX>/${padded_index}/g; " \
     ${ROOT_DIR}/thor-rc-template.yaml > ${THOR_DIR}/thor-rc${padded_index}.yaml

   # Create thor rc
   echo "kubectl create -f ${THOR_DIR}/thor-rc${padded_index}.yaml"
   kubectl create -f ${THOR_DIR}/thor-rc${padded_index}.yaml
   echo ""
done
