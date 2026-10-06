#!/bin/bash
# 07_verify_nft.sh
# 在 make defconfig 之后、在 openwrt/ 目录内运行
# 校验最终 .config 是否为"纯 nftables"方案, 不满足就让构建失败
set -euo pipefail

CFG=".config"
[ -f "$CFG" ] || { echo "错误: 找不到 ${CFG}, 请先运行 make defconfig" >&2; exit 1; }
grep -q '^CONFIG_TARGET_x86_64=y$' "$CFG" || { echo "错误: 目标不是 x86_64" >&2; exit 1; }

fail=0

# 1. 禁止出现的包 (=y 或 =m 都算)
forbidden='^CONFIG_PACKAGE_(firewall|ipset|nat6|miniupnpd-iptables|kmod-nf-ipt6?)=[ym]$
^CONFIG_PACKAGE_(iptables|ip6tables|xtables|ebtables|arptables)[A-Za-z0-9_-]*=[ym]$
^CONFIG_PACKAGE_kmod-(ipt|ip6t)-[A-Za-z0-9_-]*=[ym]$
^CONFIG_PACKAGE_kmod-r8169=[ym]$
^CONFIG_PACKAGE_dnsmasq_full_ipset=[ym]$
^CONFIG_PACKAGE_luci-compat=[ym]$'
while IFS= read -r pat; do
  if hits="$(grep -E "$pat" "$CFG")"; then
    echo "错误: 发现不应存在的包:" >&2
    echo "$hits" >&2
    fail=1
  fi
done <<< "$forbidden"

# 2. 必须出现的包
required="firewall4 dnsmasq-full dnsmasq_full_nftset kmod-r8125 mwan3 luci-app-mwan3 \
smartdns adguardhome mosdns luci-app-passwall2 kmod-nft-tproxy"
for p in $required; do
  grep -qE "^CONFIG_PACKAGE_${p}=y$" "$CFG" || { echo "错误: 缺少 ${p}" >&2; fail=1; }
done

# 3. passwall2 必须使用 nftables 透明代理 (选项名以 feed 实际为准)
if grep -qE '^CONFIG_PACKAGE_luci-app-passwall2_Iptables_Transparent_Proxy=y$' "$CFG"; then
  echo "错误: passwall2 启用了 iptables 透明代理" >&2; fail=1
fi

# 4. 禁止关闭 CPU 漏洞缓解
if grep -rn 'mitigations=off' target/linux/x86/image 2>/dev/null; then
  echo "错误: 启动参数中包含 mitigations=off" >&2; fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo "校验失败: 最终配置不是纯 nftables 方案, 请检查依赖来源" >&2
  exit 1
fi
echo "校验通过: 纯 nftables 配置"
exit 0
