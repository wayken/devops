#!/bin/bash

: '
脚本功能: 快速排查Java的CPU性能问题(top us值过高)，从而确定导致性能问题的方法调用
工作原理:
1. `top`命令找出有问题`Java`进程及线程`id`：
  1. 开启线程显示模式
  2. 按`CPU`使用率排序
  3. 记下`Java`进程`id`及其`CPU`高的线程`id`
2. 用进程`id`作为参数，`jstack`有问题的`Java`进程
3. 手动转换线程`id`成十六进制（可以用`printf %x 1234`）
4. 查找十六进制的线程`id`（可以用`grep`）
5. 查看对应的线程栈
使用方法:
- 默认会自动从所有的java进程中找出最消耗cpu的线程，这样用更方便
- 当然也可以手动指定要分析的java进程id
  show-busy-thread -p <指定的java进程id>
- 指定要显示的线程栈数，默认为5个
  show-busy-thread -c <要显示的线程栈数> -p <指定的java进程id>
- 多次执行；这2个参数的使用方式类似vmstat命令
  show-busy-thread <重复执行的间隔秒数> [<重复执行的次数>]
- 设置输出的记录到的文件，以方便回溯查看
  show-busy-thread -a <运行输出的记录到的文件>
- 指定jstack输出文件的存储目录，方便记录以后续分析
  show-busy-thread -S <存储jstack输出文件的目录>
- 打印帮助信息
  show-busy-thread -h
参考链接: https://github.com/oldratlee/useful-scripts/blob/master/docs/java.md#beer-show-busy-java-threadssh
'
readonly program="`basename $0`"
readonly -a command_line=("$0" "$@")
readonly ec=$'\033' # escape char
readonly eend=$'\033[0m' # escape end

# 各种终端颜色输出
function color_echo() {
  local color=$1
  shift
  [ -t 1 ] && echo "$ec[1;${color}m$@$eend" || echo "$@"
}
function color_print() {
  local color=$1
  shift
  color_echo "$color" "$@"
  { [ -n "$append_file" ] && echo "$@" >> "$append_file"; } &> /dev/null
}
function red_print() {
  color_print 31 "$@"
}
function green_print() {
  color_print 32 "$@"
}
function yellow_print() {
  color_print 33 "$@"
}
function blue_print() {
  color_print 36 "$@"
}
function normal_print() {
  echo "$@"
  [ -n "$append_file" ] && echo "$@" >> "$append_file"
}
function fatal() {
  red_print "$@" 1>&2
  exit 1
}

# 命令用法列表
function usage() {
  local -r exit_code="$1"
  shift
  [ -n "$exit_code" -a "$exit_code" != 0 ] && local -r out=/dev/stderr || local -r out=/dev/stdout

  (( $# > 0 )) && { echo "$@"; echo; } > $out

  > $out cat <<EOF
Usage: ${program} [OPTION] [delay [ucount]]
Find out the highest cpu consumed threads of java, and print the stack of these threads.

Example: 
  ${program}       # show busy java threads info
  ${program} 1     # update every 1 second, (stop by eg: CTRL+C)
  ${program} 3 10  # update every 3 seconds, update 10 times

Options:
  -p, --pid       find out the highest cpu consumed threads from the specifed java process,
                  default from all java process.
  -c, --count     set the thread count to show, default is 5
  -a, --append-file <file>  specify the file to append output as log
  -s, --jstack-path <path>  specify the path of jstack command
  -F, --force               set jstack to force a thread dump(use jstack -F option)
  -S, --jstack-file-dir <path>  specifies the directory for storing jstack output files, and keep files.
                          default store jstack output files at tmp dir, and auto remove after run.
                          use this option to keep files so as to review jstack later.
  -m, --mix-native-frames   set jstack to print both java and native frames (mixed mode).
  -l, --lock-info           set jstack with long listing. Prints additional information about locks.
  -d, --top-delay  <deplay> specifies the delay between top samples, default is 0.5 (second).
                            get thread cpu percentage during this delay interval.
                            more info see top -d option. eg: -d 1 (1 second).
  -P, --use-ps              use ps command to find busy thread(cpu usage) instead of top command,
                            default use top command, because cpu usage of ps command is expressed as
                            the percentage of time spent running during the entire lifetime of a process,
                            this is not ideal.
  -h, --help      display this help and exit
  delay is the delay between updates in seconds. when this is not set, it will output once.
  ucount is the number of updates. when delay is set, ucount is not set, it will output in unstop mode.
EOF

  exit $exit_code
}

# 检查记录的文件是否存在，不存在则创建
function check_append_file() {
  local -r append_file=$1
  if [ -e "$append_file" ]; then
    [ ! -f "$append_file" ] && fatal "Error: $append_file (specified by option -a, for storing run output files) exists but is not a file!"
    [ ! -w "$append_file" ] && fatal "Error: file $append_file  (specified by option -a, for storing run output files) exists but is not writable!"
  else
    append_file_dir="$(dirname "$append_file")"
    if [ -e "$append_file_dir" ]; then
      [ ! -d "$append_file_dir" ] && fatal "Error: directory $append_file_dir (specified by option -a, for storing run output files) exists but is not a directory!"
      [ ! -w "$append_file_dir" ] && fatal "Error: directory $append_file_dir (specified by option -a, for storing run output files) exists but is not writable!"
    else
      mkdir -p "$append_file_dir" || fatal "Error: fail to create directory $append_file_dir (specified by option -a, for storing run output files)!"
    fi
  fi
}

# 检查要保存的jstack目录是否存在，不存在则创建
function check_jstack_dir() {
  local -r jstack_file_dir=$1
  if [ -e "$jstack_file_dir" ]; then
    [ ! -d "$jstack_file_dir" ] && fatal "Error: $jstack_file_dir (specified by option -S, for storing jstack output files) exists but is not a directory!"
    [ ! -w "$jstack_file_dir" ] && fatal "Error: directory $jstack_file_dir (specified by option -S, for storing jstack output files) exists but is not writable!"
  else
    mkdir -p "$jstack_file_dir" || fatal "Error: fail to create directory $jstack_file_dir (specified by option -S, for storing jstack output files)!"
  fi
}

function cleanup_when_exit() {
  rm /tmp/${uuid}_* &> /dev/null
}

# 检查操作系统是否支持
uname | grep '^Linux' -q || fatal "Error: $program only support Linux, not support `uname` yet!"

# 命令行参数解析
argument=`getopt -n "$program" -a -o p:c:a:s:S:Pd:Fmlh -l pid:,count:,append-file:,jstack-path:,jstack-file-dir:,use-ps,top-delay:,force,mix-native-frames,lock-info,help -- "$@"`
[ $? -ne 0 ] && { echo; usage 1; }
eval set -- "${argument}"
while true; do
  case "$1" in
  -c|--count)
    count="$2"
    shift 2
    ;;
  -p|--pid)
    pid="$2"
    shift 2
    ;;
  -a|--append-file)
    append_file="$2"
    shift 2
    ;;
  -s|--jstack-path)
    jstack_path="$2"
    shift 2
    ;;
  -S|--jstack-file-dir)
    jstack_file_dir="$2"
    shift 2
    ;;
  -P|--use-ps)
    use_ps=true
    shift
    ;;
  -d|--top-delay)
    top_delay="$2"
    shift 2
    ;;
  -F|--force)
    force=-F
    shift
    ;;
  -m|--mix-native-frames)
    mix_native_frames=-m
    shift
    ;;
  -l|--lock-info)
    more_lock_info=-l
    shift
    ;;
  -h|--help)
    usage
    ;;
  --)
    shift
    break
    ;;
  esac
done
count=${count:-5}
use_ps=${use_ps:-false}
top_delay=${top_delay:-0.5}
update_delay=${1:-0}
update_limit=${2:-0}

# 检查记录的文件是否存在，不存在则创建
if [ -n "$append_file" ]; then
  check_append_file $append_file
fi

# 检查要保存的jstack目录是否存在，不存在则创建
if [ -n "$jstack_file_dir" ]; then
  check_jstack_dir $jstack_file_dir
fi

# 检查jstack命令是否存在
if [ -n "$jstack_path" ]; then
  [ -f "$jstack_path" ] || fatal "Error: $jstack_path is NOT found!"
  [ -x "$jstack_path" ] || fatal "Error: $jstack_path is NOT executalbe!"
elif which jstack &> /dev/null; then
  jstack_path="`which jstack`"
else
  [ -z "$JAVA_HOME" ] && fatal "Error: jstack not found on PATH and No JAVA_HOME setting! Use -s option set jstack path manually."
  [ -f "$JAVA_HOME/bin/jstack" ] || fatal "Error: jstack not found on PATH and \$JAVA_HOME/bin/jstack($JAVA_HOME/bin/jstack) file does NOT exists! Use -s option set jstack path manually."
  [ -x "$JAVA_HOME/bin/jstack" ] || fatal "Error: jstack not found on PATH and \$JAVA_HOME/bin/jstack($JAVA_HOME/bin/jstack) is NOT executalbe! Use -s option set jstack path manually."
  jstack_path="$JAVA_HOME/bin/jstack"
fi

# 生成脚本进程临时文件
readonly run_timestamp="`date "+%Y-%m-%d_%H:%M:%S.%N"`"
readonly uuid="${program}_${run_timestamp}_${RANDOM}_$$"
readonly tmp_store_dir="/tmp/${uuid}"
mkdir -p "$tmp_store_dir"
if [ -n "$jstack_file_dir" ]; then
  readonly jstack_file_path_prefix="$jstack_file_dir/jstack_${run_timestamp}_"
else
  readonly jstack_file_path_prefix="$tmp_store_dir/jstack_${run_timestamp}_"
fi
trap "cleanup_when_exit" EXIT

# 输出头部信息
function print_head_info() {
  color_echo "0;34;42" ================================================================================
  echo "$(date "+%Y-%m-%d %H:%M:%S") [$(( update_count + 1 ))/$update_limit]: ${command_line[@]}"
  color_echo "0;34;42" ================================================================================
  echo
}

# 通过ps从所有的java进程中找出最消耗cpu的线程，数据有延时
find_busy_threads_by_ps() {
  if [ -n "${pid}" ]; then
    local -r ps_options="-p $pid"
  else
    local -r ps_options="-C java"
  fi
  ps $ps_options -wwLo pid,lwp,pcpu,user --sort -pcpu --no-headers | head -n "${count}"
}

# top with output field: thread id, %cpu, thsi value is realtime cpu usage
function __top_thread_id_cpu() {
  # 1. sort by %cpu by top option `-o %CPU`
  #    unfortunately, top version 3.2 does not support -o option(supports from top version 3.3+),
  #    use
  #       HOME="$tmp_store_dir" top -H -b -n 1
  #    combined
  #       sort
  #    instead of
  #       HOME="$tmp_store_dir" top -H -b -n 1 -o '%CPU'
  # 2. change HOME env var when run top,
  #    so as to prevent top command output format being change by .toprc user config file unexpectedly
  # 3. use option `-d 0.5`(interval 0.5 second) and `-n 2`(show 2 times), and use second time update data
  #    to get cpu percentage of thread in 0.5 second interval
  HOME="$tmp_store_dir" top -H -b -d $top_delay -n 2 |
    awk '{
      if (idx == 4 && $NF == "java")    # $NF is command
        # only print 4th text block(idx == 3), aka. process info of second top update
        print $1 " " $9    # $1 is thread id, $9 is %cpu
      if ($0 == "")
        idx++
    }' | sort -k2,2nr
}

# 通过top从所有的java进程中找出最消耗cpu的线程，数据实时
find_busy_threads_by_top() {
    if [ -n "${pid}" ]; then
      local -r ps_options="-p $pid"
    else
      local -r ps_options="-C java"
    fi
    # ps output field: pid, thread id(lwp), user
    local -r ps_out="$(ps $ps_options -wwLo pid,lwp,user --no-headers)"

    local idx=0
    local -a line
    while IFS=" " read -a line ; do
      (( idx < count )) || break

      local threadId="${line[0]}"
      local pcpu="${line[1]}"

      # output field: pid, threadId, pcpu, user
      local output_fields="$( echo "$ps_out" |
        awk -v "threadId=$threadId" -v "pcpu=$pcpu" '$2==threadId {
            print $1 " " threadId " " pcpu " " $3; exit
        }' )"
      if [ -n "$output_fields" ]; then
        (( idx++ ))
        echo "$output_fields"
      fi
    done < <( __top_thread_id_cpu )
}

# 将top出来的线程id进行转换和堆栈输出
print_stack_hreads() {
  local update_round_num="$1"
  local -a line
  local idx=0
  while IFS=" " read -a line ; do
    local pid="${line[0]}"
    local threadId="${line[1]}"
    local threadId0x="0x`printf %x ${threadId}`"
    local pcpu="${line[2]}"
    local user="${line[3]}"

    (( idx++ ))
    local jstackFile="$jstack_file_path_prefix${update_round_num}_${pid}"
    [ -f "${jstackFile}" ] || {
      if [ "${user}" == "${USER}" ]; then
        # run without sudo, when java process user is current user
        "$jstack_path" ${force} $mix_native_frames $more_lock_info ${pid} > ${jstackFile}
      elif [ $UID == 0 ]; then
        # if java process user is not current user, must run jstack with sudo
        sudo -u "${user}" "$jstack_path" ${force} $mix_native_frames $more_lock_info ${pid} > ${jstackFile}
      else
        # current user is not root user, so can not run with sudo; print error message and rerun suggestion
        red_print "[$idx] Fail to jstack busy(${pcpu}%) thread(${threadId}/${threadId0x}) stack of java process(${pid}) under user(${user})."
        red_print "User of java process($user) is not current user($USER), need sudo to rerun:"
        yellow_print "    sudo ${COMMAND_LINE[@]}"
        normal_print
        continue
      fi || {
        red_print "[$idx] Fail to jstack busy(${pcpu}%) thread(${threadId}/${threadId0x}) stack of java process(${pid}) under user(${user})."
        normal_print
        rm "${jstackFile}" &> /dev/null
        continue
      }
    }

    blue_print "[$idx] Busy(${pcpu}%) thread(${threadId}/${threadId0x}) stack of java process(${pid}) under user(${user}):"

    if [ -n "$mix_native_frames" ]; then
      local sed_script="/--------------- $threadId ---------------/,/^---------------/ {
        /--------------- $threadId ---------------/b # skip first seperator line
        /^---------------/s/.*// # replace sencond seperator line to empty line
        p
      }"
    elif [ -n "$force" ]; then
      local sed_script="/^Thread ${threadId}:/,/^$/p"
    else
      local sed_script="/nid=${threadId0x} /,/^$/p"
    fi
    sed "$sed_script" -n ${jstackFile} | tee ${append_file:+-a "$append_file"}
  done
}

# 程序运行
update_count=0
while true
do
  [ -n "$append_file" ] && print_head_info >> "$append_file"
  print_head_info
  if $use_ps; then
    find_busy_threads_by_ps
  else
    find_busy_threads_by_top
  fi | print_stack_hreads $(( update_count + 1 ))
  # 不需要定时刷新数据
  if (( "$update_delay" <= 0 )); then
    break
  fi
  ((update_count++))
  # 刷新次数到达上限
  if (( "$update_limit" > 0 && "$update_count" == "$update_limit" )); then
    break
  fi
  # 休眠
  sleep "$update_delay"
done
