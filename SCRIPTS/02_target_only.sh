#!/bin/bash
# 02_target_only.sh  (x86 专用, 在 openwrt/ 目录内运行)
set -euo pipefail

# 默认设备名与 Intel CPU 调度偏好(开机执行一次)
cat > ./package/base-files/files/etc/rc.local <<'EOF'
#!/bin/sh
# Put your custom commands here that should be executed once
# the system init finished. By default this file does nothing.

if grep -q "Default string" /tmp/sysinfo/model 2>/dev/null; then
    echo "Generic PC" > /tmp/sysinfo/model
fi

PSTATE_STATUS_FILE="/sys/devices/system/cpu/intel_pstate/status"
if [ -f "$PSTATE_STATUS_FILE" ]; then
    if [ "$(cat "$PSTATE_STATUS_FILE")" = "passive" ]; then
        echo "active" > "$PSTATE_STATUS_FILE"
    fi
    for cpu_gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        [ -f "$cpu_gov" ] && echo "powersave" > "$cpu_gov"
    done
    for cpu_epp in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
        [ -f "$cpu_epp" ] && echo "balance_performance" > "$cpu_epp"
    done
fi

exit 0
EOF
chmod 755 ./package/base-files/files/etc/rc.local

# 预置文件: 先审计再放行
# 这些文件会原样写进固件, 并且覆盖同名的系统文件, 必须逐个看过内容
if [ -d ../PATCH/files ]; then
  # 禁止覆盖账号、SSH、包管理器、启动脚本等敏感路径
  for bad in etc/shadow etc/passwd etc/group etc/dropbear root/.ssh \
             etc/rc.local etc/apk etc/opkg etc/sysupgrade.conf; do
    if [ -e "../PATCH/files/${bad}" ]; then
      echo "错误: PATCH/files 含敏感路径 ${bad}, 请审计后再决定是否放行" >&2
      exit 1
    fi
  done
  echo "===== PATCH/files 清单(含校验和, 请审计) ====="
  (cd ../PATCH/files && find . -type f -exec sha256sum {} + | sort -k2)
  rm -rf ./files
  cp -a ../PATCH/files ./files
fi

# 补丁失败的残留文件: .rej 表示有补丁没打上, 必须让构建失败, 不能悄悄删掉
if find . -name '*.rej' -not -path './dl/*' -print -quit | grep -q .; then
  echo "错误: 发现 .rej 文件, 说明有补丁应用失败:" >&2
  find . -name '*.rej' -not -path './dl/*' >&2
  exit 1
fi
find . -name '*.orig' -not -path './dl/*' -delete

exit 0
