#!/bin/bash
# 02_prepare_package.sh
# 在 openwrt/ 源码目录内运行(01_get_ready.sh 之后)
# 原则: 官方 25.12 源码 + 少量固定 commit 的第三方包, 不打内核或防火墙补丁
set -euo pipefail

SUPPORTED_KERNEL="6.12"

# 第三方包: 必须填完整的 40 位 commit, 留空会中止(fail closed)
# 获取方法: git ls-remote <仓库地址> <分支或HEAD>
MWAN3_REPO="https://github.com/dl12345/mwan3.git"
MWAN3_COMMIT="${MWAN3_COMMIT:-}"
LUCI_MWAN3_REPO="https://github.com/dl12345/luci-app-mwan3.git"
LUCI_MWAN3_COMMIT="${LUCI_MWAN3_COMMIT:-}"
PW2_REPO="https://github.com/xiaorouji/openwrt-passwall2.git"
PW2_COMMIT="${PW2_COMMIT:-}"
PW_PKGS_REPO="https://github.com/xiaorouji/openwrt-passwall-packages.git"
PW_PKGS_COMMIT="${PW_PKGS_COMMIT:-}"
MOSDNS_REPO="https://github.com/sbwml/luci-app-mosdns.git"
MOSDNS_COMMIT="${MOSDNS_COMMIT:-}"

summary() { [ -n "${GITHUB_STEP_SUMMARY:-}" ] && echo "$*" >> "$GITHUB_STEP_SUMMARY" || true; }

# 按完整 commit 拉取并校验
clone_pinned() {
  local url="$1" commit="$2" dir="$3" actual
  if ! [[ "$commit" =~ ^[0-9a-f]{40}$ ]]; then
    echo "错误: ${dir} 的 commit 必须是 40 位十六进制, 当前值: '${commit}'" >&2
    exit 1
  fi
  rm -rf "$dir"; mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" remote add origin "$url"
  git -C "$dir" fetch -q --depth 1 origin "$commit"
  git -C "$dir" checkout -q FETCH_HEAD
  actual="$(git -C "$dir" rev-parse HEAD)"
  if [ "$actual" != "$commit" ]; then
    echo "错误: ${dir} commit 不匹配 (期望 ${commit}, 实际 ${actual})" >&2
    exit 1
  fi
  rm -rf "$dir/.git"
  echo "已固定 ${url} @ ${actual}"
  summary "- ${url} @ ${actual}"
}

# 第三方包同名时, 删除官方 feeds 中的同名包, 并打印出来便于审计
dedupe_feeds() {
  local root="$1" mk name p
  while IFS= read -r mk; do
    name="$(basename "$(dirname "$mk")")"
    for p in feeds/*/*/"$name"; do
      if [ -e "$p" ]; then
        echo "覆盖官方 feed 包: $p"
        rm -rf "$p"
      fi
    done
  done < <(find "$root" -maxdepth 3 -name Makefile)
}

### 1. 校验内核版本(x86) ###
current_version="$(sed -n 's/^KERNEL_PATCHVER:=//p' ./target/linux/x86/Makefile)"
if [ -z "$current_version" ]; then
  echo "错误: 无法从 target/linux/x86/Makefile 读取 KERNEL_PATCHVER" >&2
  exit 1
fi
if [ "$current_version" != "$SUPPORTED_KERNEL" ]; then
  echo "错误: 内核版本为 ${current_version}, 预期 ${SUPPORTED_KERNEL}" >&2
  exit 1
fi
export KERNEL_VERSION="$SUPPORTED_KERNEL"
if [ -n "${GITHUB_ENV:-}" ]; then
  echo "KERNEL_VERSION=${SUPPORTED_KERNEL}" >> "$GITHUB_ENV"
fi

### 2. 更新官方 feeds 并记录各 feed 的 commit ###
./scripts/feeds update -a
summary "### 官方 feeds"
for d in feeds/*/; do
  if [ -d "${d}.git" ]; then
    echo "$(basename "$d"): $(git -C "$d" rev-parse HEAD)"
    summary "- $(basename "$d"): $(git -C "$d" rev-parse HEAD)"
  fi
done

### 3. 第三方包(固定 commit) ###
summary "### 第三方包"
mkdir -p package/new
clone_pinned "$MWAN3_REPO"       "$MWAN3_COMMIT"       package/new/mwan3
clone_pinned "$LUCI_MWAN3_REPO"  "$LUCI_MWAN3_COMMIT"  package/new/luci-app-mwan3
clone_pinned "$PW2_REPO"         "$PW2_COMMIT"         package/new/passwall2
clone_pinned "$PW_PKGS_REPO"     "$PW_PKGS_COMMIT"     package/new/passwall-packages
clone_pinned "$MOSDNS_REPO"      "$MOSDNS_COMMIT"      package/new/mosdns
for r in mwan3 luci-app-mwan3 passwall2 passwall-packages mosdns; do
  dedupe_feeds "package/new/$r"
done

### 4. 安装 feeds ###
./scripts/feeds install -a

### 5. 检查必需的包是否都存在(缺任何一个就中止) ###
missing=0
for p in smartdns luci-app-smartdns adguardhome mwan3 luci-app-mwan3 \
         luci-app-passwall2 mosdns luci-app-mosdns r8125; do
  if [ -z "$(find feeds package/new -maxdepth 4 -type d -name "$p" -print -quit)" ]; then
    echo "错误: 找不到包 ${p}" >&2
    missing=1
  fi
done
[ "$missing" = 0 ] || exit 1

rm -f .config
exit 0
