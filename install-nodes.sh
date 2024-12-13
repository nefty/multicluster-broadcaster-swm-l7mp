#!/bin/bash

# iterate through the created vms and install the k3s env
for ip in $(cat hetzner-ips.txt);
do
    echo "Installing k3s env on $ip"
    scp -o "StrictHostKeyChecking no" manifests/*  root@$ip:
    ssh -o "StrictHostKeyChecking no" root@$ip /root/local-install.sh
    
    #ssh -o "StrictHostKeyChecking no" root@$ip kubectl apply -f /root/stunner-common.yaml
    #ssh -o "StrictHostKeyChecking no" root@$ip helm repo update
    #ssh -o "StrictHostKeyChecking no" root@$ip helm upgrade stunner-gateway-operator stunner/stunner-gateway-operator --namespace=stunner

    #ssh -o "StrictHostKeyChecking no" root@$ip REGION=$(echo $HOSTNAME | cut -d'-' -f5) sed -i "s/MYREGION/$REGION/g" livekit.yaml
    #ssh -o "StrictHostKeyChecking no" root@$ip kubectl apply -f /root/livekit.yaml -n livekit
    #ssh -o "StrictHostKeyChecking no" root@$ip kubectl delete pod -n livekit -l app=lk-meet
    #ssh -o "StrictHostKeyChecking no" root@$ip kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.1/cert-manager.yaml
	
	#coturn install
	#ssh -o "StrictHostKeyChecking no" root@$ip sed -i "s/99.99.99.99/$ip/g" coturn.yaml
	#ssh -o "StrictHostKeyChecking no" root@$ip kubectl apply -n stunner -f coturn.yaml
done
