

I used ansible and jinja templates to get k3s setup on brand new nodes!

```
ansible-playbook playbook.yml
```

then once the commands are finished, check that the cluster looks good with
```
kubectl get pods -A
```

then to deploy our nginx test app
```
kube ctl apply -f apps/hello/hello.yaml
kubectl get pods -n nginxtest -o wide
```