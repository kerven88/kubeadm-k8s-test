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


check_parm "请输入一个或者多个需要初始化的工作节点IP,IP之间以英文逗号隔开: " ${WORKER_IP} 
if [ $? -eq 1 ]; then
	read WORKER_IP
fi


ip_array=(${WORKER_IP//,/ })

echo """
cluster-info:
  需要初始化的工作节点:        ${ip_array[@]}
  注意!!!
  1.确定IP信息正确.
  2.确保k8sapi域名和私有仓库域名在工作节点正常解析.
  3.确保是以root用户在master-01上面执行这个脚本,且工作节点的osadmin账号拥有sudo权限.
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


JOIN_CMD=`kubeadm token create --print-join-command`

for ip in  ${ip_array[@]}; do
  scp node_base_setting.sh  osadmin@${ip}:/tmp/
  ssh osadmin@$ip "/bin/sudo /bin/rm -rf /usr/local/src/node_base_setting.sh /etc/kubernetes/*;/bin/sudo kubeadm reset -f;/bin/sudo cp /tmp/node_base_setting.sh  /usr/local/src/ && cd /usr/local/src/ && /bin/sudo /bin/bash node_base_setting.sh"
  ssh osadmin@${ip} "/bin/sudo ${JOIN_CMD}"
done
echo "worker  node create finished."


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
