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

### Install  Kubernetes 
Reference http://kubernetes.io/docs/getting-started-guides/aws/

Download the Kubernetes to local directory:

```sh
export KUBERNETES_PROVIDER=aws; wget -q -O - https://get.k8s.io | bash
```
Installed Kubernetes should be in Kubernetes in current directory.

It is helpful to create env file with:
```sh
export KUBERNETES_PROVIDER=aws
export KUBE_AWS_ZONE=ap-southeast-1b #change this to your select zone
export PATH=<Kubernetes install directory>/platforms/darwin/amd64:$PATH
# Uncomment following if you want to setup a namespace instead of using default one: "default"
#export CONTEXT=$(kubectl config view | grep current-context | awk '{print $2}')
#kubectl config set-context $CONTEXT --namespace=<your namespace name, for example,hpcc-kube> > /dev/null 2>&1

# Change the size based on your need. Following default will set master to m3.medium and node to t2.micro
export MASTER_SIZE=
export NODE_SIZE=
export NUM_NODES=4
export AWS_S3_REGION=ap-southeast-1 #It is better to match KUBE_AWS_ZONE

# Additional settings can be found in Kubernetes/cluster/aws/config-default.sh
```

You can source this env file before run any Kubernetes command or add it to profile

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
