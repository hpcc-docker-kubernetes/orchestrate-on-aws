# Demo of Docker/Kubernetes on AWS

## Preparation

To deploy HPCC cluster on Kubernetes/AWS we need AWS Client and Kubernetes package

### Install and Configure AWS Client
Install AWS Clinet as 
http://docs.aws.amazon.com/cli/latest/userguide/installing.html#install-bundle-other-os

Configure AWS client with Access Key Secrete Access Key and default region: 
```sh
aws configure

AWS Access Key ID [****************]: 
AWS Secret Access Key [****************4ifT]: 
Default region name [ap-southeast-1]: 
Default output format [None]: 
```
To test it run:
```sh
aws ec2 describe-regions
```
### Get HPCC Docker/Kubernetes Orchestrate On AWS package
git clone https://github.com/hpcc-docker-kubernetes/orchestrate-on-aws 

Review and update  orchestrate-on-aws/env. For example PATH.
Also you may want to change NODE_SIZE, NUM_NODES and XXX_VOLUME_SIZE, etc
```sh
export KUBERNETES_PROVIDER=aws
AWS_REGION=$(aws configure list | grep region | \
         sed -n 's/^  *//gp' | sed -n 's/  */ /gp' | cut -d' ' -f2)
export KUBE_AWS_ZONE=${AWS_REGION}b
export AWS_S3_REGION=${KUBE_AWS_ZONE}
export PATH=~/work/Google/Kubernetes/v1.3.6/platforms/linux/amd64:$PATH
# Uncomment following if you want to setup a namespace instead of using default one: "default"
#export CONTEXT=$(kubectl config view | grep current-context | awk '{print $2}')
#kubectl config set-context $CONTEXT --namespace=<your namespace name, for example,hpcc-kube> > /dev/null 2>&1

export MASTER_SIZE=
# For HPCC regression test probably need set following to m4.xlarge (4cpu 16GB mem) or even m4.2xlarge (8cpu 32GB mem)
# check limits in ec2 some setting for example m4.xlarge may not be available
export NODE_SIZE=m4.xlarge
export NUM_NODES=5

# Each shared volume group will be assigned a load balancer.
# If zero each roxie instance will have a dedicated volume and no load balancer will be created
export NUM_ROXIE_SHARED_VOLUME=1
export NUM_ROXIE_PER_SET=2 #Num of set equals NUM_ROXIE_SHARED_VOLUME. Each set has a shared volume
export ROXIE_VOLUME_SIZE=60
export THOR_VOLUME_SIZE=60
export NUM_THOR=2
export NUM_ROXIE=2 # NUM_ROXIE_SHARED_VOLUME=0. Each roxie has its own volume attached
```

### Install  Kubernetes 
Reference http://kubernetes.io/docs/getting-started-guides/aws/

First source above env file since following script will try to setup Kubernete after download

```sh
export KUBERNETES_PROVIDER=aws; wget -q -O - https://get.k8s.io | bash
```
Installed Kubernetes should be in Kubernetes in current directory.
kube-up.sh may fails for Kubernetes v1.3.6
To workaround it add followings in cluster/common.sh

```sh
# Add three line after line "local salt_tar_url=$SALT_TAR_URL" (around line 526)
local salt_tar_url=$SALT_TAR_URL
KUBE_MANIFESTS_TAR_URL="${SERVER_BINARY_TAR_URL/server-linux-amd64/manifests}"
MASTER_OS_DISTRIBUTION="${KUBE_MASTER_OS_DISTRIBUTION}"
NODE_OS_DISTRIBUTION="${KUBE_NODE_OS_DISTRIBUTION}"

```
More detail about this workaround reference https://github.com/kubernetes/kubernetes/issues/30495

Another error is from s3 bucket for regions eu-west-1 and ap-northeast-2 (soal):
error (InvalidRequest) occurred when calling the CreateBucket operation: Missing required header for this request: x-amz-content-sha256

The workaround is to add "signature_version = s3v4 in ~/.aws/config file



# Additional settings can be found in Kubernetes/cluster/aws/config-default.sh
```

### Start Kubernetes on AWS
Make sure you source the env file created above and go to Kubernetes/cluster and run
```sh
./kube-up.sh
```
It may ask you to install addional packages.

When it finish you should see the master and nodes (minion) in AWS Console

## Quick Start


### Create a  Cluster
Go to demo-on-aws/bin directory and run
```sh
./create-all.sh
```
Verify all pod ready:
```sh
kubectl get pods
```

### Configure the Cluster
Login to hpcc-ansible node:
```sh
kubectl exec -i -t hpcc-ansible -- bash -il

export TERM=xterm
stty rows 50 cols 120
```
Go to /opt/hpcc-tools and run
```sh
./config_hpcc.sh
```
This should collect ips and generate environment.xml and start HPCC cluster with Ansible playbook

Even "host_key_checking=false" is set in /etc/ansible/ansible.cfg but it seems not work.
use "export ANSIBLE_HOST_KEY_CHECKING=False" instead.


### Access ECLWatch
Get esp load balancer ip
```sh
kubectl get service esp

NAME      CLUSTER-IP     EXTERNAL-IP        PORT(S)    AGE
esp       10.0.150.205   ae45d4af45995...   8010/TCP   25m


kubectl get service esp -o json | grep ae45d4af45995
                    "hostname": "ae45d4af4599511e698bd02c3e1be8c5-90448396.ap-southeast-1.elb.amazonaws.com"

host ae45d4af4599511e698bd02c3e1be8c5-90448396.ap-southeast-1.elb.amazonaws.com

ae45d4af4599511e698bd02c3e1be8c5-90448396.ap-southeast-1.elb.amazonaws.com has address 52.220.16.128
ae45d4af4599511e698bd02c3e1be8c5-90448396.ap-southeast-1.elb.amazonaws.com has address 54.179.135.114
```
You should use either ip with port 8010 to access ECLWatch


### Destroy the Cluster
```sh
./destroy-all.sh
```
