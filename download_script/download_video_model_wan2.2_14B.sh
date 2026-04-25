#!/bin/bash
# =============================================================================
# Wan 2.2 模型下载脚本
# =============================================================================
# 功能：下载 Wan 2.2 T2V 5B 模型所需的三个核心文件
# 
# 使用方法：
#   ./download_wan2.2.sh        # 正常下载，已存在则跳过
#   ./download_wan2.2.sh -f     # 强制重新下载所有文件（忽略已存在检查）
#
# 作者：ComfyUI
# 参考文档：https://docs.comfy.org/tutorials/video/wan/wan2_2
# =============================================================================

# set -e  # 注释掉，遇到错误不立即退出，让脚本继续执行

# =============================================================================
# 颜色定义（用于终端输出）
# =============================================================================
RED='\033[0;31m'      # 红色 - 错误
GREEN='\033[0;32m'    # 绿色 - 成功
YELLOW='\033[0;33m'   # 黄色 - 警告/跳过
BLUE='\033[0;34m'     # 蓝色 - 信息
NC='\033[0m'          # 重置颜色

# =============================================================================
# 获取脚本所在目录的绝对路径
# =============================================================================
# 使用 BASH_SOURCE[0] 获取脚本路径，dirname 获取目录，cd 切换到该目录，pwd 获取绝对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 模型存放的基准目录：脚本目录的上一级目录下的 models 文件夹
BASE_DIR="$(dirname "$SCRIPT_DIR")/models"

# =============================================================================
# 定义下载配置（关联数组）
# 格式：key -> "URL|本地目录|文件名"
# =============================================================================
declare -A DOWNLOADS=(
    ["diffusion_models"]="https://modelscope.cn/models/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/master/split_files/diffusion_models/wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors|${BASE_DIR}/diffusion_models|wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors"
    ["diffusion_models"]="https://modelscope.cn/models/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/master/split_files/diffusion_models/wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors|${BASE_DIR}/diffusion_models|wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors"
    ["vae"]="https://modelscope.cn/models/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/master/split_files/vae/wan_2.1_vae.safetensors|${BASE_DIR}/vae|wan2.1_vae.safetensors"
    ["text_encoders"]="https://modelscope.cn/models/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/master/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors|${BASE_DIR}/text_encoders|umt5_xxl_fp8_e4m3fn_scaled.safetensors"
)

# =============================================================================
# curl 参数配置
# --connect-timeout: 连接超时时间（秒）
# --max-time: 最大传输时间（秒）
# -L: 跟随重定向
# --retry: 重试次数
# --retry-delay: 重试间隔（秒）
# =============================================================================
CURL_OPTS="--connect-timeout 30 --max-time 3600 -L --retry 3 --retry-delay 5"

# =============================================================================
# 解析命令行参数
# =============================================================================
FORCE_DOWNLOAD=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--force)
            # -f 参数：强制重新下载所有文件
            FORCE_DOWNLOAD=true
            shift
            ;;
        -h|--help)
            # 显示帮助信息
            echo "用法: $0 [选项]"
            echo ""
            echo "选项:"
            echo "  -f, --force    强制重新下载所有文件（忽略已存在检查）"
            echo "  -h, --help     显示此帮助信息"
            echo ""
            echo "示例:"
            echo "  $0             # 正常下载，已存在则跳过"
            echo "  $0 -f          # 强制下载所有文件"
            exit 0
            ;;
        *)
            echo -e "${RED}错误: 未知参数 '$1'${NC}"
            echo "使用 -h 查看帮助信息"
            exit 1
            ;;
    esac
done

# =============================================================================
# 辅助函数：格式化文件大小（字节 -> 人类可读）
# =============================================================================
format_size() {
    local bytes=$1
    if [[ -z "$bytes" || ! "$bytes" =~ ^[0-9]+$ ]]; then
        echo "未知大小"
        return
    fi
    if [[ $bytes -lt 1024 ]]; then
        echo "${bytes} B"
    elif [[ $bytes -lt 1048576 ]]; then
        echo "$(( bytes / 1024 )) KB"
    elif [[ $bytes -lt 1073741824 ]]; then
        echo "$(( bytes / 1048576 )) MB"
    else
        echo "$(( bytes / 1073741824 )) GB"
    fi
}

# =============================================================================
# 辅助函数：获取磁盘可用空间（字节）
# =============================================================================
get_available_space() {
    local dir="$1"
    # df 命令获取目录所在文件系统的可用空间，-B1 表示以字节为单位输出
    df -B1 "$dir" 2>/dev/null | tail -1 | awk '{print $4}'
}

# =============================================================================
# 辅助函数：检查文件是否存在且完整
# 返回：0=存在且完整，1=不存在或需要重新下载
# =============================================================================
check_file_exists() {
    local file_path="$1"
    # 检查文件是否存在且大小大于 0
    if [[ -f "$file_path" && -s "$file_path" ]]; then
        return 0
    else
        return 1
    fi
}

# =============================================================================
# 辅助函数：打印带颜色的消息
# =============================================================================
print_info() {
    echo -e "${BLUE}[信息]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

print_error() {
    echo -e "${RED}[错误]${NC} $1"
}

# =============================================================================
# 主流程：显示欢迎信息
# =============================================================================
echo ""
echo "=========================================="
echo "   Wan 2.2 模型下载脚本"
echo "=========================================="
echo ""
print_info "脚本目录: ${SCRIPT_DIR}"
print_info "模型目录: ${BASE_DIR}"
print_info "强制下载: ${FORCE_DOWNLOAD}"
echo ""

# =============================================================================
# 主流程：检查目标目录是否存在，不存在则创建
# =============================================================================
print_info "正在检查并创建目标目录..."
for key in "${!DOWNLOADS[@]}"; do
    # 解析配置：URL|目录|文件名
    IFS='|' read -r url target_dir filename <<< "${DOWNLOADS[$key]}"
    
    # 如果目录不存在，创建它（-p 参数会创建所有需要的父目录）
    if [[ ! -d "$target_dir" ]]; then
        mkdir -p "$target_dir"
        print_info "已创建目录: $target_dir"
    fi
done
print_success "目录检查完成"
echo ""

# =============================================================================
# 主流程：获取磁盘空间信息
# =============================================================================
print_info "正在检查磁盘空间..."
available_space=$(get_available_space "$BASE_DIR")
if [[ -n "$available_space" ]]; then
    print_info "当前磁盘可用空间: $(format_size $available_space)"
else
    print_warning "无法获取磁盘空间信息"
fi
echo ""

# =============================================================================
# 主流程：下载文件
# =============================================================================
print_info "开始下载文件..."
echo ""

downloaded_count=0
skipped_count=0
failed_count=0

for key in "${!DOWNLOADS[@]}"; do
    # 解析配置
    IFS='|' read -r url target_dir filename <<< "${DOWNLOADS[$key]}"
    target_file="${target_dir}/${filename}"
    
    echo "----------------------------------------"
    print_info "准备下载: ${key}"
    print_info "  URL: $url"
    print_info "  目标: $target_file"
    
    # 检查文件是否已存在
    if check_file_exists "$target_file"; then
        if [[ "$FORCE_DOWNLOAD" == "true" ]]; then
            print_warning "文件已存在，但使用 -f 参数强制重新下载"
        else
            print_success "文件已存在，跳过下载: $target_file"
            echo ""
            (( skipped_count++ ))
            continue
        fi
    fi
    
    # 执行下载
    print_info "开始下载 ${key}..."
    
    # 使用 curl 下载，--progress-bar 显示下载进度条
    # eval 用于展开 CURL_OPTS 变量
    if eval curl $CURL_OPTS --progress-bar -o "$target_file" "$url" 2>&1; then
        # 下载完成后检查文件是否完整
        if check_file_exists "$target_file"; then
            file_size=$(stat -c%s "$target_file" 2>/dev/null || stat -f%z "$target_file" 2>/dev/null)
            print_success "下载完成: ${key} ($(format_size $file_size))"
            (( downloaded_count++ ))
        else
            print_error "下载失败: ${key} - 文件不完整或为空"
            (( failed_count++ ))
        fi
    else
        download_status=$?
        print_error "下载失败: ${key} (curl 返回码: $download_status)"
        # 删除可能的不完整文件
        [[ -f "$target_file" ]] && rm -f "$target_file"
        (( failed_count++ ))
    fi
    
    echo ""
done

# =============================================================================
# 主流程：显示下载摘要
# =============================================================================
echo "=========================================="
echo "          下载摘要"
echo "=========================================="
print_info "本次下载文件数: $downloaded_count"
print_info "跳过文件数: $skipped_count"
print_info "失败文件数: $failed_count"
echo ""

if [[ $downloaded_count -gt 0 ]]; then
    print_success "所有指定文件下载完成！"
elif [[ $failed_count -gt 0 ]]; then
    print_error "部分文件下载失败，请检查网络连接后重试"
else
    print_info "所有文件已存在，无需下载。如需重新下载，请使用 -f 参数"
fi

echo ""
print_info "模型文件存放位置："
for key in "${!DOWNLOADS[@]}"; do
    IFS='|' read -r url target_dir filename <<< "${DOWNLOADS[$key]}"
    print_info "  - ${key}: ${target_dir}"
done
echo ""