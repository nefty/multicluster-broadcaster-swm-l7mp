#!/bin/bash
set -x

# set env vars
KUBECONFIG=.kube/config
CLUSTER1=germany
CLUSTER2=us-west
CLUSTER3=singapore

CLUSTER1IP=116.203.254.213
CLUSTER2IP=5.78.69.126
CLUSTER3IP=5.223.46.141

# get kubeconfig files
scp -o "StrictHostKeyChecking no" root@$CLUSTER1.broadcaster.stunner.cc:.kube/config ./$CLUSTER1
sed -i "s/127.0.0.1/$CLUSTER1IP/" $CLUSTER1
sed -i "s/default/$CLUSTER1/" $CLUSTER1

scp -o "StrictHostKeyChecking no" root@$CLUSTER2.broadcaster.stunner.cc:.kube/config ./$CLUSTER2
sed -i "s/127.0.0.1/$CLUSTER2IP/" $CLUSTER2
sed -i "s/default/$CLUSTER2/" $CLUSTER2

scp -o "StrictHostKeyChecking no" root@$CLUSTER3.broadcaster.stunner.cc:.kube/config ./$CLUSTER3
sed -i "s/127.0.0.1/$CLUSTER3IP/" $CLUSTER3
sed -i "s/default/$CLUSTER3/" $CLUSTER3

export KUBECONFIG=$CLUSTER1:$CLUSTER2:$CLUSTER3

# install clilium CLI
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}

# sync Cilium CA certificates. If they do not match between clusters multicluster features will be limited!
kubectl --context $CLUSTER2 delete secret -n kube-system cilium-ca
kubectl --context=$CLUSTER1 get secret -n kube-system cilium-ca -o yaml |  kubectl --context $CLUSTER2 create -f -
kubectl --context $CLUSTER2 delete pod -n kube-system -l app.kubernetes.io/part-of=cilium
kubectl --context $CLUSTER3 delete secret -n kube-system cilium-ca
kubectl --context=$CLUSTER1 get secret -n kube-system cilium-ca -o yaml |  kubectl --context $CLUSTER3 create -f -
kubectl --context $CLUSTER3 delete pod -n kube-system -l app.kubernetes.io/part-of=cilium

# enable cluster mesh
cilium clustermesh enable --context $CLUSTER1 --service-type LoadBalancer
cilium clustermesh enable --context $CLUSTER2 --service-type LoadBalancer
cilium clustermesh enable --context $CLUSTER3 --service-type LoadBalancer

# check cluster mesh status
cilium clustermesh status --context $CLUSTER1
cilium clustermesh status --context $CLUSTER2
cilium clustermesh status --context $CLUSTER3

# connect the clusters
cilium clustermesh connect --context $CLUSTER1 --destination-context $CLUSTER2
cilium clustermesh connect --context $CLUSTER1 --destination-context $CLUSTER3
cilium clustermesh connect --context $CLUSTER2 --destination-context $CLUSTER3

# check cluster mesh status
cilium clustermesh status --context $CLUSTER1 --wait
cilium clustermesh status --context $CLUSTER2 --wait
cilium clustermesh status --context $CLUSTER3 --wait

# test conenctions (takes a while)
#cilium connectivity test --context $CLUSTER1 --multi-cluster $CLUSTER2
#cilium connectivity test --context $CLUSTER1 --multi-cluster $CLUSTER3


