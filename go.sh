#!/bin/bash
# =============================================================
#  统信UOS 批量加密压缩工具（文件夹↔密码 一一对应版）
#  每个文件夹使用密码列表中"它自己那一行"的专属密码。
# =============================================================

# ---------- 1. 配置区（按需修改）----------
# 待压缩的文件夹所在目录（本脚本同级的"待压缩文件夹"）
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)/待压缩文件夹"
# 压缩包输出目录
OUTPUT_DIR="$(cd "$(dirname "$0")" && pwd)/打包结果"
# 密码列表文件（格式见下）
PASSWORD_FILE="$(cd "$(dirname "$0")" && pwd)/密码列表.txt"

# 压缩工具：auto（自动选7z优先）| 7z | zip
TOOL="auto"
# 密码列表里"找不到对应文件夹密码"时是否跳过而非中断：yes / no
SKIP_ON_MISSING="yes"

# ---------- 2. 密码列表格式说明 ----------
#   每行：  文件夹名称：密码
#   例如：  财务资料：Admin#2026
#   规则：
#     - 用冒号分隔，全角"："或 ASCII":"均可，冒号前后允许空格；
#     - 井号(#)开头整行视为注释；空行忽略；
#     - 兼容 Windows 记事本保存的 UTF-8 BOM（会自动剔除第一个 BOM）。

# ---------- 3. 环境检查 ----------
check_tool() {
  if command -v 7z >/dev/null 2>&1; then echo 7z
  elif command -v 7za >/dev/null 2>&1; then echo 7z
  elif command -v zip >/dev/null 2>&1; then echo zip
  else echo none; fi
}
if [ "$TOOL" = "auto" ]; then TOOL="$(check_tool)"; fi
if [ "$TOOL" = "none" ]; then
  echo "错误：未找到 7z 或 zip。请先安装： sudo apt install p7zip-full  或  sudo apt install zip"
  exit 1
fi

if [ ! -f "$PASSWORD_FILE" ]; then
  echo "错误：找不到密码列表文件：$PASSWORD_FILE"
  exit 1
fi
if [ ! -d "$SOURCE_DIR" ]; then
  echo "错误：找不到待压缩文件夹目录：$SOURCE_DIR"
  exit 1
fi
mkdir -p "$OUTPUT_DIR" || { echo "错误：无法创建输出目录"; exit 1; }

# ---------- 4. 读取密码映射 ----------
declare -A PASSMAP
COUNT=0
while IFS= read -r line; do
  # 去除首个 BOM
  line="${line#$'\xEF\xBB\xBF'}"
  # 去掉首尾空白
  line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  # 跳过空行与注释
  [ -z "$line" ] && continue
  case "$line" in \#*) continue ;; esac
  # 全角冒号统一为 ASCII 冒号，再按第一个冒号切分
  line="${line//：/:}"
  name="${line%%:*}"
  pw="${line#*:}"
  name="$(printf '%s' "$name" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  pw="$(printf '%s' "$pw" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [ -z "$name" ] && continue
  PASSMAP["$name"]="$pw"
  COUNT=$((COUNT+1))
done < "$PASSWORD_FILE"

if [ "$COUNT" -eq 0 ]; then
  echo "错误：密码列表为空或格式不正确。正确格式示例：  财务资料：Admin#2026"
  exit 1
fi
echo "[完成] 共读取到 $COUNT 条文件夹密码。"

# ---------- 5. 逐个文件夹压缩 ----------
LOG="$OUTPUT_DIR/压缩日志.txt"
{
  echo "批量压缩日志  $(date '+%Y-%m-%d %H:%M:%S')"
  echo "加密方式：$TOOL   密码映射条数：$COUNT"
  echo "--------------------------------------------"
} > "$LOG"

SUCCESS=0; FAIL=0; SKIP=0
shopt -s nullglob
for dir in "$SOURCE_DIR"/*/; do
  name="$(basename "${dir%/}")"
  if [ -z "${PASSMAP[$name]+x}" ]; then
    if [ "$SKIP_ON_MISSING" = "yes" ]; then
      echo "[警告] 文件夹「$name」在密码列表中无对应密码，已跳过。"
      echo "[跳过] $name -> 无对应密码" >> "$LOG"
      SKIP=$((SKIP+1)); continue
    else
      echo "[错误] 文件夹「$name」在密码列表中无对应密码，已终止。"
      echo "[失败] $name -> 无对应密码" >> "$LOG"
      FAIL=$((FAIL+1)); break
    fi
  fi
  pw="${PASSMAP[$name]}"
  out="$OUTPUT_DIR/$name.7z"
  [ "$TOOL" = "zip" ] && out="$OUTPUT_DIR/$name.zip"
  if [ "$TOOL" = "7z" ]; then
    7z a -t7z -mhe=on -p"$pw" -y "$out" "$dir" >/dev/null 2>&1
  else
    zip -r -P "$pw" "$out" "$name" >/dev/null 2>&1
  fi
  if [ $? -eq 0 ] && [ -f "$out" ]; then
    echo "[完成] $name 已压缩（密码: $pw）"
    echo "[成功] $name -> $(basename "$out")  密码: $pw" >> "$LOG"
    SUCCESS=$((SUCCESS+1))
  else
    echo "[错误] $name 压缩失败"
    echo "[失败] $name -> $(basename "$out")" >> "$LOG"
    FAIL=$((FAIL+1))
  fi
done
shopt -u nullglob

{
  echo "--------------------------------------------"
  echo "结束时间：$(date '+%Y-%m-%d %H:%M:%S')  成功：$SUCCESS  失败：$FAIL  跳过：$SKIP"
} >> "$LOG"

echo ""
echo "[完成] 全部完成！压缩包在：$OUTPUT_DIR"
echo "对应关系（含密码）已记录到：$LOG"
