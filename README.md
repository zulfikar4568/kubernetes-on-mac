# Installation of Kubernetes the Kubeadm way on Mac M1

This is setup is for Mac with M1, M2 Apple Silicon. Virtualbox doesn't support thus we use multipass to setup the nodes ubuntu or use vagrant + VMware Fusion.

## Prerequisites

* Apple M1 or M2 system
* 8GB RAM (16GB preferred).
    * All configurations - One control plane node will be provisioned - `kubemaster`
    * If you have less than 16GB then only one worker node will be provisioned - `kubeworker1`
    * If you have 16GB or more then two workers will be provisioned - `kubeworker01` and `kubeworker2`
* You have homebrew installed on your mac.

    ### Install using Multipass
* Install [Multipass](https://multipass.run/docs/installing-on-macos)
  ```bash
  brew install --cask multipass
  ```
* Install [JQ](https://github.com/jqlang/jq/wiki/Installation#macos)
  ```bash
  brew install jq
  ```
    ### Install using Vagrant with ubuntu 20.04
* Install [VMWare Fusion](https://www.vmware.com/products/fusion.html)
  You can download VMWare Fusion free Edition for learning purpose. You need to register your account to get the License

* Install [Vagrant](https://formulae.brew.sh/cask/vagrant)
  ```bash
  brew install --cask vagrant
  vagrant --version
  ```
  Install VMWare Utility
  ```bash
  brew install vagrant-vmware-utility
  ```
  You need to setup vagrant plugin [vmware](https://developer.hashicorp.com/vagrant/docs/providers/vmware/installation)
  ```bash
  vagrant plugin install vagrant-vmware-desktop
  vagrant plugin list
  ```

## Installing the Cluster

We must to use software that are compatible with `linux-arm64` ARM architecture.

### Step 1 - Provision VM with Multipass or Vagrant

#### Using Multipass

1. Run the VM deploy script from your Mac terminal

    ```bash
    cd multipass
    ./deploy-vm.sh
    ```

2. Verify you can connect to all three (two if your Mac only has 8GB RAM) VMs:

    ```bash
    multipass shell kubemaster
    ```

    You should see a command prompt like `ubuntu@kubemaster:~$`

    Type the following to return to the Mac terminal

    ```bash
    exit
    ```

    Do this for `kubeworker01` and `kubeworker02` as well

    In the following instructions when it says "connect to" any of the VMs, it means use the `multipass shell` command as above.

#### Using Vagrant
1. Run and Deploy the ubuntu instances.
    ```bash
    cd vagrant
    vagrant up
    vagrant status
    ```

2. Open three Terminal because we setup 3 nodes, and type following commands for each terminal
   ```bash
    # Terminal 1
    vagrant ssh kubemaster

    # Terminal 2
    vagrant ssh kubenode01

    # Terminal 3
    vagrant ssh kubenode02
   ```
### Step 2 - Set up OS Prerequisites

Connect to each VM, this instruction is from [here](https://kubernetes.io/docs/setup/production-environment/container-runtimes/), and run the following command:

1. Execute the following commands in each VM terminal

    ```bash
    # This will instruct the server to load overlay and br_netfilter kernel module on startup, every time server startup those kernel module will loaded and will required by containerd
    cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
    overlay
    br_netfilter
   EOF

   # We need to loaded this module immediately, without restart the server
   sudo modprobe overlay
   sudo modprobe br_netfilter

   # Create file k8s.conf, this is needed for kubernetes networking
   cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
   net.bridge.bridge-nf-call-iptables  = 1
   net.bridge.bridge-nf-call-ip6tables = 1
   net.ipv4.ip_forward                 = 1
   EOF

   # Apply sysctl params without reboot
   sudo sysctl --system
    ```
  
### Step 3 - Set up Container Runtime (containerd)

Using the default version of `containerd` that is provided by `apt-get install` results in a cluster with crashlooping pods, so we install a version that works by downloading directly from their github site.

Connect to each VM, this instruction is from [here](https://github.com/containerd/containerd/blob/main/docs/getting-started.md), and run the following command:

1. Download and unzip the containerd application, you can see the list in [here.](https://github.com/containerd/containerd/releases)

    ```bash
    curl -LO https://github.com/containerd/containerd/releases/download/v1.7.2/containerd-1.7.2-linux-arm64.tar.gz
    sudo tar Czxvf /usr/local containerd-1.7.2-linux-arm64.tar.gz
    ```
1. Download and place the systemd unit file

    ```bash
    curl -LO https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
    sudo mkdir -p /usr/lib/systemd/system
    sudo mv containerd.service /usr/lib/systemd/system/
    ```

1. Create containerd configuration file

    ```bash
    sudo mkdir -p /etc/containerd/
    sudo containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
    ```

1. Enable [systemd CGroup](https://kubernetes.io/docs/setup/production-environment/container-runtimes/#containerd-systemd) driver

    ```bash
    sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml
    ```

1. Set containerd to auto-start at boot (enable it).

    ```bash
    sudo systemctl daemon-reload
    sudo systemctl enable --now containerd

    #Check the status of containerd
    sudo systemctl status containerd
    ```

### Step 4 - Install kubeadm, kubelet and kubectl

The instruction you can follow [here](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#installing-kubeadm-kubelet-and-kubectl). Connect to each VM in turn and perform the following steps

1. Update the apt package index and install packages needed to use the Kubernetes apt repository

    ```bash
    sudo apt-get update
    sudo apt-get install -y apt-transport-https ca-certificates curl
    ```

1.  Download the Google Cloud public signing key

    ```bash
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg
    ```

1.  Add the Kubernetes apt repository

    ```bash
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
    ```

1.  Update apt package index, install kubelet, kubeadm and kubectl, and pin their version:

    ```bash
    KUBE_VERSION=1.27.3
    sudo apt-get update
    sudo apt-get install -y kubelet=${KUBE_VERSION}-00 jq kubectl=${KUBE_VERSION}-00 kubeadm=${KUBE_VERSION}-00 runc kubernetes-cni=1.2.0-00
    sudo apt-mark hold kubelet kubeadm kubectl

    # Check if installed
    sudo dpkg -l | grep kube
    ```

1. Configure crictl to work with [containerd](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#installing-runtime)

    ```bash
    sudo crictl config runtime-endpoint unix:///var/run/containerd/containerd.sock
    ```
1. Before you initialize kubeadm, make sure you turn off the swap. [You MUST disable swap in order for the kubelet to work properly.](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#before-you-begin)
   
   Check the swap status
   ```bash
   sudo swapon --show
   ```
   or
   ```bash
    sudo free -h
   ```

   If swap exists you must disable the swap before initialization kubeadm.
   ```bash
    sudo swapoff -a
   ```

### Step 5 - Provisioning the Kubernetes Cluster

1. Configure the Control Plane

    1. Connect to the control plane node
    1. Determine the IP address of the control plane node. We will need it for the forthcoming `kubeadm init` command.

        ```bash
        dig +short kubemaster | grep -v 127
        ```

    1. Initialize [control plane](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/#initializing-your-control-plane-node).

        As per the lecture, we are going to use a pod CIDR of 10.244.0.0/16. Run the following command, replacing `<IP>` with the IP address you got from the previous step

        ```bash
        sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=<ip>
        ```

    1. Set up the kubeconfig file.

        ```bash
        mkdir ~/.kube
        sudo cp /etc/kubernetes/admin.conf ~/.kube/config
        sudo chown ubuntu:ubuntu ~/.kube/config
        chmod 600 ~/.kube/config
        ```

    1. Verify the cluster is contactable

        ```bash
        kubectl get pods -n kube-system
        ```

        You should see some output. Pods may not all be ready yet.

    1. Install Weave for cluster networking
       </br> For the concepts in [here](https://kubernetes.io/docs/concepts/cluster-administration/addons/)

        ```bash
        kubectl apply -f "https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s-1.11.yaml"
        ```

        It will take up to a minute for the weave pod to be ready

    2. Prepare the join command for the worker nodes

        ```bash
        kubeadm token create --print-join-command
        ```

        Copy the output of this. We will need to paste it on the worker(s)

2. Configure the worker nodes

    For each worker node

    1. Connect to the worker node
    2. Paste the join command you copied from the final step of configuring the control plane to the command prompt and run it. Put `sudo` on the command line first, then passte the join command after sudo so it looks like

        ```
        sudo kubeadm join 192.168.64.4:6443 --token whd8v4.EXAMPLE --discovery-token-ca-cert-hash sha256:9537c57af216775e26ffa7ad3e495-5EXAMPLE`
        ```

## Notes

### Delete VM on Multipass
1. Deleting the VMs

    ```
    ./delete-vm.sh
    ```

1. Stopping and restarting the VMs

    To stop the VMs, stop the workers first, then finally kubemaster

    ```bash
    multipass stop kubeworker01
    multipass stop kubeworker02
    multipass stop kubemaster
    ```

    To restart them, start the control plane first

    ```bash
    multipass start kubemaster
    # Wait 30 sec or so
    multipass start kubeworker01
    multipass start kubeworker02
    ```

1. To see the state of VMs, run

    ```bash
    multipass list
    ```

1.  Multipass allocates IP addresses from the Mac's DHCP server to assign to VMs. When the VMs are deleted, it does not release them. If you build and tear down this a few times, you will run out of addresses on the network used for this purpose. Reclaiming them is a manual operation. To do this, you must remove the spent addresses from the file `/var/db/dhcpd_leases` This file looks like this:

    ```json
    {
            name=kubemaster
            ip_address=192.168.64.22
            hw_address=1,52:54:0:eb:c4:7
            identifier=1,52:54:0:eb:c4:7
            lease=0x643f6f22
    }
    {
            name=kubeworker01
            ip_address=192.168.64.23
            hw_address=1,52:54:0:93:3d:91
            identifier=1,52:54:0:93:3d:91
            lease=0x643f6f20
    }
    ```

    Once you have deleted all your VMs, edit this file and remove all the blocks (including their surrounding `{ }`) related to kubemaster and kubeworker. In the above example you would delete everything you can see. Do this for all kubemsters and kubeworkers.

    ```
    sudo vi /var/db/dhcpd_leases
    ```

### Delete VM on Vagrant

```
vagrant destroy kubemaster kubenode01 kubenode02
```
