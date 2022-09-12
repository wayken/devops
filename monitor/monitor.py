#!/usr/bin/python
#coding=utf-8

'''
脚本功能:
  1、通过读取配置文件监控指定进程是否存活，进程挂掉则自动重启并报警，记录日志
  2、读取监控数据并上报到数据平台进行平台查看
调用关系: python monitor.py -c "/etc/monitor.conf"
调用关系: python monitor.py -c "/etc/monitor.conf" --daemon > /dev/null 2>&1 &
参数说明：
  -c 指定读取配置的配置文件，用于读取里面要监控的进程和启动脚本
  --daemon 是否以守护进程执行，开启则监控脚本将定期执行监控，关闭则监控脚本执行一次(可配置cron定时执行)
'''

import os, time, sys, io, math
import traceback, subprocess, logging, json, socket
from concurrent.futures import ThreadPoolExecutor
from optparse import OptionParser
from multiprocessing import cpu_count

CMD_OPTIONS = None
CONFIG = None

'''
解析命令行参数
'''
def __parse_options():
    parser = OptionParser()
    parser.add_option('-c', '--conf', dest='conf_file', default='', help='Config file')
    parser.add_option('', '--daemon', dest='daemon', action='store_true', default=False, help='Program run in background')
    return parser.parse_args()

'''
解析终端命令
'''
def __run_shell(cmd):
    popen = subprocess.Popen(cmd, shell=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        out, err = popen.communicate(timeout=12)
        status = popen.wait()
        out_content = out.decode('utf-8')
        err_content = err.decode('utf-8')
        if out_content:
            logging.debug('run shell "{}" ok.'.format(cmd))
        if err_content:
            logging.error('run shell "{}" fail with error "{}".'.format(cmd, err_content.strip()))
        return True
    except Exception as e:
        return False

'''
加载监控节点，支持
1、从配置文件中加载监控节点
'''
def __load_data():
    conf_file = CMD_OPTIONS.conf_file
    if not os.path.isfile(conf_file):
        raise Exception('Conf file "{}" not found'.format(conf_file))
    with io.open(conf_file, encoding='UTF-8') as f:
        content = json.load(f)
        f.close()
        return content

'''
根据线程数，分割监控节点列表
@param services 所有的服务监控列表
@param parallel 同一时间并行运行的监控数
'''
def __parallel_service(services, parallel):
    services_parallel = []
    for i in range(0, int(len(services)) + 1, parallel):
        service = services[i:i+parallel]
        services_parallel.append(service)
    return services_parallel

'''
线路监控节点任务
'''
def __monitor_execute(services):
    if not services:
        return False
    try:
      for service in services:
          disable = service.get('disable')
          if disable: break
          name = service.get('name')
          host = service.get('host')
          port = service.get('port')
          # 进行socket连接测试
          if __is_socket_connected(host, port):
              # 连接想通则输出信息
              logging.debug("peer {} {}:{} connect ok.".format(name, host, port))
          else:
              # 连接不同则调用脚本重启服务
              logging.warning("peer {} {}:{} connect fail.".format(name, host, port))
              __service_restart(service)
          return True
    except Exception as e:
        logging.error(
            'Monitor execute failed:\n{}'.format(traceback.format_exc())
        )
        return False

'''
调用节点重启脚本，让系统自动重启服务
'''
def __service_restart(service):
    name = service.get('name')
    host = service.get('host')
    port = service.get('port')
    script = service.get('script')
    logging.debug('run shell "{}" to restart.'.format(script))
    __run_shell(script)
    success = __is_socket_connected(host, port)
    message = 'peer {} {}:{} restart {}.'\
        .format(name, host, port, 'ok' if success else 'fail')
    logging.info(message)
    # 发送报警
    notification_cmd = CONFIG.get('notification')
    if notification_cmd:
        __run_shell(notification_cmd)
    return success

'''
检测服务器端口连通性
'''
def __is_socket_connected(host, port):
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(6)
        sock.connect((host, port))
        return True
    except socket.error as e:
        return False
    finally:
        sock.close()

'''
进行监控节点监控和故障自动重启
'''
def __do_monitor(executor):
    services = CONFIG.get('services')
    parallel = CONFIG.get('parallel')
    services_execute = __parallel_service(services, math.ceil(len(services) / parallel))
    for i in services_execute:
        executor.submit(__monitor_execute, i)

def __main__():
    # 初始化处理线程池
    executor = ThreadPoolExecutor(max_workers=cpu_count() * 5)
    # 初始化日志输出
    logger_filename = CONFIG.get('logger')
    logging.basicConfig(
        level = logging.DEBUG,
        format = "[%(levelname)s] %(asctime)s %(message)s",
        filename=logger_filename,
        filemode='a',
        datefmt = '%Y-%m-%d %H:%M:%S'
    )
    daemon = CMD_OPTIONS.daemon
    if daemon:
        while True:
            __do_monitor(executor)
            time.sleep(CONFIG.get('interval'))
    else:
        __do_monitor(executor)

if __name__ == '__main__':
    try:
        # 解析命令行参数
        (CMD_OPTIONS, args) = __parse_options()
        if not CMD_OPTIONS.conf_file:
            raise Exception('No conf file specified. Specify with -c or --conf')
        # 读取加载配置文件
        CONFIG = __load_data()
        __main__()
    except Exception as e:
        logging.error(
            'Monitor process failed:\n{}'.format(traceback.format_exc())
        )
