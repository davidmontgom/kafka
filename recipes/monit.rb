

service "monit"
template "/etc/monit/conf.d/kafka.conf" do
  path "/etc/monit/conf.d/kafka.conf"
  source "monit.kafka.conf.erb"
  owner "root"
  group "root"
  mode "0755"
  #variables :role_list => role_list
  notifies :restart, resources(:service => "monit")
end