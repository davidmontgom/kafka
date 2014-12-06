

bash "install_snappy" do
  user "root"
  cwd "#{Chef::Config[:file_cache_path]}"
  code <<-EOH
    wget https://snappy.googlecode.com/files/snappy-1.1.1.tar.gz
    tar -xvf snappy-1.1.1.tar.gz
    cd snappy-1.1.1
    ./configure
    make
    make install
    pip install python-snappy
    touch #{Chef::Config[:file_cache_path]}/snappy.lock
  EOH
  action :run
  not_if {File.exists?("#{Chef::Config[:file_cache_path]}/snappy.lock")}
end