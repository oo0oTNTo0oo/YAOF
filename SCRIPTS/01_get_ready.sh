#!/bin/bash
# 01_get_ready.sh
# 作用: 只拉取官方 OpenWrt 25.12 源码, 不混入任何第三方仓库
# 第三方包(mwan3-nft / passwall2 / mosdns 等)统一放到 02 里, 固定 commit 后再拉
set -euo pipefail

OPENWRT_REPO="https://github.com/openwrt/openwrt.git"
OPENWRT_SERIES="${OPENWRT_SERIES:-25.12}"

# 可选: 手动指定 tag 或分支(例如 v25.12.1), 以及期望的 commit 用于校验
OPENWRT_REF="${OPENWRT_REF:-}"
OPENWRT_COMMIT="${OPENWRT_COMMIT:-}"

# 未指定时, 自动取 25.12 系列最新的正式 tag(排除 -rc)
if [ -z "$OPENWRT_REF" ]; then
  OPENWRT_REF="$(git ls-remote --tags --refs "$OPENWRT_REPO" "v${OPENWRT_SERIES}.*" \
    | awk -F/ '{print $NF}' \
    | grep -Ev -- '-rc[0-9]+$' \
    | sort -V | tail -n1 || true)"
fi

if [ -z "$OPENWRT_REF" ]; then
  echo "错误: 没有找到 v${OPENWRT_SERIES}.* 的正式 tag, 请用 OPENWRT_REF 手动指定" >&2
  exit 1
fi

# 克隆官方源码(只用这一个仓库, 不做任何目录替换)
rm -rf openwrt
git clone --depth 1 --branch "$OPENWRT_REF" -- "$OPENWRT_REPO" openwrt

# 记录并校验 commit, 便于审计和复现
actual_commit="$(git -C openwrt rev-parse HEAD)"
if [ -n "$OPENWRT_COMMIT" ] && [ "$actual_commit" != "$OPENWRT_COMMIT" ]; then
  echo "错误: commit 不匹配, 期望 $OPENWRT_COMMIT, 实际 $actual_commit" >&2
  exit 1
fi
echo "OpenWrt ref=${OPENWRT_REF} commit=${actual_commit}"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  echo "OpenWrt 源码: ${OPENWRT_REF} (${actual_commit})" >> "$GITHUB_STEP_SUMMARY"
fi

# 检查 feeds 是否全部来自 OpenWrt 官方, 出现其他来源就中止
if grep -E '^src-' openwrt/feeds.conf.default \
   | grep -Ev 'git\.openwrt\.org|github\.com/openwrt/'; then
  echo "错误: feeds.conf.default 含有非官方源, 请检查" >&2
  exit 1
fi

exit 0
