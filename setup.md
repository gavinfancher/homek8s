

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