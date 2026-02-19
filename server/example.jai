// codex resume 019c6dcf-c619-7c50-ba28-26b6b1fbd995
#import,file "./module.jai";
#load "shader_adapter.jai";

j_ctx: *#Context;
quit_requested := false;
shader_compile_in_progress := false;

File_Handler_Ctx :: struct {
  file_path: string;
  mime_type: string;
}

start_server :: () -> bool {
  callbacks: mg_callbacks;
  init_options := cstr_options(
    "enable_directory_listing", "no",
    "static_file_max_age", "0",
  );
  userdata: *void = null;
  init_data := mg_init_data.{
    callbacks = *callbacks,
    user_data = userdata,
    configuration_options = init_options,
  };
  start_error: mg_error_data;
  ctx := mg_start2(*init_data, *start_error);
  if ctx == null {
    log_error("mg_start failed");
    using start_error;
    if code {
      error_code := cast(MG_ERROR_DATA_CODE)code;
      log_error("%", error_code);
    }
    if text != null {
      log_error("%", to_string(text, cast(s64)text_buffer_size));
    }
    return false;
  }
  defer mg_stop(ctx);
  
  file_handler :: (conn: *mg_connection, cbdata: *void) -> s32 #c_call {
    using file_ctx := cast(*File_Handler_Ctx)cbdata;
    push_context j_ctx {
      auto_release_temp();
      no_cache_headers := "Cache-Control: no-store\r\nPragma: no-cache\r\n";
      if mime_type.count > 0 {
        mg_send_mime_file2(conn, temp_c_string(file_path), temp_c_string(mime_type), temp_c_string(no_cache_headers));
      } else {
        mg_send_file(conn, temp_c_string(file_path));
      }
    }
   	return 1;
  }
  
  quit_handler :: (conn: *mg_connection, cbdata: *void) -> s32 #c_call {
    // TODO: atomic?
    quit_requested = true;
    mg_printf_CFormat(conn, "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nConnection: close\r\n\r\nbye\n");
    return 1;
  }

  shader_handler :: (conn: *mg_connection, cbdata: *void) -> s32 #c_call {
    request_info := mg_get_request_info(conn);
    if request_info == null {
      mg_send_http_error_CFormat(conn, 500, "%s", "Internal Server Error");
      return 1;
    }

    method := request_info.request_method;
    if method == null || method[0] != #char "P" || method[1] != #char "O" || method[2] != #char "S" || method[3] != #char "T" || method[4] != 0 {
      mg_send_http_error_CFormat(conn, 405, "%s", "Method Not Allowed");
      return 1;
    }

    if request_info.content_length <= 0 {
      mg_send_http_error_CFormat(conn, 400, "%s", "Expected x-www-form-urlencoded body");
      return 1;
    }

    if request_info.content_length > 1024 * 1024 {
      mg_send_http_error_CFormat(conn, 413, "%s", "Request body too large");
      return 1;
    }

    backend: [64] u8;
    shader: [65536] u8;
    backend[0] = 0;
    shader[0] = 0;
    shader_len: s32 = 0;

    push_context j_ctx {
      auto_release_temp();

      body_capacity := cast(s64) request_info.content_length + 1;
      body := NewArray(body_capacity, u8);
      if !body.data {
        mg_send_http_error(conn, 500, "Could not allocate request buffer");
        return 1;
      }

      bytes_read_total: s64 = 0;
      while bytes_read_total < request_info.content_length {
        bytes_left := request_info.content_length - bytes_read_total;
        n := mg_read(conn, body.data + bytes_read_total, cast(u64) bytes_left);
        if n <= 0 break;
        bytes_read_total += cast(s64) n;
      }

      if bytes_read_total != request_info.content_length {
        mg_send_http_error(conn, 400, "Could not read full request body");
        return 1;
      }

      body[bytes_read_total] = 0;

      shader_len = mg_get_var(body.data, cast(u64) bytes_read_total, temp_c_string("shader"), shader.data, cast(u64) shader.count);
      if shader_len < 0 {
        mg_send_http_error(conn, 400, "Missing 'shader' form field");
        return 1;
      }

      backend_len := mg_get_var(body.data, cast(u64) bytes_read_total, temp_c_string("backend"), backend.data, cast(u64) backend.count);
      if backend_len < 0 {
        backend[0] = #char "m"; backend[1] = #char "e"; backend[2] = #char "t"; backend[3] = #char "a"; backend[4] = #char "l"; backend[5] = 0;
      }
    }

    if c_style_strlen(backend.data) != 5
      || backend[0] != #char "m" || backend[1] != #char "e" || backend[2] != #char "t" || backend[3] != #char "a" || backend[4] != #char "l" {
      mg_send_http_error_CFormat(conn, 400, "%s", "Only backend=metal is currently supported");
      return 1;
    }

    if shader_compile_in_progress {
      mg_send_http_error_CFormat(conn, 503, "%s", "A compile is already in progress");
      return 1;
    }

    shader_compile_in_progress = true;
    defer shader_compile_in_progress = false;

    push_context j_ctx {
      auto_release_temp();
      shader_text := to_string(shader.data, cast(s64) shader_len);
      result := compile_jai_to_metal(shader_text);
      if result.status != 200 {
        mg_send_http_error(conn, result.status, result.body);
        return 1;
      }

      mg_printf(conn, "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n");
      mg_printf(conn, result.body);
    }

    return 1;
  }
  
  jai_context := context;
  j_ctx = *jai_context;
  
  index_handler_ctx := File_Handler_Ctx.{ file_path="index.html", mime_type="text/html; charset=utf-8" };
  app_handler_ctx := File_Handler_Ctx.{ file_path="app.js", mime_type="text/javascript; charset=utf-8" };
  mg_set_request_handler(ctx, "/", file_handler, *index_handler_ctx);
  mg_set_request_handler(ctx, "/app.js", file_handler, *app_handler_ctx);
  mg_set_request_handler(ctx, "/shader", shader_handler, null);
  mg_set_request_handler(ctx, "/quit", quit_handler, null);
  
  // Wait for the client to request a quit.
  while !quit_requested {
    // server is running on bg thread.
    sleep_milliseconds(200);
  }
  
  log("Quit requested--done.");
  
  return true;
}

main :: () {
  if !compile_frontend() {
    exit(1);
  }

  if !start_server() {
    exit(1);
  }
}

#scope_file

#import "Basic";
Process :: #import "Process";
File :: #import "File";

compile_frontend :: () -> bool {
  result, output, error, timeout_reached := Process.run_command(
    "tsc",
    "--target", "ES2020",
    "--module", "ES2020",
    "--lib", "ES2020,DOM",
    "--strict",
    "--skipLibCheck",
    "app.ts",
    capture_and_return_output=true
  );
  if timeout_reached {
    log_error("TypeScript compile timed out.");
    return false;
  }
  if result.type == .FAILED_TO_LAUNCH {
    log_error("Failed to launch tsc. Is TypeScript installed and on PATH?");
    return false;
  }
  if result.type != .EXITED || result.exit_code != 0 {
    log_error("TypeScript compile failed (exit code %).", result.exit_code);
    if output.count > 0 log_error("%", output);
    if error.count > 0 log_error("%", error);
    return false;
  }
  return true;
}

cstr_options :: (strs: ..string) -> **u8 {
  assert(strs.count % 2 == 0, "Must have an even number of options");
  opts: [..]*u8;
  idx := 0;
  while idx < strs.count {
    array_add(*opts, to_c_string(strs[idx]), to_c_string(strs[idx + 1]));
    idx += 2;
  }
  array_add(*opts, null);
  return opts.data;
}
