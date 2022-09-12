#!/bin/bash

: '
java项目启动、关闭操作, 各指令说明如下:
1、启动项目: ./jtomcat.sh start [project]
2、重启项目: ./jtomcat.sh restart [project]
3、关闭项目: ./jtomcat.sh stop [project]
5、查看项目信息: ./jtomcat.sh stat [project]
6、创建项目配置: ./jtomcat.sh create [project]
工作流程(以部署/root/web/webportal为例):
1. 将项目进行打包，可能为.war结尾压缩包
1. 将项目文件部署到WEB_HOME(/root/web/webportal)中，如果是压缩包则unzip解压
2. 目录下需要有WEB-INF目录和jvmoption.conf启动参数，即/root/web/webportal/WEB-INF
3. 在CONF_HOME下有对应的PROJECT.xml配置文件，用./jtomcat.sh create即可创建项目配置
4. 执行./jtomcat.sh start项目，启动后在LOG_HOME查看相关日志即可
'
readonly program="`basename $0`"
readonly run=/bin/sh
readonly workdir=$(cd $(dirname $0); pwd)
# tomcat安装路径&配置文件根目录
readonly tomcat_home=/usr/local/tomcat
readonly conf_home=/etc/tomcat
readonly web_home=/root/web
readonly log_home=/root/logs
# 启动/关闭实例超时时间
readonly start_timeout=5
readonly shutdown_timeout=5
# 默认jvm参数
readonly default_jvmoption=(
  -XX:+PrintGCDateStamps
  -XX:+PrintGCDetails
  -Djava.security.egd=file:/dev/./urandom
  -Djava.nio.channels.spi.SelectorProvider=sun.nio.ch.EPollSelectorProvider
)

# 命令用法列表
function print_help() {
  echo -e "Usage: ${program} {start|stop|restart|create} [project]"
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

# 启动tomcat项目实例
function tomcat_start() {
  # tomcat安装目录必须先存在
  if [ ! -d ${tomcat_home} ]; then
    fatal "tomcat home '${tomcat_home}' not found."
  fi
  # 项目目录必须先存在
  local project=$1
  local project_directory=${web_home}/${project}
  if [ ! -d ${project_directory} ]; then
    fatal "project directory '${project_directory}' not found."
  fi
  if [ ! -d ${log_home} ]; then
    fatal "logs home '${log_home}' not found."
  fi
  local project_file=${conf_home}/${project}.xml
  if [ ! -e ${project_file} ]; then
    fatal "project config file '${project_file}' not found."
  fi
  # 检查服务实例是否已经启动
  local cmd="ps auxw | grep java | grep -w Dsvr=tomcat-${project} | grep -v grep | grep -v $0 | wc -l"
  local count=$($run -c "$cmd")
  if [[ $count > 0 ]]; then
    print_warn "project ${project} already running, start aborted!"
    return 0
  fi
  # 解析jvmoption文件参数
  local jvmoption_file=${project_directory}/jvmoption.conf
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
  
  # 启动时指定日志存储，将标准日志输出到stdout.log，GC日志输出到gc.log
  local current_day=$(date "+%Y-%m-%d")
  local project_logpath=${log_home}/${project}
  if [ ! -d ${project_logpath} ]; then
    mkdir ${project_logpath}
  fi
  local log_file_gc="${project_logpath}/gc.log"
  local pre_log_file_gc="${project_logpath}/gc.${current_day}.log"
  local log_file_stdout="${project_logpath}/stdout.log"
  local pre_log_file_stdout="${project_logpath}/stdout.${current_day}.log"
  # 移动旧日志，以当前系统时间进行日志文件重命名
  if [ -e ${log_file_stdout} ]; then
    if [ -e ${pre_log_file_stdout} ]; then
      cat ${log_file_stdout} >> ${pre_log_file_stdout} && rm -f ${log_file_stdout}
    else
      mv ${log_file_stdout} ${pre_log_file_stdout}
    fi
  fi
  if [ -e ${log_file_gc} ]; then
    if [ -e ${pre_log_file_gc} ]; then
      cat ${log_file_gc} >> ${pre_log_file_gc} && rm -f ${log_file_gc}
    else
      mv ${log_file_gc} ${pre_log_file_gc}
    fi
  fi
  # 开始启动服务
  print_info "starting ${project} project\c"
  local jvmargs="${default_jvmargs} `cat ${jvmoption_file} | sed ':a;N;s/\n/ /g;ta'` -Xloggc:${log_file_gc}"
  export JAVA_OPTS="${jvmargs}"
  export CATALINA_OUT="${log_file_stdout}"
  ${tomcat_home}/bin/catalina.sh start -config ${project_file} -Dsvr=tomcat-${project} >/dev/null 2>&1 &
  # 定时判断实例是否启动成功
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
    print_info "start project ${project} success."
	else
    fatal "start project ${project} failed!"
  fi
}

# 关闭java实例服务
function tomcat_stop() {
  # tomcat安装目录必须先存在
  if [ ! -d ${tomcat_home} ]; then
    fatal "tomcat home '${tomcat_home}' not found."
  fi
  # 检查服务实例是否已经启动
  local project=$1
  local cmd="ps auxw | grep java | grep -w Dsvr=tomcat-${project} | grep -v grep | grep -v $0 | awk '{print \$2;}'"
  local pid=$($run -c "$cmd")
  # 指定的服务实例没有启动
  if [ -z "$pid" ]; then
    print_warn "project ${project} not found!"
    return 0
  fi
  print_info "stoping project ${project}\c"
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
    print_info "stop project ${project} success."
  else
    fatal "stop project ${project} failed!"
  fi
}

# 重启tomcat实例服务
function tomcat_restart() {
  local project=$1
  tomcat_stop ${project}
  sleep 1
  tomcat_start ${project}
}

# 创建tomcat模板配置文件
function tomcat_stat() {
  local project=$1
  local cmd="ps -ef | grep java | grep -w Dsvr=tomcat-${project} | grep -v grep | grep -v $0"
  local info=$($run -c "$cmd")
  if [ -z "$info" ]; then
    fatal "project ${project} not found"
	fi
  local pid=`echo ${info} | awk -F ' ' '{print $2}'`
  local jdk_bin=`echo ${info} | awk -F ' ' '{print $8}'`
  local jvmargs=${info#*${jdk_bin}}
  local document=${web_home}/${project}
  local logpath=${log_home}/${project}
  local project_file=${conf_home}/${project}.xml
  echo "PROJECT_PID: ${pid}"
  echo "PROJECT_NAME: `echo ${info} | awk -F ' ' '{print $(NF-1)}' | awk -F '=' '{print $2}'`"
  echo "PROJECT_TIME: `echo ${info} | awk -F ' ' '{print $5}'`"
  echo "PROJECT_HOME: ${document}"
  echo "PROJECT_LOGS: ${logpath}"
  echo "PROJECT_CONF: ${project_file}"
  echo "TOMAT_HOME: ${tomcat_home}"
  echo "JAVA_BIN: ${jdk_bin}"
  echo "${jvmargs%org.apache.catalina.startup.Bootstrap*}" | awk '{split($0,a," ");for(i=1;i<=NF;i++)print "JVM_ARGUMENT: "a[i]}'
}

# 创建tomcat模板配置文件
function tomcat_create() {
  # 模板文件必须先存在
  local template_file=$workdir/project.template.xml
  if [ ! -e ${template_file} ]; then
    fatal "tomcat template file '${template_file}' not found."
  fi
  # 项目、配置、日志目录必须先存在
  if [ ! -d ${conf_home} ]; then
    fatal "config home '${conf_home}' not found."
  fi
  if [ ! -d ${web_home} ]; then
    fatal "web home '${web_home}' not found."
  fi
  if [ ! -d ${log_home} ]; then
    fatal "logs home '${log_home}' not found."
  fi
  # 配置文件已经存在则提示是否创建
  local project=$1
  local project_file=${conf_home}/${project}.xml
  if [ -e ${project_file} ]; then
    read -p "${project_file} alredy exists, do override? [y/n](Default no):" override
    [ -z ${override} ] && override="n"
    if [[ "${override}" != "y" && "${override}" != "Y" ]]; then
      fatal "project config file '${project_file}' already exists."
    fi
  fi
  read -p "Please enter server port (Default user: 8080):" server_port
  [ -z ${server_port} ] && server_port=8080
  read -p "Please enter service port (Default user: 8180):" service_port
  [ -z ${service_port} ] && service_port=8180
  read -p "Please choose project reloadable [y/n](Default no):" reloadable
  [ -z ${reloadable} ] && reloadable="n"
  # 检查输入端口是否合法
  if (( ${server_port} > 65535 || ${server_port} < 1024 )); then
    fatal "Invalid server port ${server_port}."
  fi
  if (( ${service_port} > 65535 || ${service_port} < 1024 )); then
    fatal "Invalid server port ${service_port}."
  fi
  # 开始创建tomcat配置文件
  local document=${web_home}/${project}
  local logpath=${log_home}/${project}
  cp ${template_file} ${project_file}
  sed -i "s#\#server_port\##${server_port}#" ${project_file}
  sed -i "s#\#service_port\##${service_port}#" ${project_file}
  sed -i "s#\#project\##${project}#g" ${project_file}
  if [ "${reloadable}" == "y" ] || [ "${reloadable}" == "Y" ]; then
    sed -i "s#\#reloadable\##true#" ${project_file}
  else
    sed -i "s#\#reloadable\##false#" ${project_file}
  fi
  sed -i "s#\#document\##${document}#g" ${project_file}
  sed -i "s#\#log_path\##${logpath}#" ${project_file}
  # 提示创建成功
  if [ -e ${project_file} ]; then
    print_info "project file '${project_file}' create success."
  else
    fatal "project file '${project_file}' create fail."
  fi
}

# 程序入口
# 检查操作系统是否支持
uname | grep '^Linux' -q || fatal "Error: $program only support Linux, not support `uname` yet!"
action=$1
project=$2
([ -z $1 ] || [ -z $2 ]) && print_help
case $action in
  start|stop|restart|stat|create)
    tomcat_${action} ${project}
  ;;
  *)
  print_help
esac
