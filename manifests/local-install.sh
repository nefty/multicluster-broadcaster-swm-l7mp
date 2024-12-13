#!/bin/bash

CLUSTERNAME=$(echo $HOSTNAME | cut -d'-' -f4,5)
CLUSTERID=1
CLUSTERIPAM="10.101.0.0/16"

# Switch case to set the integer based on the input string
case "$CLUSTERNAME" in
    "germany")
        CLUSTERID=1
        CLUSTERIPAM="10.101.0.0/16"
        ;;
    "us-west")
        CLUSTERID=2
        CLUSTERIPAM="10.102.0.0/16"
        ;;
    "singapore")
        CLUSTERID=3
        CLUSTERIPAM="10.103.0.0/16"
        ;;
    # Default case    
    *) 
        CLUSTERID=4
        CLUSTERIPAM="10.104.0.0/16"
        ;;
esac

# 1: install k3s
PUBLICIP=$(curl -4 ifconfig.me)
sudo rm -rf /etc/cni/net.d
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik --flannel-backend=none --disable-kube-proxy --disable-network-policy" sh -

# 2: set up kubectl
rm -rf $HOME/.kube
mkdir -p $HOME/.kube
sudo cp -i /etc/rancher/k3s/k3s.yaml $HOME/.kube/config
sudo chown $(id -u):$(id -g) /etc/rancher/k3s/k3s.yaml
sudo chown $(id -u):$(id -g) $HOME/.kube/config

echo 'source <(kubectl completion bash)' >>~/.bashrc
echo 'alias k=kubectl' >>~/.bashrc
echo 'complete -o default -F __start_kubectl k' >>~/.bashrc

kubectl version
echo "Waiting for system pods to be created in kube-system namespace..."
while [ $(kubectl get pods -n kube-system) -le 1 ]; do
    echo -n "."
    sleep 1
done
kubectl get nodes && kubectl get pods -A

# 3: get helm
curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
echo 'source <(helm completion bash)' >>~/.bashrc
helm repo add cilium https://helm.cilium.io/
helm repo update

# 4: install cilium with cilium CLI
IP=$(ip -f inet addr show eth0 | grep -Po 'inet \K[\d.]+')
PORT=6443
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}

cilium install --set cluster.name=$CLUSTERNAME --set cluster.id=$CLUSTERID --set ipam.operator.clusterPoolIPv4PodCIDRList="$CLUSTERIPAM" \
    --set clustermesh.enableEndpointSliceSynchronization=true \
    --set kubeProxyReplacement=true \
    --set k8sServiceHost=$IP \
    --set k8sServicePort=$PORT

kubectl get pods -n kube-system
echo "Waiting for cilium pods to be ready..."
sleep 5
kubectl wait --for=condition=Ready -n kube-system pod  -l app.kubernetes.io/name=cilium-agent --timeout=90s

# 5. install nginx ingress
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.2/deploy/static/provider/baremetal/deploy.yaml
kubectl patch service -n ingress-nginx ingress-nginx-controller -p '{"spec": {"type": "LoadBalancer"}}'
echo "Waiting for nginx ingress to be ready..."
kubectl wait --for=condition=Ready -n ingress-nginx pod  -l app.kubernetes.io/component=controller --timeout=90s
kubectl get pods -n ingress-nginx

# 6. install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.1/cert-manager.yaml
echo "Waiting for cert-manager to be ready..."
kubectl wait --for=condition=Ready -n cert-manager pod  -l app.kubernetes.io/component=webhook --timeout=90s
kubectl apply -f cloudflare-secret.yaml
kubectl apply -f issuer.yaml
kubectl get pods -n cert-manager

# 7. install stunner
helm repo add stunner https://l7mp.io/stunner
helm repo update
helm install stunner-gateway-operator stunner/stunner-gateway-operator --create-namespace --namespace=stunner
kubectl apply -f stunner-common.yaml

# 8. install broadcaster
sed -i "s/MYREGION/$CLUSTERNAME/g" broadcaster.yaml
kubectl apply -f broadcaster.yaml -n default
kubectl apply -f broadcaster-udproute.yaml
