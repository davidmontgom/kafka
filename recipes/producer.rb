server_type = node.name.split('-')[0]
slug = node.name.split('-')[1] 
datacenter = node.name.split('-')[2]
environment = node.name.split('-')[3]
location = node.name.split('-')[4]
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

if zookeeper_server[datacenter][environment][location].has_key?(cluster_slug)
  cluster_slug_zookeeper = cluster_slug
else
  cluster_slug_zookeeper = "nocluster"
end

if cluster_slug_zookeeper=="nocluster"
  subdomain = "zookeeper-#{slug}-#{datacenter}-#{environment}-#{location}"
else
  subdomain = "zookeeper-#{slug}-#{datacenter}-#{environment}-#{location}-#{cluster_slug_zookeeper}"
end

required_count = zookeeper_server[datacenter][environment][location][cluster_slug_zookeeper]['required_count']
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

easy_install_package "dnspython" do
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
    zookeeper_hosts.append("%s-#{full_domain}" % (i+1))
zk_host_list = []
for aname in zookeeper_hosts:
  try:
      data =  dns.resolver.query(aname, 'A')
      zk_host_list.append(data[0].to_text()+':2181')
  except:
      print 'ERROR, dns.resolver.NXDOMAIN',aname
zk_host_str = ','.join(zk_host_list)   
zk = zc.zk.ZooKeeper(zk_host_str) 

if "#{cluster_slug}"=="nocluster":
    node = '#{server_type}-#{slug}-#{datacenter}-#{node.chef_environment}-#{location}'
else:
    node = '#{server_type}-#{slug}-#{datacenter}-#{node.chef_environment}-#{location}-#{cluster_slug}'
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
          cmd = """> /var/kafka/config/producer.properties | echo '%s' | tee -a /var/kafka/config/producer.properties""" % conf
          stdin, stdout, stderr = ssh.exec_command(cmd)
          cmd = "sudo ufw allow from #{node[:ipaddress]}"
          stdin, stdout, stderr = ssh.exec_command(cmd)
          ssh.close()
          os.system("sudo ufw allow from %s" % ip_address)
os.system("> /var/kafka/config/producer.properties")
os.system("echo '%s' | tee -a /var/kafka/config/producer.properties" % conf)

PYCODE
  end
