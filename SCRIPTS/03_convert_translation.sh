#!/bin/bash
# 03_convert_translation.sh  (在 openwrt/ 目录内运行, 须在 02_prepare_package.sh 之后)
# 作用: 把第三方包里的 zh-cn 翻译改成官方 LuCI 使用的 zh_Hans
# 只处理 package/new(第三方包), 不触碰官方 feeds
set -euo pipefail

ROOT="package/new"
[ -d "$ROOT" ] || { echo "错误: 找不到 ${ROOT}, 请确认 02_prepare_package.sh 已运行" >&2; exit 1; }

# 1. 修正 .po 文件头里的语言标识
while IFS= read -r -d '' f; do
  if grep -q 'Language: zh_CN' "$f"; then
    sed -i 's/Language: zh_CN/Language: zh_Hans/' "$f"
    echo "修正语言头: $f"
  fi
done < <(find "$ROOT" -type f -name '*.po' -path '*zh-cn*' -print0)

# 2. 重命名文件名里带 zh-cn 的 .po 文件
while IFS= read -r -d '' f; do
  new="$(dirname "$f")/$(basename "$f" | sed 's/zh-cn/zh_Hans/g')"
  if [ -e "$new" ]; then
    echo "跳过(目标已存在): $f"
    continue
  fi
  mv -- "$f" "$new"
  echo "重命名文件: $f -> $new"
done < <(find "$ROOT" -type f -name '*zh-cn*.po' -print0)

# 3. 重命名名为 zh-cn 的目录(由深到浅)
while IFS= read -r -d '' d; do
  new="$(dirname "$d")/zh_Hans"
  if [ -e "$new" ]; then
    echo "警告: ${new} 已存在, 跳过 ${d}" >&2
    continue
  fi
  mv -- "$d" "$new"
  echo "重命名目录: $d -> $new"
done < <(find "$ROOT" -depth -type d -name 'zh-cn' -print0)

# 4. Makefile: zh-cn -> zh_Hans, 但 .lmo 输出名保持 zh-cn
while IFS= read -r -d '' mk; do
  if grep -qE 'zh-cn|zh_Hans\.lmo' "$mk"; then
    sed -i -e 's/zh-cn/zh_Hans/g' -e 's/zh_Hans\.lmo/zh-cn.lmo/g' "$mk"
    echo "修改 Makefile: $mk"
  fi
done < <(find "$ROOT" -type f -name Makefile -print0)

# 5. 第三方包放在 package/new 后, 相对路径的 include 要改成绝对路径
#    只改 include 行, 不动文件里其他内容
while IFS= read -r -d '' mk; do
  sed -i -E \
    -e 's#^(include[[:space:]]+)\.\./\.\./lang/#\1$(TOPDIR)/feeds/packages/lang/#' \
    -e 's#^(include[[:space:]]+)\.\./\.\./luci\.mk#\1$(TOPDIR)/feeds/luci/luci.mk#' \
    "$mk"
done < <(find "$ROOT" -type f -name Makefile -print0)

# 6. 提示: 第三方源码里预编译的 .lmo 是二进制文件, 无法审计, 发现就提醒
if find "$ROOT" -type f -name '*.lmo' -print -quit | grep -q .; then
  echo "警告: 第三方包中含有预编译 .lmo 二进制文件, 建议确认来源:" >&2
  find "$ROOT" -type f -name '*.lmo' >&2
fi

exit 0
