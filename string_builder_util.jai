
// Append a string with a newline to the String_Builder
a :: inline (sb: *String_Builder, str: string)              { append(sb, str); append(sb, "\n"); }

// Append a formatted string with tprint to the String_Builder
a :: inline (sb: *String_Builder, fmt: string, args: ..Any) { a(sb, tprint(fmt, ..args)); }

// Append a series of lines to the String_Builder
append_lines :: inline (sb: *String_Builder, lines: ..string) {
  for lines a(sb, it);
}

append_many :: inline (sb: *String_Builder, strs: ..string) {
  for strs append(sb, it);
}
