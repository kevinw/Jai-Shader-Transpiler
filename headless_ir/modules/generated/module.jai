#scope_export

#placeholder lookup_transpiled_impl;

lookup_transpiled :: (target_name: string, primary_name: string, secondary_name: string) -> string {
  return lookup_transpiled_impl(target_name, primary_name, secondary_name);
}
