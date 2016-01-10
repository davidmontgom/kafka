datacenter = node.name.split('-')[0]
environment = node.name.split('-')[1]
location = node.name.split('-')[2]
server_type = node.name.split('-')[3]
slug = node.name.split('-')[4] 
cluster_slug = File.read("/var/cluster_slug.txt")
cluster_slug = cluster_slug.gsub(/\n/, "") 
cluster_index = File.read("/var/cluster_index.txt")
cluster_index = cluster_slug.gsub(/\n/, "") 

data_bag("meta_data_bag")
aws = data_bag_item("meta_data_bag", "aws")
domain = aws[node.chef_environment]["route53"]["domain"]
zone_id = aws[node.chef_environment]["route53"]["zone_id"]
AWS_ACCESS_KEY_ID = aws[node.chef_environment]['AWS_ACCESS_KEY_ID']
AWS_SECRET_ACCESS_KEY = aws[node.chef_environment]['AWS_SECRET_ACCESS_KEY']


data_bag("server_data_bag")
zookeeper_server = data_bag_item("server_data_bag", "zookeeper")
required_count = zookeeper_server[datacenter][environment][location][cluster_slug]['required_count']
if cluster_slug=="nocluster"
  subdomain = "zookeeper-#{datacenter}-#{environment}-#{location}-#{slug}"
else
  subdomain = "#{cluster_slug}-zookeeper-#{datacenter}-#{environment}-#{location}-#{slug}"
end
full_domain = "#{subdomain}.#{domain}"

if datacenter!='aws'
  dc_cloud = data_bag_item("meta_data_bag", "#{datacenter}")
  keypair = dc_cloud[node.chef_environment]["keypair"]
  username = dc_cloud["username"]
end

easy_install_package "zc.zk" do
  action :install
end
easy_install_package "paramiko" do
  action :install
end

script "zookeeper_kafka" do
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
zookeeper_hosts = []
for i in xrange(int(#{required_count})):
    zookeeper_hosts.append("%s-#{full_domain}:2181" % (i+1))
zk_host_str = ','.join(zookeeper_hosts)   
zk = zc.zk.ZooKeeper(zk_host_str) 

if "#{cluster_slug}"=="nocluster":
    node = '#{datacenter}-#{node.chef_environment}-#{location}-#{server_type}-#{slug}'
else:
    node = '#{datacenter}-#{node.chef_environment}-#{location}-#{server_type}-#{slug}-#{cluster_slug}'
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
          cmd = "echo '%s' | tee -a /var/kafka/config/producer.properties" % conf.strip()
          stdin, stdout, stderr = ssh.exec_command(cmd)
          ssh.close()
          os.system("sudo ufw allow from %s" % ip_address)
os.system("> /var/kafka/config/producer.properties")
os.system("echo '%s' | tee -a /var/kafka/config/producer.properties" % conf)

PYCODE
  end
