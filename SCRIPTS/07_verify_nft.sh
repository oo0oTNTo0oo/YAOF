#!/bin/bash
# 07_verify_nft.sh
# 在 make defconfig 之后、在 openwrt/ 目录内运行
# 校验最终 .config 是否为"纯 nftables"方案, 不满足就让构建失败
# 可选环境变量:
#   SEED_FILE    seed 路径, 默认 ../SEED/X86/config.seed
#   STRICT_SEED  设为 1 时, seed 项被丢弃或被依赖重新启用也算失败(默认只警告)
set -euo pipefail

CFG=".config"
SEED="${SEED_FILE:-../SEED/X86/config.seed}"
STRICT_SEED="${STRICT_SEED:-0}"

fail=0
warns=0
err()  { echo "错误: $*" >&2; fail=1; }
warn() { echo "::warning::$*"; warns=$((warns + 1)); }

[ -f "$CFG" ] || { echo "错误: 找不到 ${CFG}, 请先运行 make defconfig" >&2; exit 1; }
grep -q '^CONFIG_TARGET_x86_64=y$' "$CFG" || { echo "错误: 目标不是 x86_64" >&2; exit 1; }

# 1. 禁止出现的包 (=y 或 =m 都算)
forbidden=(
  '^CONFIG_PACKAGE_(firewall|ipset|nat6|kmod-nf-ipt6?)=[ym]$'
  '^CONFIG_PACKAGE_(iptables|ip6tables|xtables|ebtables|arptables)[A-Za-z0-9_-]*=[ym]$'
  '^CONFIG_PACKAGE_kmod-(ipt|ip6t)-[A-Za-z0-9_-]*=[ym]$'
  '^CONFIG_PACKAGE_(miniupnpd[A-Za-z0-9_-]*|luci-app-upnp|luci-i18n-upnp[A-Za-z0-9_-]*)=[ym]$'
  '^CONFIG_PACKAGE_(kmod-shortcut-fe[A-Za-z0-9_-]*|shortcut-fe[A-Za-z0-9_-]*|kmod-fast-classifier|natflow[A-Za-z0-9_-]*)=[ym]$'
  '^CONFIG_PACKAGE_(wpad[A-Za-z0-9_-]*|hostapd[A-Za-z0-9_-]*|wpa-supplicant[A-Za-z0-9_-]*|kmod-cfg80211|kmod-mac80211)=[ym]$'
  '^CONFIG_PACKAGE_(luci-app-passwall|luci-app-ssr-plus|luci-app-openclash|luci-app-homeproxy|luci-app-nikki|luci-app-dae|dae)=[ym]$'
  '^CONFIG_PACKAGE_kmod-r8125[A-Za-z0-9_-]*=[ym]$'
  '^CONFIG_PACKAGE_dnsmasq_full_ipset=[ym]$'
)
for pat in "${forbidden[@]}"; do
  if hits="$(grep -E "$pat" "$CFG")"; then
    err "发现不应存在的包:"
    echo "$hits" >&2
  fi
done

# 2. 必须出现的包
required=(firewall4 dnsmasq-full dnsmasq_full_nftset kmod-r8169 mwan3 luci-app-mwan3
          smartdns luci-app-smartdns adguardhome mosdns luci-app-mosdns
          luci-app-passwall2 kmod-nft-tproxy xray-core sing-box)
for p in "${required[@]}"; do
  grep -qE "^CONFIG_PACKAGE_${p}=y$" "$CFG" || err "缺少 ${p}"
done

# 3. passwall2: 任何带 iptables 字样的选项被启用都算失败(不依赖具体选项名)
if hits="$(grep -Ei '^CONFIG_PACKAGE_luci-app-passwall2_[A-Za-z0-9_-]*iptables[A-Za-z0-9_-]*=y$' "$CFG")"; then
  err "passwall2 启用了 iptables 相关选项:"
  echo "$hits" >&2
fi
echo "--- passwall2 相关配置(请人工确认使用 nftables 透明代理) ---"
grep -E '^CONFIG_PACKAGE_luci-app-passwall2' "$CFG" || true
echo "--- 最终会编进固件的代理相关组件(请人工确认) ---"
grep -E '^CONFIG_PACKAGE_(xray-core|sing-box|hysteria|naiveproxy|chinadns-ng|geoview|v2ray-geo[A-Za-z0-9_-]*|haproxy|shadowsocks[A-Za-z0-9_-]*|simple-obfs|v2ray-plugin|tcping|luci-compat)=' "$CFG" || true
echo "--- 引入 luci-compat 的第三方包(只查 package/new) ---"
grep -rl --include=Makefile 'luci-compat' package/new 2>/dev/null || echo "(package/new 下没有 Makefile 提到 luci-compat, 可能由官方 feeds 的包引入)"
echo "---"

# 4. 禁止关闭 CPU 漏洞缓解(只检查实际存在的目录)
dirs=()
for d in target/linux/x86 package/base-files files; do
  if [ -d "$d" ]; then dirs+=("$d"); fi
done
if [ "${#dirs[@]}" -gt 0 ] && grep -rIn 'mitigations=off' "${dirs[@]}"; then
  err "启动参数或预置文件中包含 mitigations=off"
fi

# 5. seed 与最终 .config 对照: 找出被 defconfig 悄悄丢掉的选项
dropped=0
revived=0
if [ -f "$SEED" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in
      CONFIG_*=y)
        if ! grep -qxF -- "$line" "$CFG"; then
          warn "seed 中的 ${line} 没有出现在最终 .config (选项名不对, 或依赖不满足)"
          dropped=$((dropped + 1))
        fi
        ;;
      "# CONFIG_"*" is not set")
        sym="${line#\# }"
        sym="${sym% is not set}"
        if grep -qxF -- "${sym}=y" "$CFG"; then
          warn "seed 中已关闭的 ${sym} 被依赖重新启用"
          revived=$((revived + 1))
        fi
        ;;
    esac
  done < "$SEED"
  echo "seed 对照: ${dropped} 项被丢弃, ${revived} 项被重新启用"
  if [ "$STRICT_SEED" = "1" ] && [ $((dropped + revived)) -gt 0 ]; then
    err "STRICT_SEED=1: seed 与最终配置不一致"
  fi
else
  warn "找不到 seed 文件 ${SEED}, 跳过 seed 对照"
fi

if [ "$fail" -ne 0 ]; then
  echo "校验失败: 最终配置不是纯 nftables 方案, 请检查依赖来源" >&2
  exit 1
fi
echo "校验通过: 纯 nftables 配置 (警告 ${warns} 条)"
exit 0
