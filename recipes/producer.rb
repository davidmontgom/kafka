datacenter = node.name.split('-')[0]
server_type = node.name.split('-')[1]
location = node.name.split('-')[2]
  
data_bag("my_data_bag")
zk = data_bag_item("my_data_bag", "zk")
zk_hosts = zk[node.chef_environment][datacenter][location]["zookeeper_hosts"]

db = data_bag_item("my_data_bag", "my")
keypair=db[node.chef_environment][location]["ssh"]["keypair"]
username=db[node.chef_environment][location]["ssh"]["username"]



script "zookeeper_add_redis" do
    interpreter "python"
    user "root"
  code <<-PYCODE
import os
import zc.zk
import logging 
logging.basicConfig()
import paramiko
import time
username='#{username}'
zookeeper_hosts = '#{zk_hosts}'
zk_host_list = '#{zk_hosts}'.split(',')
for i in xrange(len(zk_host_list)):
    zk_host_list[i]=zk_host_list[i]+':2181' 
zk_host_str = ','.join(zk_host_list)
zk = zc.zk.ZooKeeper(zk_host_str) 
ip_address_list = zookeeper_hosts.split(',')
shard = open('/var/shard.txt').readlines()[0].strip()
node = '#{datacenter}-kafka-#{location}-#{node.chef_environment}-%s' % (shard)
path = '/%s/' % (node)
#Each kafka server
if zk.exists(path):
    addresses = zk.children(path)
    kafka_servers = list(set(addresses))
    kafka_servers.append('#{node[:ipaddress]}')
    kafka_servers = list(set(kafka_servers))
    t_list = []
    for ip in kafka_servers:
        temp = '%s:9092' % ip
        t_list.append(temp)
    broker_list = ','.join(t_list)
    metadata = "metadata.broker.list=%s" % broker_list
    conf = """
    %s
    producer.type=sync
    compression.codec=none
    serializer.class=kafka.serializer.DefaultEncoder
    """ % metadata
    for ip_address in kafka_servers:
        if ip_address != '#{node[:ipaddress]}':
          keypair_path = '/root/.ssh/#{keypair}'
          key = paramiko.RSAKey.from_private_key_file(keypair_path)
          ssh = paramiko.SSHClient()
          ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
          ssh.connect(ip_address, 22, username=username, pkey=key)
          cmd = "> /var/kafka/config/producer.properties"
          stdin, stdout, stderr = ssh.exec_command(cmd)
          cmd = "echo '%s' | tee -a /var/kafka/config/producer.properties" % conf
          stdin, stdout, stderr = ssh.exec_command(cmd)
          ssh.close()
          os.system("sudo ufw allow from %s" % ip_address)
os.system("> /var/kafka/config/producer.properties")
os.system("echo '%s' | tee -a /var/kafka/config/producer.properties" % conf)

PYCODE
  end
