# Demo of Docker/Kubernetes on AWS

## Preparation

To deploy HPCC cluster on Kubernetes/AWS we need AWS Client and Kubernetes package

### Install and Configure AWS Client
Install AWS Client as 
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

This will try to start Kubernetes. If fails check the error message and fix the problems i.e. install
missing packages etc. and start kubernetes as following

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

```
Go to /opt/hpcc-tools and run
```sh
./config_hpcc.sh
```
This should collect ips and generate environment.xml and start HPCC cluster with Ansible playbook

hpcc-ansible pod will run mon_ips.sh at boot which can monitor the cluster ip changes and re-create
ansible hosts and environment.xml if necessary. By default the action is disabled. To enable it run
under /opt/hpcc-tools
```sh
./enable
```
The log will be /var/log/hpcc-tools/mon_ips.log


### Access ECLWatch
Get esp load balancer ip
```sh
kubectl get service esp -o json | grep hostname
                    "hostname": "ae45d4af4599511e698bd02c3e1be8c5-90448396.ap-southeast-1.elb.amazonaws.com"

host ae45d4af4599511e698bd02c3e1be8c5-90448396.ap-southeast-1.elb.amazonaws.com

ae45d4af4599511e698bd02c3e1be8c5-90448396.ap-southeast-1.elb.amazonaws.com has address 52.220.16.128
ae45d4af4599511e698bd02c3e1be8c5-90448396.ap-southeast-1.elb.amazonaws.com has address 54.179.135.114
```
You should use either ip with port 8010 to access ECLWatch

You can go to "Play with HPCCSystems/Kubernetes features" for some exercises

### Destroy the Cluster
```sh
./destroy-all.sh
```

### Terminate Kubernetes on AWS 
go to Kubernetes/cluster and run
```sh
./kube-down.sh
```

## Play with HPCCSystems/Kubernetes features

### Recover from roxie pod delete
Each pod will have a container defined. Delete pod will automatically destroy the containers defined in this pod.
Let's delete a roxie pod:
```sh
kubectl get pods
NAME                READY     STATUS    RESTARTS   AGE
dali-rc-cpkgl       1/1       Running   0          15m
esp-rc-4kp81        1/1       Running   0          16m
esp-rc-ymwh7        1/1       Running   0          16m
hpcc-ansible        1/1       Running   0          15m
nfs-server-o96pt    1/1       Running   0          19m
roxie-rc1-c9y8h     1/1       Running   0          16m
roxie-rc1-n8iop     1/1       Running   0          16m
thor-rc0001-xi6wq   1/1       Running   0          16m
thor-rc0002-6fzze   1/1       Running   0          15m

kubectl delete pod roxie-rc1-c9y8h
pod "roxie-rc1-c9y8h" deleted

kubectl get pods
NAME                READY     STATUS        RESTARTS   AGE
dali-rc-cpkgl       1/1       Running       0          17m
esp-rc-4kp81        1/1       Running       0          18m
esp-rc-ymwh7        1/1       Running       0          18m
hpcc-ansible        1/1       Running       0          17m
nfs-server-o96pt    1/1       Running       0          21m
roxie-rc1-c9y8h     1/1       Terminating   0          18m
roxie-rc1-n8iop     1/1       Running       0          18m
roxie-rc1-wungv     1/1       Running       0          29s
thor-rc0001-xi6wq   1/1       Running       0          17m
thor-rc0002-6fzze   1/1       Running       0          17m
```
one roxie terminating and a new one come up.


### Recover from container delete
You also can delete roxie node container instead of the roxie pod. In Docker the pod and HPCC roxoie node are
two containers. To delete roxie node container directly you need find the correct minion (AWS node)

kubectl get pod roxie-rc1-n8iop -o json | grep nodeName
        "nodeName": "ip-172-20-0-245.ap-southeast-1.compute.internal"

kubectl get node ip-172-20-0-245.ap-southeast-1.compute.internal -o json 
...
   {
                "type": "ExternalIP",
                "address": "52.221.241.182"
            }


ssh -i ~/.ssh/kube_aws_rsa  admin@52.221.241.182
admin@ip-172-20-0-245:~$ 

admin@ip-172-20-0-245:~$ sudo docker ps -a | grep roxie
ac4cd28113b4        hpccsystems/platform-ce:latest                                         "/tmp/start_hpcc.sh"     39 minutes ago      Up 39 minutes                           k8s_roxie1.f56ce32e_roxie-rc1-n8iop_default_e51fef44-8a44-11e6-a04a-020db6e132bb_e9d1e753
4a41558ae5ea        gcr.io/google_containers/pause-amd64:3.0                               "/pause"                 41 minutes ago      Up 41 minutes                           k8s_POD.d8dbe16c_roxie-rc1-n8iop_default_e51fef44-8a44-11e6-a04a-020db6e132bb_28553b7b


admin@ip-172-20-0-245:~$ sudo docker rm -f ac4cd28113b4 
ac4cd28113b4

admin@ip-172-20-0-245:~$ sudo docker ps -a | grep roxie
dcc8b68aee42        hpccsystems/platform-ce:latest                                         "/tmp/start_hpcc.sh"     1 seconds ago       Up Less than a second                       k8s_roxie1.f56ce32e_roxie-rc1-n8iop_default_e51fef44-8a44-11e6-a04a-020db6e132bb_faaeb5f6
4a41558ae5ea        gcr.io/google_containers/pause-amd64:3.0                               "/pause"                 47 minutes ago      Up 47 minutes                               k8s_POD.d8dbe16c_roxie-rc1-n8iop_default_e51fef44-8a44-11e6-a04a-020db6e132bb_28553b7b

exit

```
roxie pod will not change

### Recover from minions termination
Login to AWS console and to you the region/EC2/Instances. Find the AWS node by the public ip and delete it by click
Actions/Instance State/Terminiate.

Kubernetes will move the pods/containers to other AWS nodes. Kubernetes/AWS will restart a new node (VM)

### Auto-scaling roxie with CPU load
Make sure autoscaling service is started
```sh
kubectl get hpa   (if nothing displayed it means autoscaling is not started yet)

:~/work/HPCC-Kubernetes/orchestrate-on-aws$ kubectl create -f roxie-autoscale.yaml
horizontalpodautoscaler "roxie-rc1" created

:~/work/HPCC-Kubernetes/orchestrate-on-aws$ kubectl get hpa
NAME        REFERENCE                         TARGET    CURRENT   MINPODS   MAXPODS   AGE
roxie-rc1   ReplicationController/roxie-rc1   50%       0%        2         3         1m

:~/work/HPCC-Kubernetes/orchestrate-on-aws$ kubectl get pods
NAME                READY     STATUS    RESTARTS   AGE
dali-rc-cpkgl       1/1       Running   0          2h
esp-rc-4kp81        1/1       Running   0          2h
esp-rc-ymwh7        1/1       Running   0          2h
hpcc-ansible        1/1       Running   0          2h
nfs-server-o96pt    1/1       Running   0          2h
roxie-rc1-n8iop     1/1       Running   0          2h
roxie-rc1-wungv     1/1       Running   0          1h
thor-rc0001-xi6wq   1/1       Running   0          2h
thor-rc0002-6fzze   1/1       Running   0          2h

kubectl exec -it roxie-rc1-n8iop -- bash -il

root@roxie-rc1-n8iop:/# /tmp/load.sh 
1
2
3
```

In another command-line session monitor kubernetes autoscale and pods status
```sh
:~/work/HPCC-Kubernetes/orchestrate-on-aws$ kubectl get hpa
NAME        REFERENCE                         TARGET    CURRENT   MINPODS   MAXPODS   AGE
roxie-rc1   ReplicationController/roxie-rc1   50%       246%      2         3         4m
:~/work/HPCC-Kubernetes/orchestrate-on-aws$ kubectl get pods
NAME                READY     STATUS    RESTARTS   AGE
dali-rc-cpkgl       1/1       Running   0          2h
esp-rc-4kp81        1/1       Running   0          2h
esp-rc-ymwh7        1/1       Running   0          2h
hpcc-ansible        1/1       Running   0          2h
nfs-server-o96pt    1/1       Running   0          2h
roxie-rc1-n8iop     1/1       Running   0          2h
roxie-rc1-td6wd     1/1       Running   0          1m
roxie-rc1-wungv     1/1       Running   0          1h
thor-rc0001-xi6wq   1/1       Running   0          2h
thor-rc0002-6fzze   1/1       Running   0          2h
```
Now CPU load is 246% which is above 50% threshold. There is a new roxie instancne created.
We you verify the roxie functions through ECLWatch or ESP <ecl ip>:8002. You can even access the
new roxie instance to check the roxie log

```sh
kubectl exec -it roxie-rc1-td6wd  -- bash -il
tail -l /var/log/HPCCSystems/myroxie/roxie.log

```
From hpcc-ansible mon_ips.log you can see the ansible hosts file (/etc/ansible/hosts) is re-generated
by environment.xml is not. It is due to we use roxie proxy service ip in environment.xml instead the 
real roxie instance ip.

Now you can exist the roxie instance and stop the load on the roxie instance runing /tmp/load.sh (CTL-C, and 
type 'n'). Monitor the autocale and pods status 
```sh
:~/work/HPCC-Kubernetes/orchestrate-on-aws$ kubectl get hpa
NAME        REFERENCE                         TARGET    CURRENT   MINPODS   MAXPODS   AGE
roxie-rc1   ReplicationController/roxie-rc1   50%       0%        2         3         16m
:~/work/HPCC-Kubernetes/orchestrate-on-aws$ kubectl get pod
NAME                READY     STATUS    RESTARTS   AGE
dali-rc-cpkgl       1/1       Running   0          2h
esp-rc-4kp81        1/1       Running   0          2h
esp-rc-ymwh7        1/1       Running   0          2h
hpcc-ansible        1/1       Running   0          2h
nfs-server-o96pt    1/1       Running   0          2h
roxie-rc1-n8iop     1/1       Running   0          2h
roxie-rc1-wungv     1/1       Running   0          2h
thor-rc0001-xi6wq   1/1       Running   0          2h
thor-rc0002-6fzze   1/1       Running   0          2h
```
The roxie instances are back to 2 since the CPU load is below the threshold 50%



### Scale roxie with replication controllers
You also can manually run kubectl replicate controller command to scale up or down of the pods.
For example you can increate thor pods to 3. You need stop auto-scale service first
```sh
:~/work/HPCC-Kubernetes/orchestrate-on-aws$ kubectl delete -f roxie-autoscale.yaml
horizontalpodautoscaler "roxie-rc1" deleted

:~/work/HPCC-Kubernetes/orchestrate-on-aws$ kubectl get rc
NAME          DESIRED   CURRENT   READY     AGE
dali-rc       1         1         1         2h
esp-rc        2         2         2         2h
nfs-server    1         1         1         2h
roxie-rc1     2         2         2         2h
thor-rc0001   1         1         1         2h
thor-rc0002   1         1         1         2h

:~/work/HPCC-Kubernetes/orchestrate-on-aws$ kubectl scale rc roxie-rc1 --replicas=3
replicationcontroller "roxie-rc1" scaled

:~/work/HPCC-Kubernetes/orchestrate-on-aws$ kubectl get pods
NAME                READY     STATUS    RESTARTS   AGE
dali-rc-cpkgl       1/1       Running   0          2h
esp-rc-4kp81        1/1       Running   0          2h
esp-rc-ymwh7        1/1       Running   0          2h
hpcc-ansible        1/1       Running   0          2h
nfs-server-o96pt    1/1       Running   0          2h
roxie-rc1-n8iop     1/1       Running   0          2h
roxie-rc1-wungv     1/1       Running   0          2h
roxie-rc1-x1njf     1/1       Running   0          2m
thor-rc0001-xi6wq   1/1       Running   0          2h
thor-rc0002-6fzze   1/1       Running   0          2h

```
Now there is three roxie instances.
From hpcc-ansible pod we can see the third ip added:
```sh
2016-10-04_17-48-18 Only esp/roxie ip(s) changed. Just update Ansible host file ...  
dali,esp,roxie,thor
dali :
ip: 10.244.1.6
esp :
ip: 10.244.4.5
ip: 10.244.3.4
roxie :
ip: 10.244.4.4
ip: 10.244.1.7
ip: 10.244.0.6
thor :
ip: 10.244.0.4
ip: 10.244.3.5
```


### Scale thor pods
For our configure each thor has a an extral 60GB volume attached.
To add third thor instance run
```sh
:~/work/HPCC-Kubernetes/orchestrate-on-aws$ bin/create-rc-w-esb.sh thor 3
Volume id: vol-e8422535
kubectl create -f bin/../thor/thor-rc0003.yaml
replicationcontroller "thor-rc0003" created
```



