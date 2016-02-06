import argparse
import os
import zc.zk
import logging 
import json
logging.basicConfig()
import paramiko
import dns.resolver
import subprocess
from zoo import *
from pprint import pprint

    
def iptables_remote(this_ip_address,ip_address_list,keypair,username,cmd_list=[]):
    
    if this_ip_address in ip_address_list:
        ip_address_list.remove(this_ip_address)
    
    for ip_address in ip_address_list:
       
        keypair_path = '/root/.ssh/%s' % keypair
        key = paramiko.RSAKey.from_private_key_file(keypair_path)
        ssh = paramiko.SSHClient()
        ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        ssh.connect(ip_address, 22, username=username, pkey=key)
        
        cmd = "iptables -C INPUT -s %s -j ACCEPT" % (this_ip_address)
        stdin, stdout, stderr = ssh.exec_command(cmd)
        error_list = stderr.readlines()
        if error_list:
            output = ' '.join(error_list)
            if output.find('iptables: Bad rule (does a matching rule exist in that chain?).')>=0: 
                cmd = "/sbin/iptables -A INPUT -s %s -j ACCEPT" % (this_ip_address)
                print cmd
                stdin, stdout, stderr = ssh.exec_command(cmd)
                cmd = "rm /var/chef/cache/unicast_hosts"
                stdin, stdout, stderr = ssh.exec_command(cmd)
        
        cmd = "iptables -C OUTPUT -d %s -j ACCEPT" % (this_ip_address)
        stdin, stdout, stderr = ssh.exec_command(cmd)
        error_list = stderr.readlines()
        if error_list:
            output = ' '.join(error_list)
            if output.find('iptables: Bad rule (does a matching rule exist in that chain?).')>=0:
                cmd = "/sbin/iptables -A OUTPUT -d %s -j ACCEPT" % (this_ip_address)
                print cmd
                stdin, stdout, stderr = ssh.exec_command(cmd)
                cmd = "/etc/init.d/iptables-persistent save" 
                stdin, stdout, stderr = ssh.exec_command(cmd)
        
        for cmd in cmd_list:
            stdin, stdout, stderr = ssh.exec_command(cmd)
            out = stdout.read()
            err = stderr.read()
        
        ssh.close()
       

def iptables_local(this_ip_address,ip_address_list):
    
    if this_ip_address in ip_address_list:
        ip_address_list.remove(this_ip_address)
    
    for ip_address in ip_address_list:     
        
        cmd = "iptables -C INPUT -s %s -j ACCEPT" % (ip_address)
        p = subprocess.Popen(cmd, shell=True,stderr=subprocess.STDOUT,stdout=subprocess.PIPE,executable="/bin/bash")
        out = p.stdout.readline().strip()
        if out.find('iptables: Bad rule (does a matching rule exist in that chain?).')>=0:
            cmd = "/sbin/iptables -A INPUT -s %s -j ACCEPT" % (ip_address)
            os.system(cmd)
        
        cmd = "iptables -C OUTPUT -d %s -j ACCEPT" % (ip_address)
        p = subprocess.Popen(cmd, shell=True,stderr=subprocess.STDOUT,stdout=subprocess.PIPE,executable="/bin/bash")
        out = p.stdout.readline().strip()
        if out.find('iptables: Bad rule (does a matching rule exist in that chain?).')>=0:
            cmd = "/sbin/iptables -A OUTPUT -d  %s -j ACCEPT" % (ip_address)
            os.system(cmd)
    
def kafka(args):
    
    zoo = zookeeper(args)
    zk = zoo.get_conn()
    path = zoo.get_path()
    
    ip_address = args.ip_address
    username = args.username
    keypair = args.keypair
     
    kafka_hosts = [ip_address]
    
    t_list = [ip_address+":9092"]
    
    if zk.exists(path):
        addresses = zk.children(path)
        ip_address_list = list(set(addresses))
        kafka_hosts = kafka_hosts + ip_address_list
        ip_address_list = list(set(kafka_hosts))
        for ip in ip_address_list:
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
        
        cmd_list = ["> /var/kafka/config/producer.properties","echo '%s' | tee -a /var/kafka/config/producer.properties" % conf]
        iptables_remote(ip_address,ip_address_list,keypair,username,cmd_list=cmd_list)
        iptables_local(ip_address,ip_address_list)
    else: 
        broker_list = ','.join(t_list)
        metadata = "metadata.broker.list=%s" % broker_list
        conf = """
%s
producer.type=sync
compression.codec=none
serializer.class=kafka.serializer.DefaultEncoder
            """ % metadata
        os.system("> /var/kafka/config/producer.properties")
        os.system("echo '%s' | tee -a /var/kafka/config/producer.properties" % conf)
    
    f.close()
    if zk:
        zoo.close()





if __name__ == "__main__":
    
    """
    python test.py --server_type elasticsearch --username root --ip_address 192.34.59.12 --zk_count 1 \
           --zk_hostname zookeeper-forex-do-development-ny.forexhui.com \
           --datacenter do --environment development --location ny --slug forex --keypair  id_rsa_forex_do
    
    
    """
    
    parser = argparse.ArgumentParser(description='Node')
    
    
    parser.add_argument('--server_type', action="store", default=None, help="server_type")
    parser.add_argument('--username', action="store", default=None, help="username")
    parser.add_argument('--ip_address', action="store", default=None, help="ipaddress")
    parser.add_argument('--zk_count', action="store", default=None, help="zk_count")
    parser.add_argument('--zk_hostname', action="store", default=None, help="zk_hostname")
    parser.add_argument('--datacenter', action="store", default=None, help="datacenter")
    parser.add_argument('--environment', action="store", default=None, help="environment")
    parser.add_argument('--location', action="store", default=None, help="location")
    parser.add_argument('--slug', action="store", default=None, help="slug")
    parser.add_argument('--cluster_slug', action="store", default='nocluster', help="cluster_slug")
    parser.add_argument('--shard', action="store", default=None, help="shard")
    parser.add_argument('--keypair', action="store", default=None, help="keypair")
    
    args = parser.parse_args()
    fn = os.path.realpath(__file__)
    
    f = open('/tmp/%s_zk.sh' % fn.split('/')[-1].replace('.py',''),'w')
    temp = '/usr/bin/python %s ' % fn
    f.write(temp)
    for arg in vars(args):
        line =  '--%s %s ' % (arg, getattr(args, arg))
        f.write(line)
    f.close()

    kafka(args)













