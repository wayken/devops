#!/bin/bash

: '
java服务启动、关闭操作, 各指令说明如下:
1、启动服务: ./jsvr.sh start [service]
2、重启服务: ./jsvr.sh restart [service]
3、关闭服务: ./jsvr.sh stop [service]
5、查看服务信息: ./jsvr.sh stat [service]
6、指定配置文件启动服务：./jsvr start [service] -c /etc/service/[service].xml
工作原理:
1. 程序启动时会判断服务实例所在$service_home目录是否存在
2. 启动服务实例所在目录下的执行程序${service}.jar
3. 在程序启动时会在$service_log目录创建对应的stdout.log和stderr.log两个日志文件，对应标准输出和错误输出
4. 旧的服务实例日志会移到以当前日期命名的日志文件中
'
readonly program="`basename $0`"
readonly run=/bin/sh
# jdk安装路径&服务实例路径
readonly jdk_home=/usr/local/jdk
readonly service_home=/root/sbin
readonly service_log=/root/logs
readonly service_default_cfg=application.all.xml
# 启动/关闭实例超时时间
readonly start_timeout=5
readonly shutdown_timeout=5
# 默认jvm参数
readonly default_jvmoption=(
  -server
  -XX:+PrintGCDateStamps
  -XX:+PrintGCDetails
  -Djava.nio.channels.spi.SelectorProvider=sun.nio.ch.EPollSelectorProvider
)

# 命令用法列表
function print_help() {
  echo -e "Usage: ${program} {start|stop|restart|stat} [service]"
  exit 1
}

function print_info() {
  local message=$1
  echo -e "[\033[0;36mInfo\033[0m]: " ${message}
}

function print_warn() {
  local message=$1
  echo -e "[\033[0;33mWarn\033[0m]: " ${message}
}

function fatal() {
  local message=$1
  echo -e "[\033[0;31mError\033[0m]: " ${message}
  exit 1
}

# 启动java实例服务
function jsvr_start() {
  # jdk安装目录必须先存在
  if [ ! -d ${jdk_home} ]; then
    fatal "jdk home '${jdk_home}' not found."
  fi
  # 服务实例目录必须先存在
  local service=$1
  local service_directory=${service_home}/${service}
  if [ ! -d ${service_directory} ]; then
    fatal "service directory '${service_directory}' not found."
  fi
  # 服务日志目录必须先存在
  local service_logpath=${service_log}/${service}
  if [ ! -d ${service_log} ]; then
    fatal "service log path '${service_log}' not found."
  fi
  if [ ! -d ${service_logpath} ]; then
    mkdir -p ${service_logpath}
  fi
  # 检查服务实例是否已经启动
  local cmd="ps auxw | grep java | grep -w Dsvr=service-${service} | grep -v grep | grep -v $0 | wc -l"
  local count=$($run -c "$cmd")
  if [[ $count > 0 ]]; then
    print_warn "service ${service} already running, start aborted!"
    return 0
  fi
  # 解析jvmoption文件参数
  local jvmoption_file=${service_directory}/jvmoption.conf
  if [ ! -f ${jvmoption_file} ]; then
    fatal "jvmoption file '${jvmoption_file}' not found."
  fi
  # 对jvm配置文件进行linux换行转码，避免windows文件的换行的linux不兼容
  sed -i 's/\r\n/\n/' ${jvmoption_file}
  # 补充默认jvm参数
  local default_jvmargs=""
  for i in ${default_jvmoption[@]};do
    default_jvmargs="$default_jvmargs $i"
  done
  # 启动时指定日志存储，将标准日志输出到stdout，将错误日志输出到stderr
  local current_day=$(date "+%Y-%m-%d")
  local log_file_stdout="${service_logpath}/stdout.log"
  local pre_log_file_stdout="${service_logpath}/stdout.${current_day}.log"
  local log_file_stderr="${service_logpath}/stderr.log"
  local pre_log_file_stderr="${service_logpath}/stderr.${current_day}.log"
  local log_file_gc="${service_logpath}/gc.log"
  local pre_log_file_gc="${service_logpath}/gc.${current_day}.log"
  # 移动旧日志，以当前系统时间进行日志文件重命名
  if [ -e ${log_file_stdout} ]; then
    if [ -e ${pre_log_file_stdout} ]; then
      cat ${log_file_stdout} >> ${pre_log_file_stdout} && rm -f ${log_file_stdout}
    else
      mv ${log_file_stdout} ${pre_log_file_stdout}
    fi
  fi
  if [ -e ${log_file_stderr} ]; then
    if [ -e ${pre_log_file_stderr} ]; then
      cat ${log_file_stderr} >> ${pre_log_file_stderr} && rm -f ${log_file_stderr}
    else
      mv ${log_file_stderr} ${pre_log_file_stderr}
    fi
  fi
  if [ -e ${log_file_gc} ]; then
    if [ -e ${pre_log_file_gc} ]; then
      cat ${log_file_gc} >> ${pre_log_file_gc} && rm -f ${log_file_gc}
    else
      mv ${log_file_gc} ${pre_log_file_gc}
    fi
  fi
  # 解析配置文件路径，策略如下：
  # 1. 默认为读取${service_directory}目录下application.all.xml
  # 2. 如果启动脚本有-c xxx指定要启动的配置文件则以此为依准
  # 3. 如果${service_directory}目录下没有application.all.xml并且启动脚本没有-c指定配置则不配置此命令行
  local confargs=""
  if [ ! -z "${conf}" ]; then
    confargs="-c ${conf}"
  elif [ -e ${service_directory}/${service_default_cfg} ]; then
    confargs="-c ${service_directory}/${service_default_cfg}"
  fi
  # 开始启动服务
  print_info "starting ${service} service\c"
  local jvmargs="-Dsvr=service-${service} ${default_jvmargs} `cat ${jvmoption_file} | sed ':a;N;s/\n/ /g;ta'` -Xloggc:${log_file_gc}"
  ${jdk_home}/bin/java ${jvmargs} -jar ${service_directory}/${service}.jar ${confargs} >>${log_file_stdout} 2>>${log_file_stderr} &
  # 定时判断实例是否启动成功
  sleep 1
  local i=0
  while [[ $i < $start_timeout ]]; do
    count=$($run -c "$cmd")
    if [[ $count > 0 ]]; then
      i=''
      break
    fi
    printf "."
    i=$(expr $i + 1)
    sleep 1
  done
  echo ""
  if test -z "$i" ; then
    print_info "start service ${service} success."
	else
    fatal "start service ${service} failed! Please check log file in ${log_file_stderr}"
  fi
}

# 关闭java实例服务
function jsvr_stop() {
  # jdk安装目录必须先存在
  if [ ! -d ${jdk_home} ]; then
    fatal "jdk home '${jdk_home}' not found."
  fi
  # 服务实例目录必须先存在
  local service=$1
  local service_directory=${service_home}/${service}
  if [ ! -d ${service_directory} ]; then
    fatal "service directory '${service_directory}' not found."
  fi
  # 检查服务实例是否已经启动
  local cmd="ps auxw | grep java | grep -w Dsvr=service-${service} | grep -v grep | grep -v $0 | awk '{print \$2;}'"
  local pid=$($run -c "$cmd")
  # 指定的服务实例没有启动
  if [ -z "$pid" ]; then
    print_warn "service ${service} not found!"
    return 0
  fi
  print_info "stoping service ${service}\c"
  # 定时判断实例是否关闭成功
  local i=0
  while (( $i < $shutdown_timeout )); do
    pid=$($run -c "$cmd")
    # 输出进度条
    test -z ${pid} && i='' && break
    printf "."
    i=$(expr $i + 1)
    # 关闭服务实例，先正常关闭3次，关闭失败再强制关闭
    if (( $i < 3 )); then
      kill -15 $pid
    else
      kill -9 $pid
    fi
    sleep 1
  done
  echo ""
  if [ -z "$pid" ]; then
    print_info "stop service ${service} success."
	else
    fatal "stop service ${service} failed! Please check log file in ${log_file_stderr}"
	fi
}

# 重启java实例服务
function jsvr_restart() {
  local service=$1
  jsvr_stop ${service}
  sleep 1
  jsvr_start ${service}
}

# 查看服务启动信息
function jsvr_stat() {
  local service=$1
  local cmd="ps -ef | grep java | grep -w Dsvr=service-${service} | grep -v grep | grep -v $0"
  local info=$($run -c "$cmd")
  if [ -z "$info" ]; then
    fatal "service ${service} not found"
	fi
  local pid=`echo ${info} | awk -F ' ' '{print $2}'`
  local jvmargs=${info#*-server}
  local document=${service_home}/${service}
  local service_logpath=${service_log}/${service}
  echo "SERVICE_PID: ${pid}"
  echo "SERVICE_NAME: `echo ${info} | awk -F ' ' '{print $9}' | awk -F '=' '{print $2}'`"
  echo "SERVICE_TIME: `echo ${info} | awk -F ' ' '{print $5}'`"
  echo "SERVICE_BIN: `echo ${info} | awk -F '-jar' '{print $2}' | awk -F ' ' '{print $1}'`"
  echo "SERVICE_HOME: ${document}"
  echo "SERVICE_LOGS: ${service_logpath}"
  echo "JAVA_HOME: ${jdk_home}"
  echo "JAVA_BIN: `echo ${info} | awk -F ' ' '{print $8}'`"
  echo "${jvmargs%-jar*}" | awk '{split($0,a," ");for(i=1;i<=NF;i++)print "JVM_ARGUMENT: "a[i]}'
  # local jvmargs=$($run -c "jinfo -flags ${pid} | grep "VM flags"")
  # echo "${jvmargs#*VM flags:*}" | awk '{split($0,a," ");for(i=1;i<=NF;i++)print "JVM_ARGUMENT: "a[i]}'
}

# 程序入口
# 检查操作系统是否支持
uname | grep '^Linux' -q || fatal "Error: $program only support Linux, not support `uname` yet!"
# 命令行参数解析
action=$1
service=$2
argument=`getopt -n "$program" -a -o p:c:a:s:S:Pd:Fmlh -l pid:,count:,append-file:,jstack-path:,jstack-file-dir:,use-ps,top-delay:,force,mix-native-frames,lock-info,help -- "$@"`
[ $? -ne 0 ] && { echo; usage 1; }
eval set -- "${argument}"
while true; do
  case "$1" in
  -c|--conf)
    conf="$2"
    shift 2
    ;;
    --)
    shift
    break
    ;;
  esac
done
([ -z $action ] || [ -z $service ]) && print_help
case $action in
  start|stop|restart|stat)
    jsvr_${action} ${service}
  ;;
  *)
  print_help
esac
