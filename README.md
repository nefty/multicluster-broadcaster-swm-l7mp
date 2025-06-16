# Globally Distributed WebRTC Broadcaster on Google Cloud Platform

This repository contains a rearchitected version of the joint demo between [Software Mansion](https://swmansion.com/) and [L7mp Technologies](https://l7mp.io/) - **migrated from Hetzner Cloud with Cilium Cluster Mesh to Google Cloud Platform** using managed services for improved scalability and operational efficiency.

> **Original Project**: The initial implementation used self-managed k3s clusters on Hetzner VMs with Cilium Cluster Mesh. This version demonstrates how to modernize the architecture using GCP-native services while maintaining the same globally distributed WebRTC functionality.

The project showcases a production-ready, globally distributed WebRTC streaming architecture using:
- **Elixir WebRTC** for real-time media processing and WHIP/WHEP protocols
- **STUNner** for WebRTC NAT traversal in Kubernetes environments  
- **GKE Multi-Cluster Services (MCS)** for cross-cluster service discovery
- **Erlang Distribution** for clustering Elixir nodes across regions via Google's private network

## Architecture Overview

The GCP-native architecture spans three regions with the following components:

### Regions & Infrastructure
- **us-east5** (North America)
- **europe-west9** (Europe) 
- **asia-southeast1** (Asia Pacific)

### Key GCP Services Used
- **Google Kubernetes Engine (GKE)**: Managed Kubernetes clusters with Autopilot
- **Multi-Cluster Services (MCS)**: Cross-cluster service discovery and load balancing  
- **Global External HTTPS Load Balancer**: Global anycast IP for WHIP/WHEP signaling traffic
- **Regional Network Load Balancers**: High-performance L4 load balancing for TURN/media traffic
- **Cloud Build**: Automated CI/CD pipeline with GitHub integration
- **Artifact Registry**: Container image storage with vulnerability scanning
- **Cloud DNS**: Geolocation-based routing for optimal performance

### Traffic Flow
- **Signaling (HTTPS/WebSocket)**: Global Load Balancer → Nearest healthy GKE cluster → Broadcaster pods
- **Media (UDP/TURN)**: Cloud DNS geolocation → Regional NLB → STUNner → Broadcaster pods  
- **Cross-cluster Communication**: Erlang Distribution over Google's private global network via MCS

## Documentation

For detailed architecture and implementation details:
- **[`docs/gcp_architecture.md`](./docs/gcp_architecture.md)** - Complete architecture overview, technology choices, and design decisions

## Quick Start

### Prerequisites
- GCP Project with billing enabled and APIs activated
- `gcloud` CLI configured with appropriate permissions
- `kubectl` installed
- Terraform (for infrastructure deployment)

### Deployment Overview
1. **Infrastructure**: Deploy GKE clusters and networking via Terraform
2. **CI/CD Setup**: Configure Cloud Build triggers for automated deployments  
3. **Application Deployment**: Push code changes to trigger deployment across all clusters
4. **Verification**: Test cross-cluster Erlang Distribution and WebRTC functionality

## Monitoring and Operations

### Connect to Clusters
```bash
# US East 5
gcloud container clusters get-credentials broadcaster-us --region=us-east5

# Europe West 9  
gcloud container clusters get-credentials broadcaster-eu --region=europe-west9

# Asia Southeast 1
gcloud container clusters get-credentials broadcaster-asia --region=asia-southeast1
```

### Monitor Application Status
```bash
# Check pod status across clusters
kubectl get pods -o wide

# Monitor Multi-Cluster Services resources
kubectl get serviceexports,serviceimports

# Watch application logs for clustering activity
kubectl logs -f <broadcaster-pod> | grep -i "cluster\|node\|connect"

# Check StatefulSet status
kubectl get statefulsets -o wide
```

### Test Cross-Cluster DNS Resolution
```bash
# Test MCS DNS resolution for each remote cluster
kubectl exec -it <broadcaster-pod> -- nslookup us-east5-broadcaster-headless.default.svc.clusterset.local
kubectl exec -it <broadcaster-pod> -- nslookup europe-west9-broadcaster-headless.default.svc.clusterset.local  
kubectl exec -it <broadcaster-pod> -- nslookup asia-southeast1-broadcaster-headless.default.svc.clusterset.local

# Test local cluster service
kubectl exec -it <broadcaster-pod> -- nslookup us-east5-broadcaster-headless.default.svc.cluster.local
```

### Verify Erlang Distribution Clustering
```bash
# Connect to Elixir remote shell
kubectl exec -it <broadcaster-pod> -- /app/bin/k8s_broadcaster remote

# In the IEx shell, check connected nodes
iex> Node.list()
iex> length(Node.list())  # Should show nodes from other clusters

# Test global registry functionality
iex> :syn.lookup(K8sBroadcaster.GlobalPeerRegistry, "some_key")

# Check cluster topology information
iex> K8sBroadcaster.Application.cluster(:c1)
iex> K8sBroadcaster.Application.cluster(:c2) 
iex> K8sBroadcaster.Application.cluster(:c3)
```

### Debug Multi-Cluster Services
```bash
# Check MCS resource status
kubectl describe serviceimport <service-name>
kubectl describe serviceexport <service-name>

# Verify GKE Fleet membership
gcloud container fleet memberships list

# Check EndpointSlice synchronization
kubectl get endpointslices -o wide

# Monitor MCS controller logs (if issues)
kubectl logs -n gke-system -l k8s-app=gke-mcs-controller
```

### Application Performance Monitoring
```bash
# Check WebRTC peer connections
kubectl exec -it <broadcaster-pod> -- curl localhost:4000/api/pc-config

# Monitor STUNner status
kubectl get udproutes,gateways -n default

# Check resource utilization
kubectl top pods
kubectl top nodes
```

## Key Differences from Original Architecture

| Aspect | Original (Hetzner + Cilium) | New (GCP Native) |
|--------|----------------------------|------------------|
| **Compute Platform** | k3s on Hetzner VMs | GKE Autopilot (managed) |
| **Cross-cluster Networking** | Cilium Cluster Mesh | Multi-Cluster Services (MCS) |
| **Service Discovery** | Cilium global services | MCS ServiceImport/ServiceExport |
| **Load Balancing** | Azure Traffic Manager | Global HTTPS LB + Regional NLBs |
| **CI/CD** | Manual deployment scripts | Cloud Build with automated triggers |
| **DNS Management** | Manual A records | Cloud DNS with geolocation policies |
| **Infrastructure Management** | Manual VM provisioning | Terraform + managed services |
| **Monitoring** | External monitoring setup | Integrated Cloud Monitoring |

## Benefits of GCP Migration

### Operational Benefits
- **Reduced Operational Overhead**: Managed Kubernetes eliminates cluster management
- **Enhanced Reliability**: Google's global private network and 99.95% SLA
- **Simplified Scaling**: Automatic cluster and node scaling based on demand
- **Integrated Security**: Workload Identity, private clusters, automated vulnerability scanning

### Technical Benefits  
- **Native Service Mesh**: MCS provides standard Kubernetes multi-cluster capabilities
- **Global Performance**: Anycast IPs and intelligent routing reduce latency
- **Observability**: Built-in monitoring, logging, and tracing with Cloud Operations
- **Cost Optimization**: Pay-per-use with Autopilot and resource right-sizing

### Development Benefits
- **Faster Iterations**: Automated CI/CD pipeline with sub-10 minute deployments
- **Better Testing**: Consistent environments across regions
- **Standard APIs**: Uses native Kubernetes resources instead of vendor-specific solutions

## Project Structure

```
├── docs/                    # Detailed documentation
├── terraform/              # Infrastructure as Code
├── kustomize/              # Kubernetes deployment manifests
│   ├── base/               # Common resources
│   └── overlays/           # Regional configurations
├── k8s_broadcaster/        # Elixir WebRTC application
└── cloudbuild.yaml         # CI/CD pipeline configuration
```

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

For major changes, please open an issue first to discuss the proposed changes.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- **[Software Mansion](https://swmansion.com/)** for Elixir WebRTC expertise and the original Broadcaster application
- **[L7mp Technologies](https://l7mp.io/)** for STUNner and cloud-native WebRTC solutions
- **Google Cloud Platform** for providing the managed infrastructure services
- Original Hetzner/Cilium implementation for architectural inspiration

## Related Resources

- [Elixir WebRTC Documentation](https://hexdocs.pm/ex_webrtc/)
- [STUNner Documentation](https://docs.l7mp.io/en/stable/)  
- [GKE Multi-Cluster Services](https://cloud.google.com/kubernetes-engine/docs/how-to/multi-cluster-services)
- [Original Blog Post](https://blog.swmansion.com/building-a-globally-distributed-webrtc-service-with-elixir-webrtc-stunner-and-cilium-cluster-mesh-54553bc066ad) about the Hetzner/Cilium implementation
