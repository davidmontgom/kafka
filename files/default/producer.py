



    
kafka_servers = ['1','2']
t_list = []
for ip in kafka_servers:
    temp = '%s:9092' % ip
    t_list.append(temp)
broker_list = ','.join(t_list)
metadata = "metadata.broker.list=%s" % broker_list
print test