$GROUP = "rg-aks-agc"
$VNET = "vnet"
$AKS_SUBNET = "aks"
$ALB_SUBNET = "alb"
$CLUSTER_NAME = "agccluster"
$IDENTITY_NAME = "agcuser"

# create the resource group
az group create -n $GROUP -l eastus2 --query id -o tsv

# create a vnet
az network vnet create -n $VNET -g $GROUP --address-prefixes 10.0.0.0/16

# create subnets for AKS and ALB
$AKS_SUBNET_ID = az network vnet subnet create `
    -n $AKS_SUBNET -g $GROUP `
    --vnet-name $VNET `
    --address-prefixes 10.0.0.0/24 `
    -o tsv --query id

$ALB_SUBNET_ID = az network vnet subnet create `
    -n $ALB_SUBNET -g $GROUP `
    --vnet-name $VNET `
    --address-prefixes 10.0.1.0/24 `
    --delegations 'Microsoft.ServiceNetworking/trafficControllers' `
    -o tsv --query id

# create a managed identity for fedarated credential
$PRINCIPAL_ID = az identity create -g $GROUP -n $IDENTITY_NAME -o tsv --query principalId

Start-Sleep -Seconds 10

# create the AKS cluster with the managed identity
az aks create -n $CLUSTER_NAME -g $GROUP `
    --vnet-subnet-id $AKS_SUBNET_ID `
    --network-plugin azure `
    --network-plugin-mode overlay `
    --node-vm-size Standard_D8s_v6 `
    --enable-oidc-issuer `
    --enable-workload-identity `
    --service-cidr 10.1.0.0/24 `
    --dns-service-ip 10.1.0.3 `
    -c 2

# get the node resource group and ID
$NODE_RESOURCE_GROUP = az aks show -n $CLUSTER_NAME -g $GROUP --query nodeResourceGroup -o tsv
$NODE_RESOURCE_GROUP_ID = az group show -n $NODE_RESOURCE_GROUP --query id -o tsv

# apply Reader role to the AKS managed cluster resource group for the newly provisioned identity
az role assignment create `
    --assignee-object-id $PRINCIPAL_ID `
    --assignee-principal-type ServicePrincipal `
    --scope $NODE_RESOURCE_GROUP_ID `
    --role "acdd72a7-3385-48ef-bd42-f606fba81ae7" # Reader role

# Delegate AppGw for Containers Configuration Manager role to AKS Managed Cluster RG
az role assignment create `
    --assignee-object-id $PRINCIPAL_ID `
    --assignee-principal-type ServicePrincipal `
    --scope $NODE_RESOURCE_GROUP_ID `
    --role "fbc52c3f-28ad-4303-a892-8a056630b8f1" # AppGw for Containers Configuration Manager

# Delegate Network Contributor permission for join to association subnet
az role assignment create `
    --assignee-object-id $PRINCIPAL_ID `
    --assignee-principal-type ServicePrincipal `
    --scope $ALB_SUBNET_ID `
    --role "4d97b98b-1d4f-4787-a291-c67834d212e7" # Network Contributor

Start-Sleep -Seconds 10

# get the OIDC issuer URL
$OIDC_ISSUER_URL = az aks show -n $CLUSTER_NAME -g $GROUP --query "oidcIssuerProfile.issuerUrl" -o tsv

az identity federated-credential create `
    --name "azure-alb-identity" `
    --identity-name $IDENTITY_NAME `
    -g $GROUP `
    --issuer $OIDC_ISSUER_URL `
    --subject "system:serviceaccount:alb:alb-controller-sa"

# get AKS credentials
az aks get-credentials --resource-group $GROUP --name $CLUSTER_NAME --overwrite-existing

# deploy ALB via Helm
helm install alb-controller oci://mcr.microsoft.com/application-lb/charts/alb-controller `
    --namespace "alb" `
    --create-namespace `
    --version 1.8.12 `
    --set albController.namespace="alb" `
    --set albController.podIdentity.clientID=$(az identity show -g $GROUP -n $IDENTITY_NAME --query clientId -o tsv)

# output the subnet ID for the App Gateway
"Update spec.associations in ApplicationLoadBalancer manifest: $ALB_SUBNET_ID"