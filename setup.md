

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