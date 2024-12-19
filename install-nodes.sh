#!/bin/bash

# iterate through the created vms and install the k3s env
for ip in $(cat hetzner-ips.txt);
do
    echo "Installing k3s env on $ip"
    scp -o "StrictHostKeyChecking no" manifests/*  root@$ip:
    ssh -o "StrictHostKeyChecking no" root@$ip /root/local-install.sh
    
    # You can use these lines if you want to run a specific command an all VMs
    #ssh -o "StrictHostKeyChecking no" root@$ip kubectl apply -f /root/stunner-common.yaml
    #ssh -o "StrictHostKeyChecking no" root@$ip helm repo update
    #ssh -o "StrictHostKeyChecking no" root@$ip helm upgrade stunner-gateway-operator stunner/stunner-gateway-operator --namespace=stunner

    #ssh -o "StrictHostKeyChecking no" root@$ip REGION=$(hostname | cut -d"-" -f4,5) sed -i "s/MYREGION/$REGION/g" broadcaster.yaml
    #ssh -o "StrictHostKeyChecking no" root@$ip kubectl apply -f /root/broadcaster.yaml
done
