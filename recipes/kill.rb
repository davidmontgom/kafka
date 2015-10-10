


bash "kill_kafka" do
  user "root"
  cwd "/var/"
  code <<-EOH
    sudo kill `sudo lsof -t -i:9999`
    touch #{Chef::Config[:file_cache_path]}/kafka_9999_kill.lock
  EOH
  action :run
  not_if {File.exists?("#{Chef::Config[:file_cache_path]}/kafka_9999_kill.lock")}
end