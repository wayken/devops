#!/bin/bash

: '
CentOS系统优化脚本，包括优化系统环境、内核和网络，脚本必须以root运行
'
# 欢迎信息
cat << EOF
+--------------------------------------------------------------+
|        === Welcome to Centos System Initializer ===          |
+--------------------------------------------------------------+
EOF

# 检查是否为root权限
[ $(id -u) != "0" ] && echo "Error: You must be root to run this script" && exit 1

# yum安装必要组件
yum install -y lrzsz make unzip zlib zlib-devel gcc gcc-c++ ncurses-devel perl pcre-devel ntp rsync telnet net-tools openssl openssl-devel vim automake autoconf libtool vnstat wget libaio libaio-devel
yum -y erase sendmail qmail mysql httpd vsftpd

# 初始化系统时间配置
echo "ZONE=\"Asia/Shanghai\"" > /etc/sysconfig/clock
echo "UTC=true" >> /etc/sysconfig/clock
echo "ARC=false" >> /etc/sysconfig/clock
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

# 关闭selinux
setenforce 0
sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config

#关闭NM
sed -i 's#.*NM_CONTROLLED=.*#NM_CONTROLLED="no"#g' /etc/sysconfig/network-scripts/ifcfg-*

#关闭发邮件
if [ -z "$(grep MAILCHECK /etc/profile)" ];then
  echo 'unset MAILCHECK'>>/etc/profile
fi
sed -i "s/^MAILTO=root/MAILTO=\"\"/g" /etc/crontab

# 修改linux终端配置
sed -i 's/PS1="\[\\u@\\h \\W\]/PS1="\[\\u@\\h \\w\]/' /etc/bashrc
source /etc/bashrc

# 修改yum超时时间
sed -i '/timeout=.*/d' /etc/yum.conf 
echo 'timeout=60' >>/etc/yum.conf

# 优化JVM
if [ -z '$(grep MALLOC_ARENA_MAX /etc/profile)' ];then
  echo 'export MALLOC_ARENA_MAX=1' >> /etc/profile
fi
source /etc/profile

# 设置时区
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime >/dev/null 2>&1
echo 'Asia/Shanghai' > /etc/timezone

# 优化系统内核
rm -f /etc/security/limits.d/*
cp -f limits.conf /etc/security/limits.conf
cp -f 90-nproc.conf /etc/security/limits.d/90-nproc.conf
cp -f sysctl.conf /etc/sysctl.conf
cp -f system.conf /etc/systemd/system.conf
# 让内核配置生效
sysctl -p

cat << EOF
+---------------------------------------------------------+
|        === OK: Centos System Initialize OK ===          |
+---------------------------------------------------------+
EOF
