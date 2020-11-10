#/bin/bash

function check_parm()
{
  if [ "${2}" == "" ]; then
    echo -n "${1}"
    return 1
  else
    return 0
  fi
}

if [ -f ./cluster-info ]; then
	source ./cluster-info 
fi

check_parm "Enter the IP address of master-01: " ${CP0_IP} 
if [ $? -eq 1 ]; then
	read CP0_IP
fi
check_parm "Enter the IP address of master-02: " ${CP1_IP}
if [ $? -eq 1 ]; then
	read CP1_IP
fi
check_parm "Enter the IP address of master-03: " ${CP2_IP}
if [ $? -eq 1 ]; then
	read CP2_IP
fi
check_parm "Enter the VIP: " ${VIP}
if [ $? -eq 1 ]; then
	read VIP
fi
check_parm "API_SERVER_NAME: " ${API_SERVER_NAME}
if [ $? -eq 1 ]; then
	read API_SERVER_NAME
fi
check_parm "Enter the Net Interface: " ${NET_IF}
if [ $? -eq 1 ]; then
	read NET_IF
fi
check_parm "Enter the cluster CIDR: " ${CIDR}
if [ $? -eq 1 ]; then
	read CIDR
fi

echo """
cluster-info:
  master-01:        ${CP0_IP}
  master-02:        ${CP1_IP}
  master-02:        ${CP2_IP}
  k8sapi负载均衡VIP:${VIP} (该IP会在三台master之间漂移,设置一个和master同网段未使用的IP即可,脚本会自动初始化)
  k8sapi域名:       ${API_SERVER_NAME}
  机器主网卡名称:   ${NET_IF}
  k8s内网网段:      ${CIDR}
  注意!!!
  1.确定以上信息正确.
  2.确保k8sapi域名和私有仓库域名正常解析.
  3.确保是以root用户在master-01上面执行这个脚本,且所有节点的osadmin账号拥有sudo权限.
"""
echo -n 'Please print "yes" to continue or "no" to cancel: '
read AGREE
while [ "${AGREE}" != "yes" ]; do
	if [ "${AGREE}" == "no" ]; then
		exit 0;
	else
		echo -n 'Please print "yes" to continue or "no" to cancel: '
		read AGREE
	fi
done
/usr/bin/which dig 
if [ $? = "1" ];then
yum install bind-utils -y
fi

if [ "`/bin/dig  ${API_SERVER_NAME} +short`" != "${VIP}" ];then
echo "请先把k8sapi域名解析到VIP上面"
exit 1
else
echo "k8sapi域名解析正常"
fi

num=`/sbin/ifconfig |grep -Po "(\d+)(\.\d+){3}"| grep -v ".255$" |grep -E "10.201|172." |wc -l`
if [ $num != "0" ];then
registry_name='registry.test.sui.internal/test'
registry_host='registry.test.sui.internal'
else
registry_name='registry.feidee.org/library'
registry_host='registry.feidee.org'
fi

if [ "`/bin/dig  ${registry_host} +short`" = "" ];then
echo "请先解析镜像私有仓库${registry_host}域名"
exit 1
else
echo "镜像私有仓库域名解析正常"
fi


mkdir -p ~/ikube/tls

sed \
-e "s/K8SHA_IP1/${CP0_IP}/g" \
-e "s/K8SHA_IP2/${CP1_IP}/g" \
-e "s/K8SHA_IP3/${CP2_IP}/g" \
nginx-lb/nginx-lb.conf.tpl > nginx-lb/nginx-lb.conf

ssh-keygen -t rsa -P '' -f /root/.ssh/id_rsa
cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys

IPS=(${CP0_IP} ${CP1_IP} ${CP2_IP})

for index in 0 1 2; do
  ip=${IPS[${index}]}
  ssh-copy-id osadmin@${ip}
done

for index in 0 1 2; do
  ip=${IPS[${index}]}
  rsync -azvh --delete nginx-lb osadmin@${ip}:/tmp/
  ssh osadmin@${ip} "
    /bin/sudo /bin/mv -f  /tmp/nginx-lb /usr/local/
    /bin/sudo /usr/local/nginx-lb/docker-compose -f  /usr/local/nginx-lb/docker-compose.yaml  up -d"
done

for index in 0 1 2; do
  ip=${IPS[${index}]}
  scp keepalived.tar.gz  osadmin@${ip}:/tmp/
  ssh osadmin@${ip} "
    /bin/sudo /bin/mv -f /tmp/keepalived.tar.gz /usr/local/src/ && cd /usr/local/src/ && /bin/sudo /bin/tar -zxvf keepalived.tar.gz && /bin/sudo /bin/bash keepalived.sh"
done

for index in 0 1 2; do
  ip=${IPS[${index}]}
  scp master_base_setting.sh  osadmin@${ip}:/tmp/
  ssh osadmin@${ip} "
    /bin/sudo /bin/mv -f /tmp/master_base_setting.sh /usr/local/src/ && cd /usr/local/src/ && /bin/sudo /bin/bash master_base_setting.sh"
done

PRIORITY=(100 50 30)
STATE=("MASTER" "BACKUP" "BACKUP")
HEALTH_CHECK=""
for index in 0 1 2; do
  HEALTH_CHECK=${HEALTH_CHECK}"""
    real_server ${IPS[$index]} 6443 {
        weight 1
        SSL_GET {
            url {
              path /healthz
              status_code 200
            }
            connect_timeout 3
            nb_get_retry 3
            delay_before_retry 3
        }
    }
"""
done

for index in 0 1 2; do
  ip=${IPS[${index}]}
  echo """
global_defs {
   router_id LVS_DEVEL
}

vrrp_instance VI_1 {
    state ${STATE[${index}]}
    interface ${NET_IF}
    virtual_router_id 80
    priority ${PRIORITY[${index}]}
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass just0kk
    }
    virtual_ipaddress {
        ${VIP}
    }
}

virtual_server ${VIP} 6443 {
    delay_loop 6
    lb_algo loadbalance
    lb_kind DR
    nat_mask 255.255.255.0
    persistence_timeout 0
    protocol TCP

${HEALTH_CHECK}
}
""" > ~/ikube/keepalived-${index}.conf
  scp ~/ikube/keepalived-${index}.conf osadmin@${ip}:/tmp/keepalived.conf
  #scp ~/ikube/keepalived-${index}.conf osadmin@${ip}:/etc/keepalived/keepalived.conf
  ssh osadmin@${ip} "
    /bin/sudo /bin/mv -f /tmp/keepalived.conf /etc/keepalived/keepalived.conf
    /bin/sudo systemctl stop keepalived
    /bin/sudo systemctl enable keepalived
    /bin/sudo systemctl start keepalived
    /bin/sudo kubeadm reset -f
    /bin/sudo rm -rf /etc/kubernetes/pki/"
done

sleep 5
echo """
apiVersion: kubeadm.k8s.io/v1beta1
kind: ClusterConfiguration
kubernetesVersion: v1.13.4
controlPlaneEndpoint: "${API_SERVER_NAME}:16443"
apiServer:
  certSANs:
  - ${CP0_IP}
  - ${CP1_IP}
  - ${CP2_IP}
  - ${VIP}
  - ${API_SERVER_NAME}
networking:
  # This CIDR is a Calico default. Substitute or remove for your CNI provider.
  podSubnet: ${CIDR}
---
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
mode: ipvs
""" > /etc/kubernetes/kubeadm-config.yaml

kubeadm init --config /etc/kubernetes/kubeadm-config.yaml
mkdir -p $HOME/.kube
cp -f /etc/kubernetes/admin.conf ${HOME}/.kube/config


kubectl apply -f calico/rbac.yaml
cat calico/calico.yaml | sed "s!8.8.8.8!${CP0_IP}!g" | sed "s!10.244.0.0/16!${CIDR}!g" |sed "s!quay.io/calico!${registry_name}!g"| kubectl apply -f -

JOIN_CMD=`kubeadm token create --print-join-command`

for index in 1 2; do
  ip=${IPS[${index}]}
  ssh osadmin@$ip "/bin/sudo mkdir -p /etc/kubernetes/pki/etcd; /bin/sudo mkdir -p /root/.kube/ ;/bin/sudo rm -rf  /root/.kube/config;/bin/sudo chmod 777 -R  /etc/kubernetes"
  scp /etc/kubernetes/pki/ca.crt osadmin@$ip:/etc/kubernetes/pki/ca.crt
  scp /etc/kubernetes/pki/ca.key osadmin@$ip:/etc/kubernetes/pki/ca.key
  scp /etc/kubernetes/pki/sa.key osadmin@$ip:/etc/kubernetes/pki/sa.key
  scp /etc/kubernetes/pki/sa.pub osadmin@$ip:/etc/kubernetes/pki/sa.pub
  scp /etc/kubernetes/pki/front-proxy-ca.crt osadmin@$ip:/etc/kubernetes/pki/front-proxy-ca.crt
  scp /etc/kubernetes/pki/front-proxy-ca.key osadmin@$ip:/etc/kubernetes/pki/front-proxy-ca.key
  scp /etc/kubernetes/pki/etcd/ca.crt osadmin@$ip:/etc/kubernetes/pki/etcd/ca.crt
  scp /etc/kubernetes/pki/etcd/ca.key osadmin@$ip:/etc/kubernetes/pki/etcd/ca.key
  scp /etc/kubernetes/admin.conf osadmin@$ip:/etc/kubernetes/admin.conf
  #ssh osadmin@$ip "sudo sed -i 's/${CP0_IP}/${ip}/' /etc/kubernetes/admin.conf"
  ssh osadmin@$ip "/bin/sudo cp /etc/kubernetes/admin.conf /root/.kube/config"
  ssh osadmin@${ip} "/bin/sudo ${JOIN_CMD} --experimental-control-plane"
done

echo "Cluster create finished."


echo "Plugin install finished."
echo "Waiting for all pods into 'Running' status. You can press 'Ctrl + c' to terminate this waiting any time you like."
POD_UNREADY=`kubectl get pods -n kube-system 2>&1|awk '{print $3}'|grep -vE 'Running|STATUS'`
NODE_UNREADY=`kubectl get nodes 2>&1|awk '{print $2}'|grep 'NotReady'`
while [ "${POD_UNREADY}" != "" -o "${NODE_UNREADY}" != "" ]; do
  sleep 1
  POD_UNREADY=`kubectl get pods -n kube-system 2>&1|awk '{print $3}'|grep -vE 'Running|STATUS'`
  NODE_UNREADY=`kubectl get nodes 2>&1|awk '{print $2}'|grep 'NotReady'`
done

echo

kubectl get cs
kubectl get nodes
kubectl get pods -n kube-system

echo """
join command:
  `kubeadm token create --print-join-command`"""
