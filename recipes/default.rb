data_bag("my_data_bag")
db = data_bag_item("my_data_bag", "my")

datacenter = node.name.split('-')[0]
server_type = node.name.split('-')[1]
location = node.name.split('-')[2]


#http://blog.liveramp.com/2013/04/08/kafka-0-8-producer-performance-2/
#/logs/kafka-request.log.2014-11-13-16
easy_install_package "boto" do
  action :install
end

execute "restart_supervisorctl_kafka_server" do
  command "sudo supervisorctl restart kafka_server:"
  action :nothing
end


bash "install_kafka" do
  user "root"
  cwd "/var/"
  code <<-EOH
    git clone https://git-wip-us.apache.org/repos/asf/kafka.git
    cd kafka
    git checkout -b 0.8 remotes/origin/0.8
    ./sbt "++2.9.2 update"
    ./sbt "++2.9.2 package"
    ./sbt "++2.9.2 assembly-package-dependency"
    #http://stackoverflow.com/questions/14735363/trying-to-build-and-run-apache-kafka-0-8-against-scala-2-9-2-without-success
    sed -i "s/2.8.0/2.9.2/g" bin/kafka-run-class.sh
    #Below is wrong - need to be at the top of file for KAFKA_JMX_OPTS
    #echo 'KAFKA_JMX_OPTS="-Dcom.sun.management.jmxremote.port=9999 -Dcom.sun.management.jmxremote=true -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false"' | tee -a /var/kafka/bin/kafka-run-class.sh 
    #echo 'export JMX_PORT=${JMX_PORT:-9999}' | tee -a /var/kafka/bin/kafka-server-start.sh
    touch #{Chef::Config[:file_cache_path]}/kafka_lock
  EOH
  action :run
  not_if {File.exists?("#{Chef::Config[:file_cache_path]}/kafka_lock")}
end


if datacenter !="local"
  
AWS_ACCESS_KEY_ID = db[node.chef_environment]['aws']['AWS_ACCESS_KEY_ID']
AWS_SECRET_ACCESS_KEY = db[node.chef_environment]['aws']['AWS_SECRET_ACCESS_KEY']
zone_id = db[node.chef_environment]['aws']['route53']['zone_id']
domain = db[node.chef_environment]['aws']['route53']['domain']

script "zookeeper_myid" do
  interpreter "python"
  user "root"
  cwd "/root"
code <<-PYCODE
import json
import os
from boto.route53.connection import Route53Connection
from boto.route53.record import ResourceRecordSets
from boto.route53.record import Record
import hashlib
conn = Route53Connection('#{AWS_ACCESS_KEY_ID}', '#{AWS_SECRET_ACCESS_KEY}')
records = conn.get_all_rrsets('#{zone_id}')
host_list = {}
prefix={}
root = None
for record in records:
  if record.name.find('zk')>=0 and record.name.find('#{location}')>=0 and record.name.find('#{node.chef_environment}')>=0:
    if record.resource_records[0]!='#{node[:ipaddress]}':
      host_list[record.name[:-1]+":2181"]=record.resource_records[0]
      p = record.name.split('.')[0]
      prefix[p]=1
      root = record.name[:-1]
with open('#{Chef::Config[:file_cache_path]}/zookeeper_hosts.json', 'w') as fp:
  json.dump(host_list, fp)
fnl=["#{Chef::Config[:file_cache_path]}/zookeeper_hosts.json"]
fh = [(fname, hashlib.md5(open("#{Chef::Config[:file_cache_path]}/zookeeper_hosts.json", 'rb').read()).hexdigest()) for fname in fnl][0][1]
hash_file = '#{Chef::Config[:file_cache_path]}/fh_%s' % fh
if not os.path.isfile(hash_file):
  try:
    os.system('rm #{Chef::Config[:file_cache_path]}/fh_*')
  except:
    pass
  os.system('touch %s' % hash_file)
  f = open('/var/chef/cache/zookeeper_hosts','w')
  tmp = ','.join(host_list.keys())
  f.write(tmp)
  f.close()
PYCODE
end
  if File.exists?("#{Chef::Config[:file_cache_path]}/zookeeper_hosts")
    zookeeper_hosts = File.read("#{Chef::Config[:file_cache_path]}/zookeeper_hosts")
  end
  
  #export KAFKA_HEAP_OPTS="-Xmx256M -Xms128M"
  #-Dcom.sun.management.jmxremote.port=9999 -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false
  #echo 'KAFKA_JMX_OPTS="-Dcom.sun.management.jmxremote.port=9999 -Dcom.sun.management.jmxremote=true -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false"' | tee -a /var/kafka/bin/kafka-run-class.sh 
  #echo 'export JMX_PORT=${JMX_PORT:-9999}' | tee -a /var/kafka/bin/kafka-server-start.sh
  heap="-Xmx256M -Xms128M"
  template "/var/kafka/bin/kafka-server-start.sh" do
    path "/var/kafka/bin/kafka-server-start.sh"
    source "kafka-server-start.sh.erb"
    owner "root"
    group "root"
    mode "0755"
    variables({
      :heap => heap
    })
    notifies :run, "execute[restart_supervisorctl_kafka_server]"
  end
  
  template "/var/kafka/bin/kafka-run-class.sh" do
    path "/var/kafka/bin/kafka-run-class.sh"
    source "kafka-run-class.sh.erb"
    owner "root"
    group "root"
    mode "0755"
    notifies :run, "execute[restart_supervisorctl_kafka_server]"
  end
  

  bash "broker_id" do
    user "root"
    cwd "/var/"
    code <<-EOH
      touch #{Chef::Config[:file_cache_path]}/broker_id
      echo $RANDOM | tee -a #{Chef::Config[:file_cache_path]}/broker_id
    EOH
    action :run
    not_if {File.exists?("#{Chef::Config[:file_cache_path]}/broker_id")}
  end
  
  if File.exists?("#{Chef::Config[:file_cache_path]}/broker_id")
    broker_id = File.read("#{Chef::Config[:file_cache_path]}/broker_id")
  end
  
  replicas = 1
  paritions = 2
  ipaddress = node[:ipaddress]
  template "/var/kafka/config/server.properties" do
    path "/var/kafka/config/server.properties"
    source "server.properties.erb"
    owner "root"
    group "root"
    mode "0644"
    variables lazy {{:broker_id => File.read("#{Chef::Config[:file_cache_path]}/broker_id"), 
    :zookeeper => File.read("#{Chef::Config[:file_cache_path]}/zookeeper_hosts"), 
    :ipaddress => ipaddress,
    :replicas => replicas, 
    :paritions => paritions}}
    notifies :run, "execute[restart_supervisorctl_kafka_server]"
  end

end


service "supervisord"
template "/etc/supervisor/conf.d/kafka.conf" do
  path "/etc/supervisor/conf.d/kafka.conf"
  source "supervisord.kafka.conf.erb"
  owner "root"
  group "root"
  mode "0755"
  #notifies :restart, resources(:service => "supervisord")
  notifies :run, "execute[restart_supervisorctl_kafka_server]"
end



cron "kafka_delete_logs" do
  action :create
  minute '0'
  hour '0'
  weekday '1'
  command "rm /logs/kafka-request.log.*"
end







#INFO Will not load MX4J, mx4j-tools.jar is not in the classpath (kafka.utils.Mx4jLoader$)
#supervisrod
#9092
#https://cwiki.apache.org/confluence/display/KAFKA/Kafka+0.8+Quick+Start
#bin/kafka-server-start.sh config/server1.properties