## Install Kubernetes on Centos using kubeadm
- CentOS Linux release 7.9.2009 (Core)
- Kubernetes v1.14.0

### Check the version of centos
```bash
cat /etc/centos-release
```

### Install on all Node

1. Once we have logged in, we need to elevate privileges using **sudo**:
```bash
sudo su  
```

2. Disable SELinux:
```bash
setenforce 0
sed -i --follow-symlinks 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux
````

3. Enable the **br_netfilter** module for cluster communication:
```bash
modprobe br_netfilter
echo '1' > /proc/sys/net/bridge/bridge-nf-call-iptables
```

4. Ensure that the Docker dependencies are satisfied:
```bash
yum install -y yum-utils device-mapper-persistent-data lvm2
```

5. Add the Docker repo and install Docker:
```bash
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
yum install -y docker-ce
docker --version
```

6. Set the cgroup driver for Docker to systemd, reload systemd, then enable and start Docker:
```bash
sed -i '/^ExecStart/ s/$/ --exec-opt native.cgroupdriver=systemd/' /usr/lib/systemd/system/docker.service
systemctl daemon-reload
systemctl enable docker --now
```

7. Add the Kubernetes repo:
```bash
cat << EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=0
repo_gpgcheck=0
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
  https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF
```

8. Install Kubernetes **v1.14.0**:
```bash
yum install -y kubelet-1.14.0-0 kubeadm-1.14.0-0 kubectl-1.14.0-0 kubernetes-cni-0.7.5
```

9. Enable the **kubelet** service. The **kubelet** service will fail to start until the cluster is initialized, this is expected:
```bash
systemctl enable kubelet
```

### Install on Master Node only

10. Initialize the cluster using the IP range for Flannel:
```bash
kubeadm init --pod-network-cidr=10.244.0.0/16
```

11. Copy the **kubeadmn join** command that is in the output. We will need this later. or later using this command
```bash
kubeadm token create --print-join-command
```
12. Exit **sudo**, copy the **admin.conf** to your home directory, and take ownership.
```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

13. Deploy Flannel:
```bash
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel-old.yaml
```

14. Check the cluster state:
```bash
kubectl get pods --all-namespaces
```

### Install on Worker node only
16. Run the join command that you copied earlier, this requires running the command prefaced with sudo on the nodes (if we hadn't run sudo su to begin with). Then we'll check the nodes from the master.
```bash
kubeadm join 10.0.1.xxx:6443 --token qd85ib.08mhaskc80..... \
    --discovery-token-ca-cert-hash sha256:csad23......
```

### Try simple Pods
1. Create a simple deployment:
```bash
kubectl create deployment nginx --image=nginx
```
2. Inspect the pod:
```bash
kubectl get pods
```
3. Scale the deployment:
```bash
kubectl scale deployment nginx --replicas=4
```
4. Inspect the pods. We should have four now:
```bash
kubectl get pods
```