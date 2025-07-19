# Arsenal Operations Inventory

## Existing Operations

### Process Operations
- ✅ kill_process
- ✅ list_processes  
- ✅ get_process_info
- ✅ restart_process
- ✅ trace_process
- ✅ send_message

### Supervisor Operations  
- ✅ list_supervisors

### Sandbox Operations
- ✅ create_sandbox
- ✅ destroy_sandbox
- ✅ list_sandboxes
- ✅ get_sandbox_info
- ✅ restart_sandbox
- ✅ hot_reload_sandbox

### Analytics
- ✅ Arsenal.AnalyticsServer (not an operation, but provides analytics infrastructure)

## Missing Operations (Per Tasks.md)

### Phase 2.1: Basic Process Management
- ❌ start_process (not found in codebase)

### Phase 2.2: Advanced Process Control  
- ❌ suspend_process
- ❌ resume_process
- ❌ migrate_process

### Phase 2.3: Process Monitoring
- ❌ monitor_process
- ❌ get_process_tree

### Phase 3: Supervisor Operations
- ❌ start_supervisor
- ❌ stop_supervisor
- ❌ which_children
- ❌ restart_child
- ❌ add_child
- ❌ delete_child
- ❌ change_strategy
- ❌ supervisor_stats

### Phase 5: Distributed Operations
- ❌ cluster_health
- ❌ cluster_topology
- ❌ node_info
- ❌ connect_node
- ❌ disconnect_node
- ❌ remote_execute (or rpc_call)

## Next Implementation Priority

Based on the task breakdown and current status:

1. **Complete Phase 2.2**: suspend_process, resume_process
2. **Complete Phase 2.3**: monitor_process, get_process_tree  
3. **Start Phase 3**: Basic supervisor operations (start_supervisor, stop_supervisor, which_children, restart_child)
4. **Phase 5**: Distributed operations for cluster management

The foundation is solid with the Arsenal.Operation behaviour and Registry in place. All new operations should follow the established patterns.