datacenter = node.name.split('-')[0]
server_type = node.name.split('-')[1]
location = node.name.split('-')[2]


data_bag("my_data_bag")
db = data_bag_item("my_data_bag", "my")
monitor_server = db[node.environment][location]['monitor']['ip_address']
service "jmxtrans"

=begin
  
http://www.der-maschinenstuermer.de/2014/06/16/jmx-metrics-for-apache-kafka-0-8-1-jmxtrans-chef-template-for-kafka/
https://kafka.apache.org/08/ops.html  - Use to add additional metrics to kafka
=end

template "/var/lib/jmxtrans/kafka.json" do
  path "/var/lib/jmxtrans/kafka.json"
  source "jmxtrans.kafka.json.erb"
  owner "root"
  group "root"
  mode "0755"
  variables({
    :monitor_host => "#{monitor_server}"
  })
  notifies :restart, resources(:service => "jmxtrans")
end
