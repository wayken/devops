# 服务监控脚本

## 工作原理：
1. 通过读取配置文件监控指定进程是否存活，进程挂掉则自动重启并报警，记录日志
2. 读取监控数据并上报到数据平台进行平台查看

## 服务启动
python monitor.py -c "/etc/monitor/monitor.conf" --daemon

也可以配置服务启动时自动开启该监控脚本，编辑`/etc/rc.local`

```sh
python3.8 /home/monitor.py -c "/home/etc/monitor/monitor.conf" --daemon > /dev/null 2>&1 &
```

## `monitor.conf`配置说明

- interval: 监控脚本定时监控时间，单位为秒，默认为1分钟
- parallel: 配置多少个线程进行多线程监听，如果要监听的服务比较多，可以适当配置对应的线程数
- logger: 配置日志路径
- services: 配置监听的服务列表
  - name: 要监听的服务名称
  - host: 要监听的服务IP或者服务域名
  - port: 要监听的服务端口
  - script: 当要监听的服务IP+端口无法连通时调用对应的启动脚本
- notification: 当监听到服务宕机进行脚本重启时调用对应的通知脚本，可以配置邮件告警或者企微告警

## 后续规划
1. 抽象配置模块，支持通过ZK读取配置
