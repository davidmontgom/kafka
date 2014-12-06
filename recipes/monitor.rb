
=begin
https://github.com/quantifind/KafkaOffsetMonitor
https://github.com/quantifind/KafkaOffsetMonitor/releases/download/v0.2.0/KafkaOffsetMonitor-assembly-0.2.0.jar
https://github.com/quantifind/KafkaOffsetMonitor/releases/latest


https://github.com/claudemamo/kafka-web-console
=end





bash "install_kafka_monitor" do
  user "root"
  cwd "/var/"
  code <<-EOH
    wget https://github.com/quantifind/KafkaOffsetMonitor/releases/download/v0.2.0/KafkaOffsetMonitor-assembly-0.2.0.jar
    java -cp KafkaOffsetMonitor-assembly-0.2.0.jar com.quantifind.kafka.offsetapp.OffsetGetterWeb --zk 192.241.233.107 --port 8081 --refresh 10.seconds --retain 2.days
  EOH
  action :run
  not_if {"/var/KafkaOffsetMonitor-assembly-0.2.0.jar")}
end
