# here are the commands I use to demo some YugabyteDB features on my laptop

# start Docker deamon

cd /home/ybdemo/docker/yb-lab
sh gen-yb-docker-compose.sh
cygstart http://localhost:7000

# show that connections are distributed
docker logs yb-lab-yb-demo-connect-1 \

grep -i datasource client/hikari.properties \

timeout 15 docker logs -f yb-lab-yb-demo-connect-1 \

# check all logs (connections, reads, writes)
timeout 15 docker-compose logs -tf \

# read/write operations on tservers
cygstart http://localhost:7000/tablet-servers \

## check tablet followers and leaders

cygstart http://localhost:7000/table?id=000030af000030008000000000004005 \

docker stop yb-tserver-1 \
&

timeout 15 docker logs -f yb-lab-yb-demo-connect-1 \

cygstart http://localhost:7000/table?id=000030af000030008000000000004005 \

cygstart http://localhost:7000/tablet-servers \

# start again
docker start yb-tserver-1 \

cygstart http://localhost:7000/tablet-servers \

cygstart http://localhost:7000/table?id=000030af000030008000000000004005 \

curl -s http://localhost:7000/logs?raw | grep --color=auto -iE "(cluster_balance|async_rpc_tasks|Leader Stepdown|Moving leader)" \

## scale up

docker-compose up -d --scale yb-tserver-n=3\

cygstart http://localhost:7000/tablet-servers \

curl -s http://localhost:7000/logs?raw | grep --color=auto -iE "(cluster_balance|async_rpc_tasks|Leader Stepdown|Moving leader)" \

# scale down

for i in {1..3} ; do docker exec -i yb-lab-yb-tserver-n-${i} bash <<< "/home/yugabyte/bin/yb-admin --master_addresses $(echo yb-master-{0..2}:7100|tr ' ' ,) change_blacklist ADD "'$(hostname):9100' ; done \

# wait for re-balancing
until docker exec -it yb-master-0 /home/yugabyte/bin/yb-admin --master_addresses $(echo yb-master-{0..2}:7100|tr ' ' ,) get_load_move_completion | tee /dev/stderr | grep --color=auto "complete = 100" ; do sleep 1 ; done

# stop them:
for i in {1..3} ; do docker stop yb-lab-yb-tserver-n-$i ; done

# clear the blacklist
for i in yb-lab_yb-tserver-n-{1..3} ; do docker exec -i yb-master-0 /home/yugabyte/bin/yb-admin --master_addresses $(echo yb-master-{0..2}:7100|tr ' ' ,) change_blacklist REMOVE $i ; done

cygstart http://localhost:7000/tablet-servers \

# force master re-election
for i in yb-master-{0..2} ; do docker restart $i -t 5 ; sleep 1 ; done




################################################ done ##########################

## Connect with psql

you can go to any node with something like `docker exec -it yb-lab_yb-demo_1 bash` and use `ysqlsh` like you would use `psql`. 

```
docker exec -it yb-tserver-0 ysqlsh -h yb-tserver-0
```

## Inspect the performance metrics

the `ybwr.sql` script collects the metrics from the tserver json endpoints, stores them, and displays a report every 10 seconds.
if the yb-lab_yb-demo-metrics service is not started you can run:
```
docker exec -it yb-lab_yb-demo-connect_1 bash client/ybdemo.sh ybwr
```

The most important metrics to identify any hotspots are `rows_inserted` for writes (those are key-value subdocuments, not SQL rows) and `rocksdb_number_db_seek`,`rocksdb_number_db_next` for reads and writes. The "%table" column shows the distribution of the per-tablet ones per the total for the table.

## Test JDBC Smart Driver

In a yb-lab_yb-demo container you can also test when client connects to a specic zone by changing `dataSource.url` in `client/hikari.properties` to

```
jdbc:yugabytedb://yb-tserver-0:5433/yugabyte?user=yugabyte&password=yugabyte&loggerLevel=INFO&load-balance=true&topology-keys=cloud1.region1.zone1,cloud1.region1.zone2
```

and restart a yb-demo server, or run:

```
docker start   yb-lab-yb-demo-connect-1
docker exec -i yb-lab-yb-demo-connect-1 bash -c "
cat > hikari.properties <<INI
dataSource.url=jdbc:yugabytedb://yb-tserver-0:5433/yugabyte?user=yugabyte&password=yugabyte&loggerLevel=INFO&load-balance=true&topology-keys=cloud1.region1.zone1,cloud1.region1.zone2
INI
grep -v ^dataSource.url client/hikari.properties >> hikari.properties
java -jar client/YBDemo.jar <<SQL
execute ybdemo(1000)
SQL
"

```

## Test follower reads

This can used the `docker-compose.yaml` generated by `sh gen-yb-docker-compose.sh rr` that creates some read replicas and starting no workload.
You can start only the database with:
```
docker-compose down
docker-compose up -d
docker-compose kill yb-demo-{read,write,connect}
docker-compose start yb-demo-init
```

This connects to one server and reads all rows in a loop:
```
docker exec -i yb-tserver-7 bash -c 'ysqlsh -h $(hostname)' <<'SQL'
\timing on
select count(*),current_setting('listen_addresses') from demo where id<=1000;
\watch 0.001
SQL
```
The console should show reads distributed on all servers, because the read goes to the LEADER tablet.

Now, the same with a follower read session:
```
docker exec -i yb-tserver-7 bash -c 'ysqlsh -h $(hostname)' <<'SQL'
set default_transaction_read_only = on;
set yb_read_from_followers=on;
set yb_follower_read_staleness_ms=2000;
\timing on
select count(*),current_setting('listen_addresses') from demo where id<=1000;
\watch 0.001
SQL
```
You should see all reads from the local server, as long as they have the tablet LEADER or FOLLOWER, and this also works from read replicas

# Screenshots

When started:

![image](https://user-images.githubusercontent.com/33070466/150552326-9d48f8d6-be31-405f-9506-2d7af65c6c49.png)

List of containers:

![image](https://user-images.githubusercontent.com/33070466/150541577-065967bc-4069-4eed-b939-3ac9a7d45bd5.png)

Cluster configuration from the logs of yb-lab_cluster-config:

![image](https://user-images.githubusercontent.com/33070466/150541630-c15da94d-e2a2-4492-a95c-0502d34109c2.png)

Smart driver demo:

![image](https://user-images.githubusercontent.com/33070466/150541806-2fba911b-c565-4cfc-a3f1-8edac6a3084d.png)

List of servers from the console:

![image](https://user-images.githubusercontent.com/33070466/150541890-b67e2540-9526-41fa-81a0-206831deb30a.png)

Performance metrics between two snapshots:

![Screenshot 2022-02-15 183046](https://user-images.githubusercontent.com/33070466/154118148-5906ed77-2240-4090-bf16-ab8ccddf29ec.png)
