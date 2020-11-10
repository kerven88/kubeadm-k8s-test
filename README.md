``` shell
#下载安装脚本
#git clone http://git.sui.work/ops/kubeadm-k8s.git

# 编辑集群信息文件
# cat ./cluster-info
CP0_IP=10.201.3.221               #master-01 IP
CP1_IP=10.201.3.222              #master-02 IP 
CP2_IP=10.201.3.223              #master-03 IP
VIP=10.201.3.224                 #k8sapi负载均衡VIP,该IP会在三台master之间漂移,设置一个和master同网段未使用的IP即可,脚本会自动初始化
API_SERVER_NAME=k8sapi.feidee.cn #k8sapi域名
NET_IF=eth0                      #机器主网卡名称
CIDR=10.244.0.0/16               #k8s内网网段

#执行集群安装脚本,安装过程需要交互输入osadmin密码
# /bin/sudo /bin/bash init_k8s_master.sh

#增加工作节点到集群,安装过程需要交互输入osadmin密码
# /bin/sudo /bin/bash init_k8s_node.sh
```
