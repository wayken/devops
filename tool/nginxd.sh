#!/bin/bash 

# nginx启动相关, 视部署情况修改
run=/bin/sh
ngx_bin=/usr/local/nginx/sbin/nginx
ngx_conf=/usr/local/nginx/conf/nginx.conf

# 输出样式颜色
style_red='\033[0;31m'
style_green='\033[0;32m'
style_plain='\033[0m'

# 启动nginx
function ngx_start() {
    cmd="ps auxw | grep -w $ngx_bin | grep -v grep | grep -w $ngx_conf | grep -v $0 | wc -l"
    count=`$run -c "$cmd"`
    if [ $count -eq 0 ]; then
        $ngx_bin -c $ngx_conf
        count=`$run -c "$cmd"`
        if [ $count -ge 1 ]; then
            echo -e "[${style_green}Info${style_plain}]: start nginx success"
        else
            echo -e "[${style_red}Error${style_plain}]: start nginx failed"
        fi
    else
        echo -e "[${style_red}Error${style_plain}]: nginx already running, start aborted!"       
    fi
}

# 关闭nginx
function ngx_stop() {
    cmd="ps auxw | grep -w $ngx_bin | grep -v grep | grep -w $ngx_conf | grep -v $0 | awk '{print \$2;}'"
    pid=`$run -c "$cmd"`
    count=0
    if [ ! -z "$pid" ]; then
        echo -e "[${style_green}Info${style_plain}]: stoping nginx..."
        # 循环kill直到pid进程不存在
        while [ 1 -eq 1 ]; do
            if [ $count -gt 1 ]; then
                printf .
            fi

            pid=`$run -c "$cmd"`
            if [ -z "$pid" ]; then
                break
            else
                killall -TERM nginx
            fi

            count=`expr $count + 1`
            sleep 1
        done
        echo -e "[${style_green}Info${style_plain}]: nginx stop success"
    fi
}

# 重启nginx
function ngx_restart() {
    ngx_stop
    sleep 1
    ngx_start
}

# 重载nginx
function ngx_reload() {
    killall -HUP nginx
    echo -e "[${style_green}Info${style_plain}]: nginx reload success"
}

# 检查nginx配置是否正确
function ngx_check() {
    sudo ${ngx_bin} -t -c ${ngx_conf}
}

# 程序入口
action="$1"
case $action in
    start|stop|reload|check|restart)
        ngx_$action
    ;;
    *)
    echo "Usage: $(basename $0) {start|stop|restart|reload|check}"
    exit 1
esac