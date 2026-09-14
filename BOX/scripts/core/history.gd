class_name ActionHistory
extends RefCounted

## 回退检查点只保存“需要回退”的推动前状态。
var checkpoints: Array[Dictionary] = []
## 每次成功推动都进入日志，即使它与上一推动合并、不产生新检查点。
var push_log: Array[Dictionary] = []

func clear() -> void:
    checkpoints.clear()
    push_log.clear()

func push(state: BoardState) -> void:
    # 保留旧的通用快照接口，供规则夹具和未来非推动检查点使用。
    checkpoints.append({"state": state.duplicate_state(), "push_log_size": -1})

func record_push(state: BoardState, push_info: Dictionary) -> void:
    var needs_checkpoint := true
    if not push_log.is_empty():
        var previous: Dictionary = push_log.back()
        var same_entity := str(previous.get("entity_id", "")) == str(push_info.get("entity_id", ""))
        var same_direction := str(previous.get("direction", "")) == str(push_info.get("direction", ""))
        var special := bool(push_info.get("special", false))
        needs_checkpoint = special or not same_entity or not same_direction
    if needs_checkpoint:
        checkpoints.append({
            "state": state.duplicate_state(),
            "push_log_size": push_log.size()
        })
    push_log.append(push_info.duplicate(true))

func record_reflection(state: BoardState, reflection_info: Dictionary = {}) -> void:
    # 镜面反射是独立操作，即使没有推动箱子也必须进入撤回列表。
    checkpoints.append({
        "state": state.duplicate_state(),
        "push_log_size": push_log.size(),
        "kind": "reflection",
        "info": reflection_info.duplicate(true)
    })

func can_undo() -> bool:
    return not checkpoints.is_empty()

func pop() -> BoardState:
    if checkpoints.is_empty():
        return null
    var checkpoint: Dictionary = checkpoints.pop_back()
    var push_log_size := int(checkpoint.get("push_log_size", -1))
    if push_log_size >= 0 and push_log_size <= push_log.size():
        push_log.resize(push_log_size)
    var restored: BoardState = checkpoint.get("state")
    return restored

func size() -> int:
    return checkpoints.size()
