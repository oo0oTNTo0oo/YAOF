#!/bin/bash
# 04_remove_upx.sh  (在 openwrt/ 目录内运行, 须在 02_prepare_package.sh 之后)
# 作用: 去掉第三方包里的 UPX 压缩步骤, 保持二进制未压缩, 便于审计
# 做法: 精确删除"纯 upx 命令行", 并只去掉依赖里的 upx/host 记号
set -euo pipefail

ROOT="package/new"
[ -d "$ROOT" ] || { echo "错误: 找不到 ${ROOT}, 请确认 02_prepare_package.sh 已运行" >&2; exit 1; }

while IFS= read -r -d '' mk; do
  grep -qi 'upx' "$mk" || continue
  echo "处理: $mk"

  # 1. 依赖里去掉 upx/host, 保留同一行的其他依赖
  sed -i -E 's#([[:space:]]|:=|\+=)upx/host#\1#g' "$mk"

  # 2. 删除"纯 upx 命令行"(以 Tab 开头的配方行); 遇到续行(反斜杠)则不动, 留给人工
  awk '
    {
      cur = $0
      if (cur ~ /^\t@?([^#]*\/)?upx[ \t]/ && cur !~ /\\[ \t]*$/ && prev !~ /\\[ \t]*$/) {
        next
      }
      print cur
      prev = cur
    }
  ' "$mk" > "${mk}.tmp"
  mv -- "${mk}.tmp" "$mk"

  # 3. 仍然残留 upx 的行: 打印出来, 不自动处理
  if grep -ni 'upx' "$mk"; then
    echo "警告: ${mk} 里仍有 upx 相关行(见上), 请确认是否需要人工处理" >&2
  fi
done < <(find "$ROOT" -type f -name Makefile -print0)

exit 0
