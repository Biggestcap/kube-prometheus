#!/bin/bash

# 检查kubectl是否可用
if ! command -v kubectl &> /dev/null; then
    echo "错误: kubectl 命令未找到。请确保已安装kubectl并配置好Kubernetes集群访问。"
    exit 1
fi

# 检查是否能连接到Kubernetes集群
if ! kubectl cluster-info &> /dev/null; then
    echo "错误: 无法连接到Kubernetes集群。请检查集群配置和网络连接。"
    exit 1
fi

# 检查jq是否可用
if ! command -v jq &> /dev/null; then
    echo "错误: jq 命令未找到。请先安装jq (apt install jq 或 yum install jq)。"
    exit 1
fi

# 获取所有节点名称列表
NODE_NAMES=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')
if [ -z "$NODE_NAMES" ]; then
    echo "错误: 无法获取节点列表。"
    exit 1
fi

# 统计节点数量
NODE_COUNT=$(echo "$NODE_NAMES" | wc -w)
echo "发现 $NODE_COUNT 个节点，开始检查影响调度的污点..."
echo "========================================"

# 遍历所有节点并检查影响调度的污点
for NODE_NAME in $NODE_NAMES; do
    echo "处理节点: $NODE_NAME"
    echo "----------------------------------------"
    
    # 获取节点上所有污点
    TAINTS_JSON=$(kubectl get node "$NODE_NAME" -o jsonpath='{.spec.taints}')
    
    # 检查是否有污点
    if [ "$TAINTS_JSON" == "null" ] || [ -z "$TAINTS_JSON" ]; then
        echo "  该节点没有任何污点，无需处理。"
        echo
        continue
    fi
    
    # 检查是否有影响调度的污点(NoSchedule或NoExecute)
    # 使用jq提取污点的key、value和effect
    SCHEDULING_TAINTS=$(echo "$TAINTS_JSON" | jq -r '.[] | select(.effect == "NoSchedule" or .effect == "NoExecute") | .key + "|" + (.value // "") + "|" + .effect')
    
    if [ -z "$SCHEDULING_TAINTS" ] || [ "$SCHEDULING_TAINTS" == "null" ]; then
        echo "  该节点没有影响Pod调度的污点(NoSchedule/NoExecute)。"
        echo
        continue
    fi
    
    # 显示影响调度的污点
    echo "  发现影响Pod调度的污点:"
    echo "$SCHEDULING_TAINTS" | while IFS='|' read -r key value effect; do
        if [ -n "$value" ]; then
            echo "  - $key=$value:$effect"
        else
            echo "  - $key:$effect"
        fi
    done
    
    # 询问是否移除这些污点
    read -p "  是否要移除这些影响调度的污点? (y/N) " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # 逐个移除污点
        echo "$SCHEDULING_TAINTS" | while IFS='|' read -r key value effect; do
            # 构建污点字符串
            if [ -n "$value" ]; then
                taint_spec="$key=$value:$effect"
                remove_command="$key=$value:$effect-"
            else
                taint_spec="$key:$effect"
                remove_command="$key:$effect-"
            fi
            
            # 执行移除污点命令
            echo "  正在移除污点: $taint_spec"
            if kubectl taint nodes "$NODE_NAME" "$remove_command"; then
                echo "  成功移除污点: $taint_spec"
            else
                echo "  移除污点 $taint_spec 失败"
            fi
        done
    else
        echo "  已跳过移除操作。"
    fi
    
    echo
done

echo "所有节点处理完毕。"
exit 0
