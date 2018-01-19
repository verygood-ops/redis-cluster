#!/usr/bin/env bash
TRIB="/home/ubuntu/redis-4.0.6/src/redis-trib.rb"

# exit if node already in formed cluster
[ $($TRIB check localhost:6379 | grep -c [M]) -ge 2 ] && exit 0

PRE_LOG="redis-ha:"
masters=""
MASTER=""
# join as slave by defaul
asSLAVE="--slave" 
# get locat IP
LOCAL_ADDR=$(ifconfig eth0 | grep -w inet | egrep -o "addr:([0-9]{1,3}[\.]){3}[0-9]{1,3}" | cut -d ':' -f2)
echo $PRE_LOG LOCAL_ADDR=$LOCAL_ADDR
# get IPs of all nodes
ADDRS="$(AWS_DEFAULT_REGION=us-west-2 aws ec2 describe-instances --query "Reservations[].Instances[].[InstanceId,PrivateIpAddress,Tags[?Key=='Name'].Value]" --output=text | grep -i -B1 redis | egrep -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}" | sort -V )" 
echo $PRE_LOG ADDRS=$ADDRS
# which node should be first master
FIRST="$(echo $ADDRS | cut -d ' ' -f1)"
echo $PRE_LOG FIRST=$FIRST

for addr in $ADDRS; do
  # find nodes already in cluster
  masters=$($TRIB check $addr:6379 | grep -c '[M]')
  # node with 3 or more masters attached will be node to connect as slave
  if [ $masters -ge 3 ]; then
    MASTER="$addr"
    asSLAVE="--slave"
  else 
    # if no 3 masters node found - connect to 2 masters node as master
    if [ $masters -eq 2 -a -z "$MASTER"]; then
      MASTER="$addr"
      asSLAVE=""
    fi
  fi
done

# if no cluster found 
if [ -z "$MASTER" ]; then
 # check if  this node should create cluster
 echo $PRE_LOG No cluster found. Checking if I should create one
 if [ "$LOCAL_ADDR" = "$FIRST" ]; then 
  echo $PRE_LOG Yes, I will be the first node in cluster
  # split existing nodes to future masters and slaves
  for addr in $ADDRS; do
    [ $(echo $NODES | wc -w) -le 2 ] && NODES="$NODES $addr:6379" || SLAVES="$SLAVES $addr:6379"
  done
  # check if there's enough nodes to create replicas
  if [ $(echo $ADDRS | wc -w) -le 5 ]; then
    echo $PRE_LOG Not enough nodes to init cluster with replicas
    REPLICAS=0 
    SLAVES=""
  else
    echo $PRE_LOG Found enough nodes to init cluster with replicas
    REPLICAS=1
  fi
  # create the cluster
  echo $PRE_LOG Lets create cluster
  $TRIB create --replicas $REPLICAS $NODES $SLAVES
  if [ -n $SLAVES -a $REPLICAS -eq 0 ]; then
    echo $PRE_LOG Lets also add other nodes found as replicas
    $TRIB add-node --slave $SLAVES $MASTER:6379
  fi  
 fi
# if some cluster found - join it
else 
  echo $PRE_LOG Joining to existing cluster
  $TRIB add-node $asSLAVE $LOCAL_ADDR:6379 $MASTER:6379
fi
