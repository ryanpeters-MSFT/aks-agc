# Azure Application Gateway for Containers

Creates a standard App Gateway for Containers. The AGC resource is created within the MC resource group and gets associated with a "alb" subnet.

## Quickstart

```powershell
# invoke setup.ps1 to create cluster, vnet, set permissions, and install ALB via helm
.\setup.ps1
```

Once setup is complete, it will output the ID of the subnet for ALB. You will need to update this value in [apploadbalancer.yaml](./apploadbalancer.yaml) under `spec.associations`. Once this is applied, it will provision an Application Gateway for Containers resource and associate it with this subnet.

```powershell
# update apploadbalancer.yaml subnet association and apply
kubectl apply -f .\apploadbalancer.yaml

# once applied, wait a few minutes and verify the AGC resource is created
az network alb list -o table
```

Finally, deploy the sample workloads. The manifest deploys two services, each serving an HTML page whose content is driven by the `CONTENT` environment variable. The default values are `Workload A` and `Workload B`.

```powershell
# deploy sample workload
kubectl apply -f .\workload.yaml
```

### Deploy using Ingress

To deploy using Ingress, apply the Ingress manifest to expose a route to `workload-a`.

```powershell
# create the ingress resource
kubectl apply -f .\ingress.yaml
```

Once an Ingress resource is deployed, retrieve the hostname and invoke a curl request.

```powershell
# get the hostname
$hostname = kubectl get ingress ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# invoke curl
curl.exe http://$hostname
```

### Deploy using Gateway API

To deploy using Gateway API and HttpRoute, apply their manifests to expose a gateway and a weighted canary route. The default split is 80% of traffic to `workload-a` and 20% to `workload-b`.

```powershell
# create the gateway and httproute resources
kubectl apply -f .\gateway.yaml -f .\httproute.yaml
```

Once an Gateway and HttpRoute resources are deployed, retrieve the hostname and invoke a curl request.

```powershell
# get the hostname
$hostname = kubectl get gateway gateway -o jsonpath='{.status.addresses[0].value}'

# invoke curl
curl.exe http://$hostname
```

## Observations/Notes
- It can still take several minutes to reconcile and create the resources. 
- Both "overlay" and regular CNI network plugin modes are supported.
- Once the AGC resource has been associated with the "alb" subnet, it will create a "Frontend" with a URL in the format `RANDOMSTRING.RANDOM.alb.azure.com`
- Currently, ALB requires AMD64 architecture for the nodes, otherwise `alb-controller` pods will not schedule, as they require the `kubernetes.io/arch` value of `amd64` on the nodes.

## Links
- [Quickstart: Deploy Application Gateway for Containers ALB Controller](https://learn.microsoft.com/en-us/azure/application-gateway/for-containers/quickstart-deploy-application-gateway-for-containers-alb-controller?tabs=install-helm-windows)
- [Quickstart: Create Application Gateway for Containers managed by ALB Controller](https://learn.microsoft.com/en-us/azure/application-gateway/for-containers/quickstart-create-application-gateway-for-containers-managed-by-alb-controller?tabs=new-subnet-aks-vnet)