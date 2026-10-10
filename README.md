

1. set ips statically in dhcp (i use unifi so its a fixed ip)
2. set the host names of the machines

```
sudo hostnamectl set-hostname <new-hostname> && sudo nvim /etc/hosts
```
Make sure you have neovim installed and you replace the `127.0.0.1` name that is not `localhost`
devices

- `k8s-cp` = `10.0.0.90`
- `k8s-w1` = `10.0.0.67`
- `k8s-w2` = `10.0.0.250`

```
sudo nvim /etc/fstab
```

comment out the swap line
(the vm does not have swap enabled)




## cp k3s install

```
sudo mkdir -p /etc/rancher/k3s
sudo nvim /etc/rancher/k3s/config.yaml
```
then use the config yaml from cp/ 

then run the following
```
curl -sfL https://get.k3s.io -o k3s-install.sh
sudo sh k3s-install.sh
```

this installs it as the control plane node


```
systemctl status k3s
sudo k3s kubectl get nodes -o wide
sudo k3s kubectl describe node k8s-cp | grep Taints
sudo k3s kubectl get pods -A
```
gives us some good info and makes sure it is running


get the token for isntalling and linking the agents to the control plane
```
sudo cat /var/lib/rancher/k3s/server/node-token
```


on each of the worker nodes
```
sudo mkdir -p /etc/rancher/k3s
sudo nvim /etc/rancher/k3s/config.yaml
```
get the data from the wn/ config file and fill in the appropriate info

```
curl -sfL https://get.k3s.io -o k3s-install.sh
sudo INSTALL_K3S_EXEC=agent sh k3s-install.sh
```


check on the cp that all the installed nodes are being detected
```
sudo k3s kubectl get nodes
```

on mac run the following ot get gp node connect info
```
mkdir -p ~/.kube
ssh ubuntu@k8s-cp 'sudo cat /etc/rancher/k3s/k3s.yaml' > ~/.kube/config
chmod 600 ~/.kube/config
nvim ~/.kube/config
```

replace `127.0.0.1` with the tailscale ip so we can reach it remotely



rename from default to `homek8s`
```
kubectl config rename-context default homek8s
```



now to do some testing

```
kubectl create namespace nginxtest
kubectl config set-context --current --namespace=nginxtest
```


this creates three containers of the nginx image
```
kubectl create deployment hello --image=nginx:1.29-alpine --replicas=3
```

```
avin@mac ~ % kubectl get deploy,rs,pods -o wide
NAME                    READY   UP-TO-DATE   AVAILABLE   AGE   CONTAINERS   IMAGES              SELECTOR
deployment.apps/hello   3/3     3            3           8s    nginx        nginx:1.29-alpine   app=hello

NAME                             DESIRED   CURRENT   READY   AGE   CONTAINERS   IMAGES              SELECTOR
replicaset.apps/hello-54c79594   3         3         3       8s    nginx        nginx:1.29-alpine   app=hello,pod-template-hash=54c79594

NAME                       READY   STATUS    RESTARTS   AGE   IP          NODE     NOMINATED NODE   READINESS GATES
pod/hello-54c79594-5stpc   1/1     Running   0          8s    10.42.1.5   k8s-w1   <none>           <none>
pod/hello-54c79594-bp52r   1/1     Running   0          8s    10.42.1.6   k8s-w1   <none>           <none>
pod/hello-54c79594-jdrn5   1/1     Running   0          8s    10.42.2.4   k8s-w2   <none>           <none>
gavin@mac ~ % kubectl get deploy,rs,pods -o wide
NAME                    READY   UP-TO-DATE   AVAILABLE   AGE   CONTAINERS   IMAGES              SELECTOR
deployment.apps/hello   3/3     3            3           15s   nginx        nginx:1.29-alpine   app=hello

NAME                             DESIRED   CURRENT   READY   AGE   CONTAINERS   IMAGES              SELECTOR
replicaset.apps/hello-54c79594   3         3         3       15s   nginx        nginx:1.29-alpine   app=hello,pod-template-hash=54c79594

NAME                       READY   STATUS    RESTARTS   AGE   IP          NODE     NOMINATED NODE   READINESS GATES
pod/hello-54c79594-5stpc   1/1     Running   0          15s   10.42.1.5   k8s-w1   <none>           <none>
pod/hello-54c79594-bp52r   1/1     Running   0          15s   10.42.1.6   k8s-w1   <none>           <none>
pod/hello-54c79594-jdrn5   1/1     Running   0          15s   10.42.2.4   k8s-w2   <none>           <none>
gavin@mac ~ % kubectl delete pod hello-54c79594-jdrn5
pod "hello-54c79594-jdrn5" deleted from nginxtest namespace
gavin@mac ~ % kubectl delete pod hello-54c79594-jdrn5
Error from server (NotFound): pods "hello-54c79594-jdrn5" not found
gavin@mac ~ % kubectl get deploy,rs,pods -o wide
NAME                    READY   UP-TO-DATE   AVAILABLE   AGE   CONTAINERS   IMAGES              SELECTOR
deployment.apps/hello   3/3     3            3           46s   nginx        nginx:1.29-alpine   app=hello

NAME                             DESIRED   CURRENT   READY   AGE   CONTAINERS   IMAGES              SELECTOR
replicaset.apps/hello-54c79594   3         3         3       46s   nginx        nginx:1.29-alpine   app=hello,pod-template-hash=54c79594

NAME                       READY   STATUS    RESTARTS   AGE   IP          NODE     NOMINATED NODE   READINESS GATES
pod/hello-54c79594-4mjrl   1/1     Running   0          4s    10.42.2.5   k8s-w2   <none>           <none>
pod/hello-54c79594-5stpc   1/1     Running   0          46s   10.42.1.5   k8s-w1   <none>           <none>
pod/hello-54c79594-bp52r   1/1     Running   0          46s   10.42.1.6   k8s-w1   <none>           <none>
gavin@mac ~ % kubectl expose deployment hello --port=80
service/hello exposed
gavin@mac ~ % kubectl port-forward svc/hello 8080:80
Forwarding from 127.0.0.1:8080 -> 80
Forwarding from [::1]:8080 -> 80
Handling connection for 8080
```

then going to 
```
kubectl patch svc hello -p '{"spec":{"type":"NodePort"}}'
service/hello patched
gavin@mac ~ % kubectl get svc hello
NAME    TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
hello   NodePort   10.43.111.38   <none>        80:31361/TCP   2m4s
```

any of the ips in the cluster and using the port bound to 80 will show the traffic!


but isntead of doing it that way, lets do it decalrativly

```
kubectl apply -f apps/hello/hello.yaml
```

look at apps/hello directory for the yaml!
