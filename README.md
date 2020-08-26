# Kubernetes Windows Nodes with CAPI provider Azure and Cloudbase-Init

Guide on how to use CAPZ (Cluster API provider Azure) with Cloudbase-Init in order to bootstrap K8s Windows nodes.

Authors:
* @adelina-t (Adelina Tuvenie - Cloudbase Solutions)
* @ionutbalutoiu (Ionut Balutoiu - Cloudbase Solutions)

## Requirements

* Windows Azure image containing latest [Cloudbase-Init](https://cloudbase.it/cloudbase-init/) already published to an Azure shared gallery. Guide on how to prepare the image is available [here](https://github.com/ionutbalutoiu/k8s-e2e-runner/tree/capz_flannel/image-builder/azure-cbsl-init).
* `kind` tool, used to deploy the management cluster. It can be installed via:
    ```
    sudo curl -Lo /usr/local/bin/kind https://github.com/kubernetes-sigs/kind/releases/download/v0.8.1/kind-linux-amd64
    sudo chmod +x /usr/local/bin/kind
    ```
* `clusterctl` tool, used to add the cluster-api components with CAPZ infrastructure plugin. It can be installed via:
    ```
    sudo curl -Lo /usr/local/bin/clusterctl https://github.com/kubernetes-sigs/cluster-api/releases/download/v0.3.8/clusterctl-linux-amd64
    sudo chmod +x /usr/local/bin/clusterctl
    ```
* `envsubst` tool installed.

## Deployment Steps

1. Deploy the management cluster via `kind`:
    ```
    kind create cluster --name capz-demo
    ```

2. Set the proper environment variables used by the Azure provider with their base64 encoded values:
    ```
    export AZURE_TENANT_ID=<TENANT_ID>
    export AZURE_CLIENT_ID=<CLIENT_ID>
    export AZURE_CLIENT_SECRET=<CLIENT_SECRET>
    export AZURE_SUBSCRIPTION_ID=<SUBSCRIPTION_ID>

    export AZURE_SUBSCRIPTION_ID_B64="$(echo -n "$AZURE_SUBSCRIPTION_ID" | base64 | tr -d '\n')"
    export AZURE_TENANT_ID_B64="$(echo -n "$AZURE_TENANT_ID" | base64 | tr -d '\n')"
    export AZURE_CLIENT_ID_B64="$(echo -n "$AZURE_CLIENT_ID" | base64 | tr -d '\n')"
    export AZURE_CLIENT_SECRET_B64="$(echo -n "$AZURE_CLIENT_SECRET" | base64 | tr -d '\n')"
    ```

3. Install the cluster api components with the Azure provider patched to work with Cloudbase-init Windows nodes, and wait for all the components to be ready
    ```
    clusterctl init --infrastructure azure:v0.4.6 --config specs/capz-config.yaml
    kubectl wait --for=condition=Available deployments --all --all-namespaces
    ```

    NOTE: [This](https://github.com/ionutbalutoiu/cluster-api-provider-azure/commit/9c8daedac75959b141fec7ea909c2c1fd0bd484b) is the patch to enable Cloudbase-init Windows nodes based on CAPZ `v0.4.6`.

4. Set the required environment variables to deploy the new K8s cluster via CAPZ:
    ```
    export KUBERNETES_VERSION=v1.18.8
    export AZURE_SSH_PUBLIC_KEY="$(cat $HOME/.ssh/id_rsa.pub)"
    export AZURE_SSH_PUBLIC_KEY_B64="$(echo $AZURE_SSH_PUBLIC_KEY | base64 | tr -d '\n')"

    export WINDOWS_WORKER_IMAGE_RG="adtv-capz-win"
    export WINDOWS_WORKER_IMAGE_GALLERY="capz_gallery"
    export WINDOWS_WORKER_IMAGE_DEFINITION="ws-ltsc2019-docker-cbsl-init"
    export WINDOWS_WORKER_IMAGE_VERSION="1.0.0"
    ```

5. Deploy the new CAPZ cluster:
    ```
    cat specs/capz-cluster.yaml | envsubst | kubectl apply -f -
    cat specs/capz-control-plane.yaml | envsubst | kubectl apply -f -
    cat specs/capz-windows-workers.yaml | envsubst | kubectl apply -f -
    ```

6. Wait until the new cluster is provisioned. You can use `kubectl get cluster` and `kubectl get machine` to see the status of the new k8s deployement. When it's ready, it should report the cluster `Provisioned`, and the machines `Running`:
    ```
    $ kubectl get cluster
    NAME        PHASE
    capz-demo   Provisioned

    $ kubectl get machine -o=custom-columns=NAME:.metadata.name,PHASE:.status.phase
    NAME                            PHASE
    capi-win-695c4d6cf6-gmvc5       Running
    capi-win-695c4d6cf6-mw5nf       Running
    capz-demo-control-plane-ptd6w   Running
    ```

7. When the cluster is succesfully deployed, fetch the kubeconfig, and use it for the next commands:
    ```
    kubectl get secret capz-demo-kubeconfig -o json | \
        jq -r .data.value | \
        base64 --decode > /tmp/capz-demo.kubeconfig

    export KUBECONFIG=/tmp/capz-demo.kubeconfig
    ```

8. At this moment, if we run `kubectl get pods -n kube-system`, we may notice that there isn't any CNI setup:
    ```
    NAME                                                    READY   STATUS    RESTARTS   AGE
    coredns-66bff467f8-29mxb                                0/1     Pending   0          2m7s
    coredns-66bff467f8-kgn8q                                0/1     Pending   0          2m7s
    etcd-capz-demo-control-plane-zkw8z                      1/1     Running   0          2m26s
    kube-apiserver-capz-demo-control-plane-zkw8z            1/1     Running   0          2m26s
    kube-controller-manager-capz-demo-control-plane-zkw8z   1/1     Running   0          2m26s
    kube-proxy-j6rpg                                        1/1     Running   0          2m7s
    kube-scheduler-capz-demo-control-plane-zkw8z            1/1     Running   0          2m26s
    ```

9. Deploy the kube-flannel CNI on Linux:
    ```
    kubectl apply -f specs/kube-flannel.yaml
    ```

    After a bit, if we list the pods from `kube-system`, we shall see the kube-flannel pods `Running`, and the CNI setup:
    ```
    NAME                                                    READY   STATUS    RESTARTS   AGE
    coredns-66bff467f8-29mxb                                1/1     Running   0          10m
    coredns-66bff467f8-kgn8q                                1/1     Running   0          10m
    etcd-capz-demo-control-plane-zkw8z                      1/1     Running   0          10m
    kube-apiserver-capz-demo-control-plane-zkw8z            1/1     Running   0          10m
    kube-controller-manager-capz-demo-control-plane-zkw8z   1/1     Running   0          10m
    kube-flannel-ds-amd64-5888g                             1/1     Running   0          84s
    kube-proxy-j6rpg                                        1/1     Running   0          10m
    kube-scheduler-capz-demo-control-plane-zkw8z            1/1     Running   0          10m
    ```

10. Add `kube-flannel` and `kube-proxy` on the Windows worker nodes, and wait for all the pods to be ready:
    ```
    kubectl apply -f specs/kube-flannel-windows.yaml
    kubectl apply -f specs/kube-proxy-windows.yaml
    kubectl wait --for=condition=Ready --timeout 30m pods --all --all-namespaces
    ```

11. Deploy a simple K8s deployment with a PowerShell-based webserver. It will configure a [Kubernetes deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) with a replica of 2, and a cluster IP on top of those:
    ```
    kubectl apply -f specs/win-webserver.yaml
    ```

12. Wait until the pods are running and the cluster IP is ready:
    ```
    $ kubectl get pods -o wide
    NAME                             READY   STATUS    RESTARTS   AGE   IP           NODE             NOMINATED NODE   READINESS GATES
    win-webserver-79bdf78b75-2dhfs   1/1     Running   0          16s   10.244.1.4   capi-win-fvjx9   <none>           <none>
    win-webserver-79bdf78b75-bgwqf   1/1     Running   0          16s   10.244.2.4   capi-win-dgpnq   <none>           <none>

    $ kubectl get svc
    NAME            TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
    win-webserver   ClusterIP   10.109.162.22   <none>        80/TCP    4m14s
    ```

13. SSH into the master node:
    ```
    MASTER_PUBLIC_ADDRESS=$(kubectl --kubeconfig $HOME/.kube/config get cluster -o=custom-columns=ADDRESS:.spec.controlPlaneEndpoint.host --no-headers)

    ssh capi@$MASTER_PUBLIC_ADDRESS
    ```

14. Try to ping the pods cluster addresses, and curl the webserver cluster IP:
    ```
    $ ping 10.244.1.4
    PING 10.244.1.4 (10.244.1.4) 56(84) bytes of data.
    64 bytes from 10.244.1.4: icmp_seq=1 ttl=127 time=2.39 ms
    64 bytes from 10.244.1.4: icmp_seq=2 ttl=127 time=2.08 ms
    ...

    $ ping 10.244.2.4
    PING 10.244.2.4 (10.244.2.4) 56(84) bytes of data.
    64 bytes from 10.244.2.4: icmp_seq=1 ttl=127 time=2.40 ms
    64 bytes from 10.244.2.4: icmp_seq=2 ttl=127 time=1.91 ms
    ...

    $ curl 10.109.162.22
    <html><body><H1>Windows Container Web Server</H1><p>IP 10.244.1.4 callerCount 1 </body></html>

    $ curl 10.109.162.22
    <html><body><H1>Windows Container Web Server</H1><p>IP 10.244.2.4 callerCount 1 </body></html>
    ```

    If everything deployed succesfully, the above commands should work as illustrated, and this will confirm:
    * Pod <-> Pod communication
    * ClusterIP functionality


## Troubleshooting

### Cloudbase-Init logs

On the Windows Node, Cloudbase-Init logs can be found at:
```
C:\Program Files\Cloudbase Solutions\Cloudbase-Init\Log
```

## References

- [1] CAPI QuickStart: https://cluster-api.sigs.k8s.io/user/quick-start.html
- [2] Kubeadm & Windows work thanks to @benmoss : https://github.com/benmoss/kubeadm-windows
- [3] Cloudbase-Init: https://cloudbase.it/cloudbase-init/
- [4] Cloudbase-Init docs: https://cloudbase-init.readthedocs.io/en/latest/
- [5] sig-windows-tools: https://github.com/kubernetes-sigs/sig-windows-tools/