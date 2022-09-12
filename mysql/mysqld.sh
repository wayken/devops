#!/bin/bash 
: '
mysql数据库配置、安装与启动、关闭操作, 各指令说明如下:
1、创建数据库:./mysqld.sh create [dbname]
    Please enter db user:   - 输入启动mysql的用户, 示例:root
    Please enter db port:   - 输入启动mysql的监听端口, 示例:9090
2、启动数据库:./mysqld.sh start [dbname]
3、关闭数据库:./mysqld.sh stop [dbname]
'

# mysql配置启动相关, 视部署情况修改
# mysql安装默认用户名[mysql_install_db --user xxx]
mysql_user=root
# mysql安装路径
mysql_home=/usr/local/mysql
# mysql数据仓库安装根目录, 所有数据仓库统一安装在此根目录下
data_home=/dat/mysql
# mysql配置文件根目录, 所有mysql配置文件统一放在此目录下
conf_home=/etc/mysql

# 启动/关闭mysql超时时间
start_timeout=10
shutdown_timeout=20

# 脚本运行所在工作目录
workdir=$(cd $(dirname $0); pwd)

# 输出样式颜色
style_error='\033[0;31m'
style_info='\033[0;32m'
style_warn='\033[0;33m'
style_plain='\033[0m'

function version_ge(){
    test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" == "$1"
}

function version_gt(){
    test "$(echo "$@" | tr " " "\n" | sort -V | head -n 1)" != "$1"
}

function print_help() {
    echo "Usage: $(basename $0) {start|stop|create|drop} [dbname]"
    exit 1
}

# 数据库创建
function mysql_create() {
    # 安装目录必须先存在
    if [ ! -d ${mysql_home} ]; then
        echo -e "[${style_error}Error${style_plain}]: ${mysql_home} not found."
        exit 1
    fi
    # 模板配置文件必须先存在
    if [ ! -f ${workdir}/mysql.cnf ]; then
        echo -e "[${style_error}Error${style_plain}]: template '${workdir}/mysql.cnf' not found."
        exit 1
    fi
    # 数据仓库目录必须先存在
    if [ ! -d ${data_home} ]; then
        echo -e "[${style_error}Error${style_plain}]: data home '${data_home}' not found."
        exit 1
    fi
    # 配置目录必须先存在
    if [ ! -d ${conf_home} ]; then
        echo -e "[${style_error}Error${style_plain}]: ${conf_home} not found."
        exit 1
    fi

    # 进行交互获取所需参数
    db_name=$1
    db_datadir=${data_home}/${db_name}
    # 如果数据仓库已经存在同不再该目录创建, 避免把重要数据覆盖了
    if [ -d ${db_datadir} ]; then
        echo -e "[${style_error}Error${style_plain}]: ${db_datadir} already exists."
        exit 1
    fi
    read -p "Please enter db user (Default user: ${mysql_user}):" db_user
    [ -z ${db_user} ] && db_user=root
    # linux账号不存在不能创建数据仓库
    if [ `grep -c ${db_user}: /etc/passwd` -eq 0 ]; then
        echo -e "[${style_error}Error${style_plain}]: user '${db_user}' not exist in linux."
        exit 1
    fi
    read -p "Please enter db port (Default user: 9090):" db_port
    [ -z ${db_port} ] && db_port=9090
    # 检查输入端口是否合法
    if [ ${db_port} -gt 65535 ] || [ ${db_port} -lt 1024 ]; then
        echo -e "[${style_error}Error${style_plain}]: Invalid db port ${db_port}."
        exit 1
    fi
    read -p "Please enter bind address (Default bind address: 0.0.0.0):" db_bind_address
    [ -z ${db_bind_address} ] && db_bind_address=0.0.0.0

    # 开始创建数据仓库
    # mysql5.7之前用mysql_install_db --options
    # mysql5.7之后推荐用mysqld --initialize --options, 其实也是套了个壳
    version=$(mysql -V | awk '{print $5+0}')
    if version_ge ${version} 5.7; then
        ${mysql_home}/bin/mysqld --initialize --user=${db_user} --datadir=${db_datadir}
    else
        ${mysql_home}/script/mysql_install_db --user=${db_user} --datadir=${db_datadir}
    fi
    chown -R ${db_user}:${db_user} ${db_datadir}
    # 创建配置文件, 替换配置模板内容并复制到对应配置目录
    db_cfgfile=${conf_home}/mysql_${db_name}.conf
    cp ${workdir}/mysql.cnf ${db_cfgfile}
    sed -i "s#__user__#${db_user}#" ${db_cfgfile}
    sed -i "s#__port__#${db_port}#" ${db_cfgfile}
    sed -i "s#__host__#${db_bind_address}#" ${db_cfgfile}
    sed -i "s#__datadir__#${db_datadir}#" ${db_cfgfile}
    sed -i "s#__socket__#${db_datadir}/${db_name}.sock#" ${db_cfgfile}
    sed -i "s#__pidfile__#${db_datadir}/${db_name}.pid#" ${db_cfgfile}
    sed -i "s#__log_bin__#${db_datadir}/${db_name}_bin.log#" ${db_cfgfile}
    sed -i "s#__log_slow__#${db_datadir}/${db_name}_slow.log#" ${db_cfgfile}
    sed -i "s#__log_error__#${db_datadir}/${db_name}_error.log#" ${db_cfgfile}
    sed -i "s#__log_relay__#${db_datadir}/${db_name}_relay.log#" ${db_cfgfile}

    # 提示创建数据仓库成功
    if [ -d ${db_datadir} ]; then
        echo -e "[${style_info}Info${style_plain}] database '${db_datadir}' create success."
    else
        echo -e "[${style_error}Error${style_plain}] database '${db_datadir}' create fail."
    fi
}

# 数据库删除, 仅用于测试
function mysql_drop() {
    # mysql安装目录必须先存在
    if [ ! -d ${mysql_home} ]; then
        echo -e "[${style_error}Error${style_plain}]: ${mysql_home} not found."
        exit 1
    fi
    # 要启动的数据库必须存在
    db_name=$1
    db_datadir=${data_home}/${db_name}
    if [ ! -d ${db_datadir} ]; then
        echo -e "[${style_warn}Warn${style_plain}]: database '${db_datadir}' not exists."
        exit 1
    fi

    # 删除数据仓库安装目录
    printf "Are you sure drop database ${style_error}${db_datadir}${style_plain}? [y/n]\n"
    read -p "(default: n):" answer
    [ -z ${answer} ] && answer="n"
    if [ "${answer}" == "y" ] || [ "${answer}" == "Y" ]; then
        rm -rf ${db_datadir}
        if [ ! -d ${db_datadir} ]; then
            echo -e "[${style_info}Info${style_plain}]: database '${db_datadir}' drop success"
        else
            echo -e "[${style_error}Error${style_plain}]: database '${db_datadir}' drop fail"
        fi
    else
        echo -e "[${style_info}Info${style_plain}]: database '${db_datadir}' drop cancelled, nothing to do..."
    fi
}

# 启动mysql进程
function mysql_start() {
    # 要启动的数据库必须存在
    db_name=$1
    db_datadir=${data_home}/${db_name}
    if [ ! -d ${db_datadir} ]; then
        echo -e "[${style_error}Error${style_plain}]: database '${db_datadir}' not found."
        exit 1
    fi
    # 数据库已经启动就没必要重新启动
    db_cfgfile=${conf_home}/mysql_${db_name}.conf
    count=`ps auxw | grep -w mysql | grep -v grep | grep -w ${db_cfgfile} | wc -l`
    if [ ${count} -gt 0 ]; then
        echo -e "[${style_warn}Warn${style_plain}]: database '${db_datadir}' started."
        exit 1
    fi
    # 开始启动数据库
    echo -e "[${style_info}Info${style_plain}]: starting mysql ${db_name}\c"
    ${mysql_home}/bin/mysqld_safe --defaults-file=${db_cfgfile} >/dev/null 2>&1 &
    pid_file=${db_datadir}/${db_name}.pid
    # 定时判断mysql是否启动成功
    i=0
	while test $i -ne $shutdown_timeout ; do
	   test -s $pid_file && i='' && break
	   printf "."
	   i=`expr $i + 1`
	   sleep 1
	done
    echo ""
	if test -z "$i" ; then
	   echo -e "[${style_info}Info${style_plain}]: database '${db_datadir}' start success"
	else
	   echo -e "[${style_error}Error${style_plain}]: database '${db_datadir}' start failed"
	fi
}

# 关闭mysql进程
function mysql_stop() {
    # 要关闭的数据库必须存在
    db_name=$1
    db_datadir=${data_home}/${db_name}
    if [ ! -d ${db_datadir} ]; then
        echo -e "[${style_error}Error${style_plain}]: database '${db_datadir}' not found."
        exit 1
    fi
    # 数据库已经关闭就没必要重复关闭
    db_cfgfile=${conf_home}/mysql_${db_name}.conf
    count=`ps auxw | grep -w mysql | grep -v grep | grep -w ${db_cfgfile} | wc -l`
    if [ ${count} -le 0 ]; then
        echo -e "[${style_warn}Warn${style_plain}]: database '${db_datadir}' stopped."
        exit 1
    fi

    # 要关闭的数据库pid文件必须存在
    pid_file=${db_datadir}/${db_name}.pid
    if [ ! -f ${pid_file} ]; then
        echo -e "[${style_error}Error${style_plain}]: ${pid_file} not found."
        exit 1
    fi
    echo -e "[${style_info}Info${style_plain}]: stoping mysql ${db_name}\c"
	kill `cat $pid_file`
    # 定时判断mysql是否关闭成功
    i=0
	while test $i -ne $shutdown_timeout ; do
	   test ! -s $pid_file && i='' && break
	   printf "."
	   i=`expr $i + 1`
	   sleep 1
	done
    echo ""
	if test -z "$i" ; then
	   echo -e "[${style_info}Info${style_plain}]: database '${db_datadir}' shutdown success"
	else
	   echo -e "[${style_error}Error${style_plain}]: database '${db_datadir}' shutdown failed"
	fi
}

# 程序入口
action=$1
dbname=$2
([ -z $1 ] || [ -z $2 ]) && print_help
case $action in
    start|stop|create|drop)
        mysql_${action} ${dbname}
    ;;
    *)
    print_help
esac
