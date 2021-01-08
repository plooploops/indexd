# Create a test storage account
# this uses az cli
RANDOMVAL=$(echo $RANDOM | tr '[0-9]' '[a-z]')
rgName="myrg$RANDOMVAL"
location='westus'
storageAccountName="mysa$RANDOMVAL"
fileShareName="myfileshare$RANDOMVAL"
spName="MySaSP$RANDOMVAL" # test service principal to access storage account
aksName="my-aks-$RANDOMVAL"
acrName="myacr$RANDOMVAL"
postgresName="mypostgres$RANDOMVAL"
postgresUsername="postgres"
postgresPassword="replaceP@SSW0RD"
aksIdentityName="myid$RANDOMVAL"

az group create -n $rgName -l $location

az storage account create -n $storageAccountName -g $rgName -l $location
storageAccountId=$(az storage account show -n $storageAccountName -g $rgName | jq -r '.id')

# https://docs.microsoft.com/en-us/azure/aks/use-managed-identity
# This can be handled by tf later.  First start with az cli.

### if you're using ManagedIdentityCredential
# set this to the name of your Azure Container Registry.  It must be globally unique

# Run the following line to create an Azure Container Registry if you do not already have one
az acr create -n $acrName -g $rgName --sku basic

az aks create -g $rgName -n $aksName --enable-managed-identity --attach-acr $acrName --generate-ssh-keys

# enable monitoring
# https://docs.microsoft.com/en-us/azure/azure-monitor/insights/container-insights-enable-existing-clusters
az aks enable-addons -a monitoring -n $aksName -g $rgName

# this is system assigned MSI
aksMSIJson=$(az aks show -g $rgName -n $aksName --query "identity")
aksMSIId=$(echo $aksMSIJson | jq -r '.principalId')

aksUserAssignedMSIJson=$(az aks show -g $rgName -n $aksName --query "identityProfile")
aksUserAssignedMSIClientId=$(echo $aksUserAssignedMSIJson | jq -r '.kubeletidentity.clientId')
aksUserAssignedMSIObjectId=$(echo $aksUserAssignedMSIJson | jq -r '.kubeletidentity.objectId')
aksUserAssignedMSIResourceId=$(echo $aksUserAssignedMSIJson | jq -r '.kubeletidentity.resourceId')
aksUserAssignedMSIName=$(az identity show --id $aksUserAssignedMSIResourceId --query "name" -otsv)

# https://azure.github.io/aad-pod-identity/docs/demo/standard_walkthrough/
aksIdentityRGName=$(az aks show -g $rgName -n $aksName --query nodeResourceGroup -otsv)
rgID=$(az group show -n $rgName --query "id" -otsv)
aksIdentityRGID=$(az group show -n $aksIdentityRGName --query "id" -otsv)
az identity create -g $aksIdentityRGName -n $aksIdentityName
identityClientId="$(az identity show -g $aksIdentityRGName -n $aksIdentityName --query clientId -otsv)"
identityResourceId="$(az identity show -g $aksIdentityRGName -n $aksIdentityName --query id -otsv)"

identityAssignmentId="$(az role assignment create --role Reader --assignee $identityClientId --scope $aksIdentityRGID --query id -otsv)"

# assign identity to storage account
az role assignment create --assignee $aksMSIId --role 'Contributor' --scope $storageAccountId
az role assignment create --assignee $identityClientId --role 'Contributor' --scope $storageAccountId
az role assignment create --assignee $aksUserAssignedMSIClientId --role "Contributor" --scope $storageAccountId

# setup postgres
postgresJson=$(az postgres server create -l $location -g $rgName -n $postgresName -u $postgresUsername -p $postgresPassword)
postgresId=$(echo $postgresJson | jq -r ".id")

# Assign identity to postgres
az role assignment create --assignee $aksMSIId --role "Contributor" --scope $postgresId
az role assignment create --assignee $identityClientId --role "Contributor" --scope $postgresId
az role assignment create --assignee $aksUserAssignedMSIClientId --role "Contributor"  --scope $postgresId

## Setup Azure File Share for volume mount (Placeholder, can also introduce Key Vault)
# https://docs.microsoft.com/en-us/azure/aks/azure-files-volume
azureStorageConnectionString=$(az storage account show-connection-string -n $storageAccountName -g $rgName -o tsv)
az storage share create -n $fileShareName --connection-string $azureStorageConnectionString
storageAccountKey=$(az storage account keys list --resource-group $rgName --account-name $storageAccountName --query "[0].value" -o tsv)

kubectl create namespace gen3

# this should come from CSI driver / KV.
kubectl create secret generic azure-secret --from-literal=azurestorageaccountname=$storageAccountName --from-literal=azurestorageaccountkey=$storageAccountKey -n gen3

# AAD pod identity
# https://azure.github.io/aad-pod-identity/docs/demo/standard_walkthrough/#1-deploy-aad-pod-identity

# Non-RBAC cluster (TODO: Try with RBAC cluster)
kubectl apply -f https://raw.githubusercontent.com/Azure/aad-pod-identity/master/deploy/infra/deployment.yaml

# For AKS clusters, deploy the MIC and AKS add-on exception by running -
kubectl apply -f https://raw.githubusercontent.com/Azure/aad-pod-identity/master/deploy/infra/mic-exception.yaml

export SUBSCRIPTION_ID=$(az account show --query "id" -otsv)
export IDENTITY_CLIENT_ID=$(echo $aksUserAssignedMSIClientId)
export IDENTITY_RESOURCE_ID=$(echo $aksUserAssignedMSIResourceId)
export IDENTITY_RESOURCE_GROUP=$(echo $rgName)
# for demo, assign identity to resource group
az role assignment create --role Reader --assignee $aksUserAssignedMSIClientId --scope $aksIdentityRGID
az role assignment create --role Reader --assignee $aksUserAssignedMSIClientId --scope $rgID
## If you already assigned a user assigned identity (MSI) upon cluster creation, the demo pod will try to use that instead of the newly created one.
export IDENTITY_ASSIGNMENT_ID="$(az role assignment create --role Reader --assignee ${IDENTITY_CLIENT_ID} --scope /subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${IDENTITY_RESOURCE_GROUP} --query id -otsv)"
export IDENTITY_NAME=$(echo $aksUserAssignedMSIName)

# Add azure identity for user assigned MSI
cat <<EOF | kubectl apply -f -
apiVersion: "aadpodidentity.k8s.io/v1"
kind: AzureIdentity
metadata:
  name: ${IDENTITY_NAME}
spec:
  type: 0
  resourceID: ${IDENTITY_RESOURCE_ID}
  clientID: ${IDENTITY_CLIENT_ID}
EOF

# Add Azure identity binding
cat <<EOF | kubectl apply -f -
apiVersion: "aadpodidentity.k8s.io/v1"
kind: AzureIdentityBinding
metadata:
  name: ${IDENTITY_NAME}-binding
spec:
  azureIdentity: ${IDENTITY_NAME}
  selector: ${IDENTITY_NAME}
EOF

# deploy demo azure identity pod.
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: demo
  labels:
    aadpodidbinding: $IDENTITY_NAME
spec:
  containers:
  - name: demo
    image: mcr.microsoft.com/oss/azure/aad-pod-identity/demo:v1.7.1
    args:
      - --subscriptionid=${SUBSCRIPTION_ID}
      - --clientid=${IDENTITY_CLIENT_ID}
      - --resourcegroup=${IDENTITY_RESOURCE_GROUP}
    env:
      - name: MY_POD_NAME
        valueFrom:
          fieldRef:
            fieldPath: metadata.name
      - name: MY_POD_NAMESPACE
        valueFrom:
          fieldRef:
            fieldPath: metadata.namespace
      - name: MY_POD_IP
        valueFrom:
          fieldRef:
            fieldPath: status.podIP
  nodeSelector:
    kubernetes.io/os: linux
EOF

# check the logs for the pod.
kubectl logs demo


# setup the db.
# get local ip address for firewall rule, can update to cluster next.
myIP=$(host -4 myip.opendns.com resolver1.opendns.com | grep myip | awk '{print $4}')
az postgres server firewall-rule create -g $rgName -s $postgresName -n allowMyIp --start-ip-address $myIP --end-ip-address $myIP

# you will also need to get the kubernetes LB ip address?

# assumes psql client installed, and host has firewall access
# At this point, you'll need to run deployment\scripts\postgresql\postgres_init_azure.sql
# This command assumes the following folder structure:
# /deployment
#   /scripts
#     /indexd
#     /postgresql
#       /postgres_init_azure.sql
# /azure-setup.sh
curDir=$(pwd)
# set password for call to psql. https://www.postgresql.org/docs/current/libpq-envars.html
PGPASSWORD=$postgresPassword psql -v sslmode=true -U "$postgresUsername@$postgresName" -h "$postgresName.postgres.database.azure.com" -p 5432 postgres -f "${curDir}/scripts/postgresql/postgres_init_azure.sql"

# copy to file share:
az storage share create -n $fileShareName --connection-string $azureStorageConnectionString

# copy configuration files
az storage file upload-batch -s deployment/scripts/indexd -d $fileShareName --destination-path /scripts/indexd --connection-string $azureStorageConnectionString
az storage file upload-batch -s deployment/Secrets -d $fileShareName --destination-path /Secrets/indexd --connection-string $azureStorageConnectionString

# set up logging share
az storage directory create -n logging -s $fileShareName --connection-string$azureStorageConnectionString
az storage directory create -n logging/indexd -s $fileShareName --connection-string $azureStorageConnectionString

# fetch credentials
az aks get-credentials -g $rgName -n $aksName

az acr login --name $acrName

# Build container (source should be root directory)
docker build -f Dockerfile -t "$acrName.azurecr.io/indexd:latest" .

az acr login --name "$acrName"

docker push "$acrName.azurecr.io/indexd:latest"

# need to put together yaml file for deploying container.

# kubectl apply -f deployment/namespace.yaml -n gen3
kubectl apply -f deployment/indexd.yaml -n gen3

