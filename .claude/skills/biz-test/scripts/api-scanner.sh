#!/bin/bash
# ============================================================
# biz-test API 接口扫描脚本
# 用法: ./api-scanner.sh [src_dir] [--json|--table|--markdown]
# 默认扫描 src/main/java/，输出 Markdown 表格
# 兼容 macOS (BSD grep) 和 Linux (GNU grep)
# ============================================================
set -e

SRC_DIR="${1:-src/main/java}"
FORMAT="${2:---markdown}"

if [ ! -d "$SRC_DIR" ]; then
  echo "{\"error\": \"Source directory '$SRC_DIR' not found\"}" >&2
  exit 1
fi

TMPFILE=$(mktemp /tmp/api-scan.XXXXXX)
trap "rm -f $TMPFILE" EXIT

# 扫描每个 Java 文件
find "$SRC_DIR" -name "*.java" -type f | while read -r file; do

  # 提取类级别路径: @RequestMapping("...") 或 @RequestMapping(path="...") 或 @RequestMapping(value="...")
  CLASS_PATH=$(grep -E '@RequestMapping' "$file" 2>/dev/null | head -1 | sed -n 's/.*@RequestMapping[[:space:]]*([[:space:]]*\(path\|value\)[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\2/p')
  if [ -z "$CLASS_PATH" ]; then
    CLASS_PATH=$(grep -E '@RequestMapping' "$file" 2>/dev/null | head -1 | sed -n 's/.*@RequestMapping[[:space:]]*([[:space:]]*"\([^"]*\)".*/\1/p')
  fi

  # 获取类名
  CLASS_NAME=$(grep -E 'class[[:space:]]+[A-Z][a-zA-Z0-9]*' "$file" 2>/dev/null | head -1 | sed -E 's/.*class[[:space:]]+//;s/[[:space:]].*//')

  # 检查是否是 Controller
  IS_CTRL=$(grep -cE '@RestController|@Controller' "$file" 2>/dev/null || echo 0)

  # 提取方法级别注解
  grep -nE '@(GetMapping|PostMapping|PutMapping|DeleteMapping|PatchMapping|RequestMapping)' "$file" 2>/dev/null | while read -r line_info; do
    line_num=$(echo "$line_info" | cut -d: -f1)
    anno_line=$(echo "$line_info" | cut -d: -f2-)

    # 提取 HTTP 方法
    METHOD=$(echo "$anno_line" | sed -nE 's/.*@(Get|Post|Put|Delete|Patch|Request)Mapping.*/\1/p')
    [ "$METHOD" = "Get" ] && METHOD="GET"
    [ "$METHOD" = "Post" ] && METHOD="POST"
    [ "$METHOD" = "Put" ] && METHOD="PUT"
    [ "$METHOD" = "Delete" ] && METHOD="DELETE"
    [ "$METHOD" = "Patch" ] && METHOD="PATCH"
    [ "$METHOD" = "Request" ] && METHOD="*"

    # 提取路径: 先匹配 path="..."，再 value="..."，再直接 "..."
    PATH_VAL=$(echo "$anno_line" | sed -nE 's/.*path[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/p')
    if [ -z "$PATH_VAL" ]; then
      PATH_VAL=$(echo "$anno_line" | sed -nE 's/.*value[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/p')
    fi
    if [ -z "$PATH_VAL" ]; then
      PATH_VAL=$(echo "$anno_line" | sed -nE 's/.*@[A-Za-z]+Mapping[[:space:]]*\([[:space:]]*"([^"]*)".*/\1/p')
    fi

    # 组合完整路径
    if [ -n "$CLASS_PATH" ] && [ -n "$PATH_VAL" ]; then
      FULL_PATH="${CLASS_PATH}${PATH_VAL}"
    elif [ -n "$PATH_VAL" ]; then
      FULL_PATH="$PATH_VAL"
    elif [ -n "$CLASS_PATH" ]; then
      FULL_PATH="$CLASS_PATH"
    else
      FULL_PATH="/"
    fi
    FULL_PATH=$(echo "$FULL_PATH" | sed 's#//*#/#g')

    # 标记类型
    if [ "$IS_CTRL" -gt 0 ] 2>/dev/null; then
      TYPE="controller"
    else
      TYPE="client"
    fi

    echo -e "${METHOD}\t${FULL_PATH}\t${CLASS_NAME}\t${TYPE}\t${file}:${line_num}" >> "$TMPFILE"
  done
done

# 去重
sort -u "$TMPFILE" -o "$TMPFILE" 2>/dev/null || true

TOTAL=$(wc -l < "$TMPFILE" | tr -d ' ')
[ -z "$TOTAL" ] && TOTAL=0

if [ "$TOTAL" -eq 0 ] 2>/dev/null; then
  echo "No API endpoints found in $SRC_DIR"
  exit 0
fi

case "$FORMAT" in
  --json)
    echo "["
    FIRST=true
    while IFS=$'\t' read -r method path class type location; do
      [ -z "$method" ] && continue
      $FIRST || echo ","
      FIRST=false
      printf '  {"method":"%s","path":"%s","class":"%s","type":"%s","file":"%s"}' "$method" "$path" "$class" "$type" "$location"
    done < "$TMPFILE"
    echo ""
    echo "]"
    ;;

  --table)
    printf "%-8s %-45s %-25s %-10s\n" "METHOD" "PATH" "CLASS" "TYPE"
    printf "%-8s %-45s %-25s %-10s\n" "------" "----" "-----" "----"
    while IFS=$'\t' read -r method path class type location; do
      [ -z "$method" ] && continue
      printf "%-8s %-45s %-25s %-10s\n" "$method" "$path" "$class" "$type"
    done < "$TMPFILE"
    ;;

  --markdown)
    echo "| 方法 | 路径 | 类 | 类型 |"
    echo "|------|------|-----|------|"
    while IFS=$'\t' read -r method path class type location; do
      [ -z "$method" ] && continue
      echo "| $method | \`$path\` | $class | $type |"
    done < "$TMPFILE"
    echo ""
    echo "> 共 $TOTAL 个接口端点"
    ;;

  *)
    while IFS=$'\t' read -r method path class type location; do
      [ -z "$method" ] && continue
      echo "$method $path  ($class)"
    done < "$TMPFILE"
    ;;
esac
