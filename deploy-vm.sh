#!/usr/bin/env bash
# When VMs are deleted, IPs remain allocated in dhcpdb
# IP reclaim: https://discourse.ubuntu.com/t/is-it-possible-to-either-specify-an-ip-address-on-launch-or-reset-the-next-ip-address-to-be-used/30316

set -euo pipefail

RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

NUM_WORKER_NODES=2
MEM_GB=$(( $(sysctl hw.memsize | cut -d ' ' -f 2) / 1073741824 ))
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )/scripts
VM_MEM_GB=2G # Set the default memory

if [ $MEM_GB -lt 8 ]
then
  echo -e "${RED}System RAM is ${MEM_GB}GB. This is insufficient to deploy a working cluster.${NC}"
  exit 1
fi

if [ $MEM_GB -lt 16 ]
then
  echo -e "${YELLOW}System RAM is ${MEM_GB}GB. Deploying only one worker node.${NC}"
  NUM_WORKER_NODES=1
  VM_MEM_GB=2G
  sleep 1
fi


workers=$(for n in $(seq 1 $NUM_WORKER_NODES) ; do echo -n "kubeworker0$n"; done)

# Check if node are running
if multipass list --format json | jq -r '.list[].name' | egrep 'kube(master|node01|node02)' > /dev/null
then
  echo -n -e $RED
  read -p "VMs are running. Delete and rebuild them (y/n)? " answer
  echo -n -e $NC
  [ "$answer" != 'y' ] && exit 1
fi

# Boot the nodes
for node in kubemaster $workers
do
  if multipass list --format json | jq -r '.list[].name' | grep "$node"
  then
    echo -e "${YELLOW}Deleting $node${NC}"
    multipass delete $node
    multipass purge
  fi

  echo -e "${BLUE}Launching ${node}${NC}"
  multipass launch --disk 5G --memory $VM_MEM_GB --cpus 2 --name $node jammy
  echo -e "${GREEN}$node booted!${NC}"
done

#Create hosts files
echo -e "${BLUE}Setting hostsnames${NC}"
hostentries=/tmp/hostentries

[ -f $hostentries ] && rm -f $hostentries

for node in kubemaster $workers
do
  ip=$(multipass info $node --format json | jq -r 'first( .info[] | .ipv4[0] )')
  echo "$ip $node" >> $hostentries
done

for node in kubemaster $workers
do
  multipass transfer $hostentries $node:/tmp/
  multipass transfer $SCRIPT_DIR/01-setup-hosts.sh $node:/tmp/
  multipass exec $node -- /tmp/01-setup-hosts.sh
done
echo -e "${GREEN}Done!${NC}"