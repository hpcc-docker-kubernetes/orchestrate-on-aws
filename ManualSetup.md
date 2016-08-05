Change to your region if it not ap-southeast-1b

## NFS Volumes
There are two types of NFS Volumes: 1) share HPCC configuration such as  environment.xml 2) share roxie data for the roxie cluster

### Create EBS for HPCC Configuration
```sh
aws ec2 create-volume --availability-zone ap-southeast-1b --size 1 --volume-type gp2
```

### Create EBS for Roxie data
```sh
aws ec2 create-volume --availability-zone ap-southeast-1b --size 10 --volume-type gp2
```

## NFS Server
### Create a ReplicateController defined in  nfs-server-rc.yaml with NFS volume created above
```sh
kubectl create -f nfs-server-rc.yaml
```
The nfs container image by default run command "/usr/local/bin/run_nfs.sh /exports". Since we export several
directories we overwrite with container command and parameters "/usr/local/bin/run_nfs.sh /hpcc-config hpcc-data"
If manually change: 
```sh
  1) kubectl exec to the nfs-server 
  2) add /hpcc-config hpcc-data to /etc/exports and delete /exports 
  3) run "exportfs -r -s -a"
```

### Create a service for NFS server defined in  nfs-server-service.yaml
```sh
kubectl create -f nfs-server-service.yaml
```
Get nfs-server services ip (cluster ip)
If this ip doesn't work maybe try pod ip though it is not recommended.
```sh
kubectl describe services nfs-server
```

## Create Persistent Volumes (PV) and Persistent Volumes Claim
For each nfs exported storage there should be a pair of PV and PVC. The pods will use PVC to mount the NFS storage. 

### Create PV and PVC for HPCC configuration
Create Persistent Volume for nfs mount point /hpcc-config
```sh
kubectl create -f config-pv.yaml
```
To see the PV
```sh
kubectl describe pv config
```
Create Persistent Volume Claim  for nfs
```sh
kubectl create -f config-pvc.yaml
```
To see the PVC
```sh
kubectl describe pvc config
```
Create PV and PVC pair for nfs mount point /hpcc-config/roxie
```sh
kubectl create -f config-roxie-pv.yaml
kubectl create -f config-roxie-pvc.yaml
```
Create PV and PVC pair for nfs mount point /hpcc-config/esp
```sh
kubectl create -f config-esp-pv.yaml
kubectl create -f config-esp-pvc.yaml
```


### Create PV and PVC for Roxie Shared Data
Create Persistent Volume 
```sh
kubectl create -f data-pv.yaml
```
Create Persistent Volume Claim
```sh
kubectl create -f data-pvc.yaml
```

##  Roxie 
Every Roxie node will have one NFS shared /etc/HPCCSystems volume and one NFS shared /var/lib/HPCCSystems/hpcc-data volume
### Create Roxie ReplicateController
```sh
kubectl create -f roxie-rc.yaml
```
To check the status:
```sh
kubectl get rc roxie or kubectl get pod and kubectl get pod <pod name> -o json
```
### Create Roxie Service
```sh
kubectl create -f roxie-service.yaml
```
To check the status:
```sh
kubectl get service roxie or kubectl describe service roxie
```
## Esp 
Every Esp node will have one NFS shared /etc/HPCCSystems volume 
### Create Esp ReplicateController
```sh
kubectl create -f esp-rc.yaml
```
To check the status:
```sh
kubectl get rc esp or kubectl get pod and kubectl get pod <pod name> -o json
```
### Create Esp Service
```sh
kubectl create -f esp-service.yaml
```
To check the status:
```sh
kubectl get service esp or kubectl describe service esp
```

## Thor
Every Roxie node will have one NFS shared /etc/HPCCSystems volume and one EBS volume mounted to /var/lib/HPCCSystems/hpcc-data

### Create EBS for HPCC Configuration
```sh
aws ec2 create-volume --availability-zone ap-southeast-1b --size 10 --volume-type gp2
```
set volumeID in thor-rc1.yaml
```sh
kubectl create -f thor-rc1.yaml
```
Do same for second set:
```sh
aws ec2 create-volume --availability-zone ap-southeast-1b --size 10 --volume-type gp2
```
set volumeID in thor-rc2.yaml
```sh
kubectl create -f thor-rc2.yaml
```
To check the status:
```sh
kubectl get pod
```

## Ansible
