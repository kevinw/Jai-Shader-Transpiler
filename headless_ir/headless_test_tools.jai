#import "Basic";

fail :: (message: string, args: .. Any) {
  log_error(message, ..args);
  exit(1);
}

check_contains :: (source: string, pattern: string, where: string) {
  ok, _ := contains(source, pattern);
  if !ok fail("Expected '%' in %", pattern, where);
}

check_occurs_once :: (source: string, pattern: string, where: string) {
  search: string = source;
  found_count: s64 = 0;
  while true {
    index := find_index_from_left(search, pattern);
    if index == -1 break;
    found_count += 1;
    next_start := index + pattern.count;
    if next_start >= search.count break;
    search.data += next_start;
    search.count -= next_start;
  }

  if found_count != 1 fail("Expected '%' exactly once in %, found % occurrences", pattern, where, found_count);
}
