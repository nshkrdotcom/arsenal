[
  # Mix tasks have special runtime behavior that dialyzer doesn't understand
  {"lib/mix/tasks/arsenal.gen.operation.ex", :callback_info_missing},
  {"lib/mix/tasks/arsenal.gen.operation.ex", :unknown_function, 240}, # EEx.eval_string
  
  # These pattern match warnings are due to dialyzer not understanding the macro expansion
  # in use Arsenal.Operation, compat: true
  {"lib/arsenal/operations/create_sandbox.ex", :pattern_match_cov},
  {"lib/arsenal/operations/destroy_sandbox.ex", :pattern_match_cov},
  {"lib/arsenal/operations/distributed/cluster_health.ex", :pattern_match_cov},
  {"lib/arsenal/operations/distributed/cluster_supervision_trees.ex", :pattern_match_cov},
  {"lib/arsenal/operations/distributed/cluster_topology.ex", :pattern_match_cov},
  {"lib/arsenal/operations/distributed/horde_registry_inspect.ex", :pattern_match_cov},
  {"lib/arsenal/operations/distributed/node_info.ex", :pattern_match_cov},
  {"lib/arsenal/operations/distributed/process_list.ex", :pattern_match_cov},
  {"lib/arsenal/operations/get_process_info.ex", :pattern_match_cov},
  {"lib/arsenal/operations/get_sandbox_info.ex", :pattern_match_cov},
  {"lib/arsenal/operations/hot_reload_sandbox.ex", :pattern_match_cov},
  {"lib/arsenal/operations/kill_process.ex", :pattern_match_cov},
  {"lib/arsenal/operations/list_sandboxes.ex", :pattern_match_cov},
  {"lib/arsenal/operations/list_supervisors.ex", :pattern_match_cov},
  {"lib/arsenal/operations/restart_sandbox.ex", :pattern_match_cov},
  {"lib/arsenal/operations/send_message.ex", :pattern_match_cov},
  {"lib/arsenal/operations/trace_process.ex", :pattern_match_cov}
]