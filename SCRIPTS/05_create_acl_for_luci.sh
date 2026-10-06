#!/bin/bash
# 05_create_acl_for_luci.sh  (在 openwrt/ 目录内运行, 须在 02_prepare_package.sh 之后)
# 原脚本会给缺少 ACL 的第三方 LuCI 应用自动生成"UCI 读写"授权, 相当于替第三方包授权
# 这里改成只检查和报告: 不生成、不修改任何文件
# 参数全部忽略, 以兼容 workflow 里现有的 "-a" 调用
set -euo pipefail

ROOT="package/new"
[ -d "$ROOT" ] || { echo "错误: 找不到 ${ROOT}, 请确认 02_prepare_package.sh 已运行" >&2; exit 1; }

found=0
missing=0
while IFS= read -r -d '' app; do
  found=$((found + 1))
  name="$(basename "$app")"
  if compgen -G "$app/root/usr/share/rpcd/acl.d/*.json" >/dev/null; then
    echo "OK    ${name}: 已带 ACL 文件"
  else
    echo "WARN  ${name}: 没有 ACL 文件 (${app})" >&2
    missing=$((missing + 1))
  fi
done < <(find "$ROOT" -type d -name 'luci-app-*' -print0)

echo "共检查 ${found} 个 LuCI 应用, 其中 ${missing} 个没有 ACL"
if [ "$found" -eq 0 ]; then
  echo "警告: 没有找到任何 luci-app-*, 可能是第三方包的目录结构与预期不同" >&2
fi
exit 0
