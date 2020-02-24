### Bootstrapping Windows Nodes with CAPI provider Azure  and Cloudbase Init

Guide on how to use CAPZ ( Cluster API provider Azure ) with Cloudbase-Init in
order to bootstrap K8s Windows Nodes.

author: @adelina-t ( Adelina Tuvenie - Cloudbase Solutions )

### Requirements

- Windows Azure image containing latest [Cloudbase-Init](https://cloudbase.it/cloudbase-init/)
- [kind](https://github.com/kubernetes-sigs/kind) for setting up management cluster
- envsubst

### Prepare management cluster

```
kind cluster create --name capz-demo
```

### Installation

### Install CAPI, Bootstrap provider & infra provider components

1. CAPI components

```
kubectl create -f https://github.com/kubernetes-sigs/cluster-api/releases/download/v0.2.9/cluster-api-components.yaml
```

2. Kubeadm bootstrap provider 

```
kubectl create -f https://github.com/kubernetes-sigs/cluster-api-bootstrap-provider-kubeadm/releases/download/v0.1.5/bootstrap-components.yaml
```

3. Install CAPZ  infrastructure provider

```
# Create the base64 encoded credentials
export AZURE_SUBSCRIPTION_ID_B64="$(echo -n "$AZURE_SUBSCRIPTION_ID" | base64 | tr -d '\n')"
export AZURE_TENANT_ID_B64="$(echo -n "$AZURE_TENANT_ID" | base64 | tr -d '\n')"
export AZURE_CLIENT_ID_B64="$(echo -n "$AZURE_CLIENT_ID" | base64 | tr -d '\n')"
export AZURE_CLIENT_SECRET_B64="$(echo -n "$AZURE_CLIENT_SECRET" | base64 | tr -d '\n')"

```

We will need to replace the CAPZ manager image in the deployment with a custom one built from this branch: https://github.com/adelina-t/cluster-api-provider-azure/tree/windows-vms
because the current CAPZ does not support Windows VMs at the moment.

```
curl -L https://github.com/kubernetes-sigs/cluster-api-provider-azure/releases/download/v0.3.0/infrastructure-components.yaml | sed "s/us.gcr.io\/k8s-artifacts-prod\/cluster-api-azure\/cluster-api-azure-controller:v0.3.0/atuvenie\/capz-windows-amd64:0.1/g" | envsubst | kubectl create -f -
```

### Deploy K8s Cluster

Once all the CAPI components have deployed, we can start creating our cluster. This example cluster will contain
two machines, one linux machine for the controlplane and one Windows Node.

1. Deploy cluster 

Use [this](https://github.com/adelina-t/cloudbase-init-capz-demo/blob/master/specs/cluster.yaml) demo cluster spec and customize it according to your needs.
By default, CAPZ will create a vnet for the cluster with CIDR 10.0.0.0/8 .

```
kubectl create -f cluster.yaml
```

2. Deploy controlplane machine

Use [this](https://github.com/adelina-t/cloudbase-init-capz-demo/blob/master/specs/controlplane.yaml) demo spec for the controlplane. Customize it according to your needs.

```
export AZURE_SUBSCRIPTION_ID_B64="$(echo -n "$AZURE_SUBSCRIPTION_ID" | base64 | tr -d '\n')"
export AZURE_TENANT_ID_B64="$(echo -n "$AZURE_TENANT_ID" | base64 | tr -d '\n')"
export AZURE_CLIENT_ID_B64="$(echo -n "$AZURE_CLIENT_ID" | base64 | tr -d '\n')"
export AZURE_CLIENT_SECRET_B64="$(echo -n "$AZURE_CLIENT_SECRET" | base64 | tr -d '\n')"

SSH_PUB_KEY_FILE="/path/to/rsa/public/key"
# Export ssh key file
export SSH_PUBLIC_KEY=$(cat "${SSH_PUB_KEY_FILE}" | base64 | tr -d '\r\n')

export AZURE_LOCATION="westeurope"

cat controlplane.yaml | envsubst | kubectl create -f -

```

Verify that the control plane machine deployed correctly

```
kubectl get machines --selector cluster.x-k8s.io/control-plane
```
 
If all went well, you can retrieve the kubeconfig for the deployed cluster:

```
kubectl --namespace=default get secret/capi-quickstart-kubeconfig -o json \
  | jq -r .data.value \
  | base64 --decode \
  > ./capi-quickstart.kubeconfig
```

3. Deploy Flannel CNI

Use [this](https://github.com/adelina-t/cloudbase-init-capz-demo/blob/master/specs/addons.yaml) addons spec for the flannel CNI deployment.
Pay close attention to the CIDR for the flannel network and change it to correspond to the pod CIDR you selected in the cluster spec.

```
kubectl create -f addons.yaml
```

4. Deploy Windows Node.

In order for Kubeadm join to work with Windows without requiring additional wrapper scripts, we will need to have kube-proxy and flannel running in
a containr on the Windows Node. For this, we use [wins](https://github.com/rancher/wins) in order to be able to proxy commands from Windows Containers to
the Windows Host. More detail about this are described [here](https://github.com/benmoss/kubeadm-windows).

- Prepare Windows image.

For the Windows node you need to prepare a Windows Server 1809 ( or later ) image that contains Cloudbase-Init. 
The image must also contain kubelet, kubeadm & wins. Use [this](https://github.com/benmoss/kubeadm-windows/blob/master/windows-node.ps1) helper script when creating your image or 
run it in `preKubeadmCommands` section of the KubeadmConfig spec for the node. 

- Create MachineDeployment for Windows Node.

Use [this](https://github.com/adelina-t/cloudbase-init-capz-demo/blob/master/specs/machinesdeployment.yaml) MachineDeployment spec for the Windows Node.

Be careful to change the image reference in the AzureMachineTemplate to point to your image that you just created.

```
export AZURE_SUBSCRIPTION_ID_B64="$(echo -n "$AZURE_SUBSCRIPTION_ID" | base64 | tr -d '\n')"
export AZURE_TENANT_ID_B64="$(echo -n "$AZURE_TENANT_ID" | base64 | tr -d '\n')"
export AZURE_CLIENT_ID_B64="$(echo -n "$AZURE_CLIENT_ID" | base64 | tr -d '\n')"
export AZURE_CLIENT_SECRET_B64="$(echo -n "$AZURE_CLIENT_SECRET" | base64 | tr -d '\n')"

SSH_PUB_KEY_FILE="/path/to/rsa/public/key"
# Export ssh key file
export SSH_PUBLIC_KEY=$(cat "${SSH_PUB_KEY_FILE}" | base64 | tr -d '\r\n')

export AZURE_LOCATION="westeurope2"

cat machinedeployment.yaml | envsubst | kubectl create -f -

```

Note: The machine might take a while to deploy and for flannel to start as it needs to pull images for kube-proxy & flannel.

#### A few words about the `preKubeadmCommands` in machinedeployment.yaml

These are commands that are being run before calling `kubeadm join`. The take care of setting up the Docker nat network & External HNS network needed for flannel.

### Cloudbase-Init logs

On the Windows Node, Cloudbase-Init logs can be found in:
```
c:\Program Files\CloudbaseSolutions\Cloudbase-Init
```

### References

- [1] CAPI QuickStart: https://cluster-api.sigs.k8s.io/user/quick-start.html
- [2] Kubeadm & Windows work thanks to @benmoss : https://github.com/benmoss/kubeadm-windows
- [3] Cloudbase-Init: https://cloudbase.it/cloudbase-init/
- [4] Cloudbase-Init docs: https://cloudbase-init.readthedocs.io/en/latest/
