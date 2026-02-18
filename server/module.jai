//
// This file was auto-generated using the following command:
//
// jai generate.jai
//



CIVETWEB_VERSION :: "1.17";
CIVETWEB_VERSION_MAJOR :: 1;
CIVETWEB_VERSION_MINOR :: 17;
CIVETWEB_VERSION_PATCH :: 0;

MG_MAX_HEADERS :: 64;

mg_server_ports :: mg_server_port;

MG_MATCH_CONTEXT_MAX_MATCHES :: 32;

/* Init Features */
MG_FEATURES :: enum u32 {
    DEFAULT         :: 0;

    FILES           :: 1;

    TLS             :: 2;
    SSL             :: 2;

    CGI             :: 4;

    IPV6            :: 8;

    WEBSOCKET       :: 16;

    LUA             :: 32;

    SSJS            :: 64;

    CACHE           :: 128;

    STATS           :: 256;

    COMPRESSION     :: 512;

    HTTP2           :: 1024;

    X_DOMAIN_SOCKET :: 2048;

    ALL             :: 65535;
}

/* Initialize this library. This should be called once before any other
* function from this library. This function is not guaranteed to be
* thread safe.
* Parameters:
*   features: bit mask for features to be initialized.
*             Note: The TLS libraries (like OpenSSL) is initialized
*                   only if the MG_FEATURES_TLS bit is set.
*                   Currently the other bits do not influence
*                   initialization, but this may change in future
*                   versions.
* Return value:
*   initialized features
*   0: error
*/
mg_init_library :: (features: u32) -> u32 #foreign libcivetweb;

/* Un-initialize this library.
* Return value:
*   0: error
*/
mg_exit_library :: () -> u32 #foreign libcivetweb;

mg_context :: struct {}
mg_connection :: struct {}

mg_header :: struct {
    name:  *u8; /* HTTP header name */
    value: *u8; /* HTTP header value */
}

/* This structure contains information about the HTTP request. */
mg_request_info :: struct {
    request_method:               *u8; /* "GET", "POST", etc */
    /* URL-decoded URI (absolute or relative,
    * as in the request) */
    request_uri:                  *u8;

    /* URL-decoded URI (relative). Can be NULL
    * if the request_uri does not address a
    * resource at the server host. */
    local_uri_raw:                *u8;

    /* Same as local_uri_raw, however, cleaned
    * so a path like
    *   allowed_dir/../forbidden_file
    * is not possible. */
    local_uri:                    *u8;

    http_version:                 *u8; /* E.g. "1.0", "1.1" */
    /* URL part after '?', not including '?', or
    NULL */
    query_string:                 *u8;

    /* Authenticated user, or NULL if no auth
    used */
    remote_user:                  *u8;

    remote_addr:                  [48] u8; /* Client's IP address as a string. */
    server_addr:                  [48] u8; /* Server's IP address as a string. */

    /* Length (in bytes) of the request body,
    can be -1 if no length was given. */
    content_length:               s64;

    remote_port:                  s32; /* Port at client side */
    /* Port at server side (one of the listening
    ports) */
    server_port:                  s32;

    /* 1 if HTTPS or WS is used (SSL/TLS used),
    0 if not */
    is_ssl:                       s32;

    user_data:                    *void; /* User data pointer passed to mg_start() */
    conn_data:                    *void; /* Connection-specific user data */

    num_headers:                  s32; /* Number of HTTP headers */

    http_headers:                 [64] mg_header; /* Allocate maximum headers */

    client_cert:                  *mg_client_cert; /* Client certificate information */

    /* websocket subprotocol,
    * accepted during handshake */
    acceptedWebSocketSubprotocol: *u8;
}

/* This structure contains information about the HTTP request. */
/* This structure may be extended in future versions. */
mg_response_info :: struct {
    status_code:    s32; /* E.g. 200 */
    status_text:    *u8; /* E.g. "OK" */
    http_version:   *u8; /* E.g. "1.0", "1.1" */

    /* Length (in bytes) of the request body,
    can be -1 if no length was given. */
    content_length: s64;

    num_headers:    s32; /* Number of HTTP headers */

    http_headers:   [64] mg_header; /* Allocate maximum headers */
}

/* Client certificate information (part of mg_request_info) */
mg_client_cert :: struct {
    peer_cert: *void;
    subject:   *u8;
    issuer:    *u8;
    serial:    *u8;
    finger:    *u8;
}

/* This structure needs to be passed to mg_start(), to let civetweb know
which callbacks to invoke. For a detailed description, see
https://github.com/civetweb/civetweb/blob/master/docs/UserManual.md */
mg_callbacks :: struct {
    /* Called when civetweb has received new HTTP request.
    If the callback returns one, it must process the request
    by sending valid HTTP headers and a body. Civetweb will not do
    any further processing. Otherwise it must return zero.
    Note that since V1.7 the "begin_request" function is called
    before an authorization check. If an authorization check is
    required, use a request_handler instead.
    Return value:
    0: civetweb will process the request itself. In this case,
    the callback must not send any data to the client.
    1-999: callback already processed the request. Civetweb will
    not send any data after the callback returned. The
    return code is stored as a HTTP status code for the
    access log. */
    begin_request:           #type (unknown0: *mg_connection) -> s32 #c_call;

    /* Called when civetweb has finished processing request. */
    end_request:             #type (unknown0: *mg_connection, reply_status_code: s32) -> void #c_call;

    /* Called when civetweb is about to log a message. If callback returns
    non-zero, civetweb does not log anything. */
    log_message:             #type (unknown0: *mg_connection, message: *u8) -> s32 #c_call;

    /* Called when civetweb is about to log access. If callback returns
    non-zero, civetweb does not log anything. */
    log_access:              #type (unknown0: *mg_connection, message: *u8) -> s32 #c_call;

    /* Called when civetweb initializes SSL library.
    Parameters:
    ssl_ctx: SSL_CTX pointer.
    user_data: parameter user_data passed when starting the server.
    Return value:
    0: civetweb will set up the SSL certificate.
    1: civetweb assumes the callback already set up the certificate.
    -1: initializing ssl fails. */
    init_ssl:                #type (ssl_ctx: *void, user_data: *void) -> s32 #c_call;

    /* Called when civetweb initializes SSL library for a domain.
    Parameters:
    server_domain: authentication_domain from the domain config.
    ssl_ctx: SSL_CTX pointer.
    user_data: parameter user_data passed when starting the server.
    Return value:
    0: civetweb will set up the SSL certificate.
    1: civetweb assumes the callback already set up the certificate.
    -1: initializing ssl fails. */
    init_ssl_domain:         #type (server_domain: *u8, ssl_ctx: *void, user_data: *void) -> s32 #c_call;

    /* Called when civetweb is about to create or free a SSL_CTX.
    Parameters:
    ssl_ctx: SSL_CTX pointer. NULL at creation time, Not NULL when
    mg_context will be freed user_data: parameter user_data passed when starting
    the server. Return value: 0: civetweb will continue to create the context,
    just as if the callback would not be present. The value in *ssl_ctx when the
    function returns is ignored. 1: civetweb will copy the value from *ssl_ctx
    to the civetweb context and doesn't create its own. -1: initializing ssl
    fails.*/
    external_ssl_ctx:        #type (ssl_ctx: **void, user_data: *void) -> s32 #c_call;

    /* Called when civetweb is about to create or free a SSL_CTX for a domain.
    Parameters:
    server_domain: authentication_domain from the domain config.
    ssl_ctx: SSL_CTX pointer. NULL at creation time, Not NULL when
    mg_context will be freed user_data: parameter user_data passed when starting
    the server. Return value: 0: civetweb will continue to create the context,
    just as if the callback would not be present. The value in *ssl_ctx when the
    function returns is ignored. 1: civetweb will copy the value from *ssl_ctx
    to the civetweb context and doesn't create its own. -1: initializing ssl
    fails.*/
    external_ssl_ctx_domain: #type (server_domain: *u8, ssl_ctx: **void, user_data: *void) -> s32 #c_call;

    /* Called when civetweb is closing a connection.  The per-context mutex is
    locked when this is invoked.
    
    Websockets:
    Before mg_set_websocket_handler has been added, it was primarily useful
    for noting when a websocket is closing, and used to remove it from any
    application-maintained list of clients.
    Using this callback for websocket connections is deprecated: Use
    mg_set_websocket_handler instead.
    */
    connection_close:        #type (unknown0: *mg_connection) -> void #c_call;

    /* Called after civetweb has closed a connection.  The per-context mutex is
    locked when this is invoked.
    
    Connection specific data:
    If memory has been allocated for the connection specific user data
    (mg_request_info->conn_data, mg_get_user_connection_data),
    this is the last chance to free it.
    */
    connection_closed:       #type (unknown0: *mg_connection) -> void #c_call;

    /* init_lua is called when civetweb is about to serve Lua server page.
    exit_lua is called when the Lua processing is complete.
    Both will work only if Lua support is enabled.
    Parameters:
    conn: current connection.
    lua_context: "lua_State *" pointer.
    context_flags: context type information as bitmask:
    context_flags & 0x0F: (0-15) Lua environment type
    */
    init_lua:                #type (conn: *mg_connection, lua_context: *void, context_flags: u32) -> void #c_call;

    exit_lua:                #type (conn: *mg_connection, lua_context: *void, context_flags: u32) -> void #c_call;

    /* Called when civetweb is about to send HTTP error to the client.
    Implementing this callback allows to create custom error pages.
    Parameters:
    conn: current connection.
    status: HTTP error status code.
    errmsg: error message text.
    Return value:
    1: run civetweb error handler.
    0: callback already handled the error. */
    http_error:              #type (conn: *mg_connection, status: s32, errmsg: *u8) -> s32 #c_call;

    /* Called after civetweb context has been created, before requests
    are processed.
    Parameters:
    ctx: context handle */
    init_context:            #type (ctx: *mg_context) -> void #c_call;

    /* Called when civetweb context is deleted.
    Parameters:
    ctx: context handle */
    exit_context:            #type (ctx: *mg_context) -> void #c_call;

    /* Called when a new worker thread is initialized.
    * It is always called from the newly created thread and can be used to
    * initialize thread local storage data.
    * Parameters:
    *   ctx: context handle
    *   thread_type:
    *     0 indicates the master thread
    *     1 indicates a worker thread handling client connections
    *     2 indicates an internal helper thread (timer thread)
    * Return value:
    *   This function returns a user supplied pointer. The pointer is assigned
    *   to the thread and can be obtained from the mg_connection object using
    *   mg_get_thread_pointer in all server callbacks. Note: A connection and
    *   a thread are not directly related. Threads will serve several different
    *   connections, and data from a single connection may call different
    *   callbacks using different threads. The thread pointer can be obtained
    *   in a callback handler, but should not be stored beyond the scope of
    *   one call to one callback.
    */
    init_thread:             #type (ctx: *mg_context, thread_type: s32) -> *void #c_call;

    /* Called when a worker exits.
    * The parameters "ctx" and "thread_type" correspond to the "init_thread"
    * call. The  "thread_pointer" parameter is the value returned by
    * "init_thread".
    */
    exit_thread:             #type (ctx: *mg_context, thread_type: s32, thread_pointer: *void) -> void #c_call;

    /* Called when initializing a new connection object.
    * Can be used to initialize the connection specific user data
    * (mg_request_info->conn_data, mg_get_user_connection_data).
    * When the callback is called, it is not yet known if a
    * valid HTTP(S) request will be made.
    * Parameters:
    *   conn: not yet fully initialized connection object
    *   conn_data: output parameter, set to initialize the
    *              connection specific user data
    * Return value:
    *   must be 0
    *   Otherwise, the result is undefined
    */
    init_connection:         #type (conn: *mg_connection, conn_data: **void) -> s32 #c_call;
}

/* Start web server.

Parameters:
callbacks: mg_callbacks structure with user-defined callbacks.
options: NULL terminated list of option_name, option_value pairs that
specify Civetweb configuration parameters.

Side-effects: on UNIX, ignores SIGCHLD and SIGPIPE signals. If custom
processing is required for these, signal handlers must be set up
after calling mg_start().


Example:
const char *options[] = {
"document_root", "/var/www",
"listening_ports", "80,443s",
NULL
};
struct mg_context *ctx = mg_start(&my_func, NULL, options);

Refer to https://github.com/civetweb/civetweb/blob/master/docs/UserManual.md
for the list of valid option and their possible values.

Return:
web server context, or NULL on error. */
mg_start :: (callbacks: *mg_callbacks, user_data: *void, configuration_options: **u8) -> *mg_context #foreign libcivetweb;

/* Stop the web server.

Must be called last, when an application wants to stop the web server and
release all associated resources. This function blocks until all Civetweb
threads are stopped. Context pointer becomes invalid. */
mg_stop :: (unknown0: *mg_context) -> void #foreign libcivetweb;

/* Add an additional domain to an already running web server.
*
* Parameters:
*   ctx: Context handle of a server started by mg_start.
*   options: NULL terminated list of option_name, option_value pairs that
*            specify CivetWeb configuration parameters.
*
* Return:
*   < 0 in case of an error
*    -1 for a parameter error
*    -2 invalid options
*    -3 initializing SSL failed
*    -4 mandatory domain option missing
*    -5 duplicate domain
*    -6 out of memory
*   > 0 index / handle of a new domain
*/
mg_start_domain :: (ctx: *mg_context, configuration_options: **u8) -> s32 #foreign libcivetweb;

/* mg_request_handler

Called when a new request comes in.  This callback is URI based
and configured with mg_set_request_handler().

Parameters:
conn: current connection information.
cbdata: the callback data configured with mg_set_request_handler().
Returns:
0: the handler could not handle the request, so fall through.
1 - 999: the handler processed the request. The return code is
stored as a HTTP status code for the access log. */
mg_request_handler :: #type (conn: *mg_connection, cbdata: *void) -> s32 #c_call;

/* mg_set_request_handler

Sets or removes a URI mapping for a request handler.
This function waits until a removing/updating handler becomes unused, so
do not call from the handler itself.

URI's are ordered and prefixed URI's are supported. For example,
consider two URIs: /a/b and /a
/a   matches /a
/a/b matches /a/b
/a/c matches /a

Parameters:
ctx: server context
uri: the URI (exact or pattern) for the handler
handler: the callback handler to use when the URI is requested.
If NULL, an already registered handler for this URI will
be removed.
The URI used to remove a handler must match exactly the
one used to register it (not only a pattern match).
cbdata: the callback data to give to the handler when it is called. */
mg_set_request_handler :: (ctx: *mg_context, uri: *u8, handler: mg_request_handler, cbdata: *void) -> void #foreign libcivetweb;

/* Callback types for websocket handlers in C/C++.

mg_websocket_connect_handler
Is called when the client intends to establish a websocket connection,
before websocket handshake.
Return value:
0: civetweb proceeds with websocket handshake.
1: connection is closed immediately.

mg_websocket_ready_handler
Is called when websocket handshake is successfully completed, and
connection is ready for data exchange.

mg_websocket_data_handler
Is called when a data frame has been received from the client.
Parameters:
bits: first byte of the websocket frame, see websocket RFC at
http://tools.ietf.org/html/rfc6455, section 5.2
data, data_len: payload, with mask (if any) already applied.
Return value:
1: keep this websocket connection open.
0: close this websocket connection.

mg_connection_close_handler
Is called, when the connection is closed.*/
mg_websocket_connect_handler :: #type (unknown0: *mg_connection, unknown1: *void) -> s32 #c_call;

mg_websocket_ready_handler :: #type (unknown0: *mg_connection, unknown1: *void) -> void #c_call;
mg_websocket_data_handler :: #type (unknown0: *mg_connection, unknown1: s32, unknown2: *u8, unknown3: u64, unknown4: *void) -> s32 #c_call;

mg_websocket_close_handler :: #type (unknown0: *mg_connection, unknown1: *void) -> void #c_call;

/* struct mg_websocket_subprotocols
*
* List of accepted subprotocols
*/
mg_websocket_subprotocols :: struct {
    nb_subprotocols: s32;
    subprotocols:    **u8;
}

/* mg_set_websocket_handler

Set or remove handler functions for websocket connections.
This function works similar to mg_set_request_handler - see there. */
mg_set_websocket_handler :: (ctx: *mg_context, uri: *u8, connect_handler: mg_websocket_connect_handler, ready_handler: mg_websocket_ready_handler, data_handler: mg_websocket_data_handler, close_handler: mg_websocket_close_handler, cbdata: *void) -> void #foreign libcivetweb;

/* mg_set_websocket_handler

Set or remove handler functions for websocket connections.
This function works similar to mg_set_request_handler - see there. */
mg_set_websocket_handler_with_subprotocols :: (ctx: *mg_context, uri: *u8, subprotocols: *mg_websocket_subprotocols, connect_handler: mg_websocket_connect_handler, ready_handler: mg_websocket_ready_handler, data_handler: mg_websocket_data_handler, close_handler: mg_websocket_close_handler, cbdata: *void) -> void #foreign libcivetweb;

/* mg_authorization_handler

Callback function definition for mg_set_auth_handler

Parameters:
conn: current connection information.
cbdata: the callback data configured with mg_set_request_handler().
Returns:
0: access denied
1: access granted
*/
mg_authorization_handler :: #type (conn: *mg_connection, cbdata: *void) -> s32 #c_call;

/* mg_set_auth_handler

Sets or removes a URI mapping for an authorization handler.
This function works similar to mg_set_request_handler - see there. */
mg_set_auth_handler :: (ctx: *mg_context, uri: *u8, handler: mg_authorization_handler, cbdata: *void) -> void #foreign libcivetweb;

/* Get the value of particular configuration parameter.
The value returned is read-only. Civetweb does not allow changing
configuration at run time.
If given parameter name is not valid, NULL is returned. For valid
names, return value is guaranteed to be non-NULL. If parameter is not
set, zero-length string is returned. */
mg_get_option :: (ctx: *mg_context, name: *u8) -> *u8 #foreign libcivetweb;

/* Get context from connection. */
mg_get_context :: (conn: *mg_connection) -> *mg_context #foreign libcivetweb;

/* Get user data passed to mg_start from context. */
mg_get_user_data :: (ctx: *mg_context) -> *void #foreign libcivetweb;

/* Get user data passed to mg_start from connection. */
mg_get_user_context_data :: (conn: *mg_connection) -> *void #foreign libcivetweb;

/* Get user defined thread pointer for server threads (see init_thread). */
mg_get_thread_pointer :: (conn: *mg_connection) -> *void #foreign libcivetweb;

/* Set user data for the current connection. */
/* Note: CivetWeb callbacks use "struct mg_connection *conn" as input
when mg_read/mg_write callbacks are allowed in the callback,
while "const struct mg_connection *conn" is used as input in case
calling mg_read/mg_write is not allowed.
Setting the user connection data will modify the connection
object represented by mg_connection *, but it will not read from
or write to the connection. */
/* Note: An alternative is to use the init_connection callback
instead to initialize the user connection data pointer. It is
recommended to supply a pointer to some user defined data structure
as conn_data initializer in init_connection. In case it is required
to change some data after the init_connection call, store another
data pointer in the user defined data structure and modify that
pointer. In either case, after the init_connection callback, only
calls to mg_get_user_connection_data should be required. */
mg_set_user_connection_data :: (conn: *mg_connection, data: *void) -> void #foreign libcivetweb;

/* Get user data set for the current connection. */
mg_get_user_connection_data :: (conn: *mg_connection) -> *void #foreign libcivetweb;

/* Get a formatted link corresponding to the current request

Parameters:
conn: current connection information.
buf: string buffer (out)
buflen: length of the string buffer
Returns:
<0: error
>=0: ok */
mg_get_request_link :: (conn: *mg_connection, buf: *u8, buflen: u64) -> s32 #foreign libcivetweb;

mg_option :: struct {
    name:          *u8;
    type:          s32;
    default_value: *u8;
}

/* Configuration types */
MG_CONFIG_TYPE :: enum u32 {
    UNKNOWN          :: 0;
    NUMBER           :: 1;
    STRING           :: 2;
    FILE             :: 3;
    DIRECTORY        :: 4;
    BOOLEAN          :: 5;
    EXT_PATTERN      :: 6;
    STRING_LIST      :: 7;
    STRING_MULTILINE :: 8;
    YES_NO_OPTIONAL  :: 9;
}

/* Return array of struct mg_option, representing all valid configuration
options of civetweb.c.
The array is terminated by a NULL name option. */
mg_get_valid_options :: () -> *mg_option #foreign libcivetweb;

mg_server_port :: struct {
    protocol:    s32; /* 1 = IPv4, 2 = IPv6, 3 = both */
    port:        s32; /* port number */
    is_ssl:      s32; /* https port: 0 = no, 1 = yes */
    is_redirect: s32; /* redirect all requests: 0 = no, 1 = yes */
    is_optional: s32; /* optional: 0 = no, 1 = yes */
    is_bound:    s32; /* bound: 0 = no, 1 = yes, relevant for optional ports */
    _reserved3:  s32;
    _reserved4:  s32;
}

/* Get the list of ports that civetweb is listening on.
The parameter size is the size of the ports array in elements.
The caller is responsibility to allocate the required memory.
This function returns the number of struct mg_server_port elements
filled in, or <0 in case of an error. */
mg_get_server_ports :: (ctx: *mg_context, size: s32, ports: *mg_server_port) -> s32 #foreign libcivetweb;

/* Add, edit or delete the entry in the passwords file.
*
* This function allows an application to manipulate .htpasswd files on the
* fly by adding, deleting and changing user records. This is one of the
* several ways of implementing authentication on the server side. For another,
* cookie-based way please refer to the examples/chat in the source tree.
*
* Parameter:
*   passwords_file_name: Path and name of a file storing multiple passwords
*   realm: HTTP authentication realm (authentication domain) name
*   user: User name
*   password:
*     If password is not NULL, entry modified or added.
*     If password is NULL, entry is deleted.
*
*  Return:
*    1 on success, 0 on error.
*/
mg_modify_passwords_file :: (passwords_file_name: *u8, realm: *u8, user: *u8, password: *u8) -> s32 #foreign libcivetweb;

/* Same as mg_modify_passwords_file, but instead of the plain-text
* password, the HA1 hash is specified. The plain-text password is
* not made known to civetweb.
*
* The HA1 hash is the MD5 checksum of a "user:realm:password" string
* in lower-case hex format. For example, if the user name is "myuser",
* the realm is "myrealm", and the password is "secret", then the HA1 is
* e67fd3248b58975c3e89ff18ecb75e2f.
*/
mg_modify_passwords_file_ha1 :: (passwords_file_name: *u8, realm: *u8, user: *u8, ha1: *u8) -> s32 #foreign libcivetweb;

/* Return information associated with the request.
* Use this function to implement a server and get data about a request
* from a HTTP/HTTPS client.
* Note: Before CivetWeb 1.10, this function could be used to read
* a response from a server, when implementing a client, although the
* values were never returned in appropriate mg_request_info elements.
* It is strongly advised to use mg_get_response_info for clients.
*/
mg_get_request_info :: (unknown0: *mg_connection) -> *mg_request_info #foreign libcivetweb;

/* Return information associated with a HTTP/HTTPS response.
* Use this function in a client, to check the response from
* the server. */
mg_get_response_info :: (unknown0: *mg_connection) -> *mg_response_info #foreign libcivetweb;

/* Send data to the client.
Return:
0   when the connection has been closed
-1  on error
>0  number of bytes written on success */
mg_write :: (unknown0: *mg_connection, buf: *void, len: u64) -> s32 #foreign libcivetweb;

/* Blocks until unique access is obtained to this connection. Intended for use
with websockets only.
Invoke this before mg_write or mg_printf when communicating with a
websocket if your code has server-initiated communication as well as
communication in direct response to a message.
Do not acquire this lock while holding mg_lock_context(). */
mg_lock_connection :: (conn: *mg_connection) -> void #foreign libcivetweb;
mg_unlock_connection :: (conn: *mg_connection) -> void #foreign libcivetweb;

/* Lock server context.  This lock may be used to protect resources
that are shared between different connection/worker threads.
If the given context is not server, these functions do nothing. */
mg_lock_context :: (ctx: *mg_context) -> void #foreign libcivetweb;
mg_unlock_context :: (ctx: *mg_context) -> void #foreign libcivetweb;

/* WebSocket OpcCodes, from http://tools.ietf.org/html/rfc6455 */
MG_WEBSOCKET_OPCODE :: enum u32 {
    CONTINUATION     :: 0;
    TEXT             :: 1;
    BINARY           :: 2;
    CONNECTION_CLOSE :: 8;
    PING             :: 9;
    PONG             :: 10;
}

/* Send data to the client using printf() semantics.
Works exactly like mg_write(), but allows to do message formatting. */
mg_printf_CFormat :: (unknown0: *mg_connection, fmt: *u8, __args: ..Any) -> s32 #foreign libcivetweb "mg_printf";
mg_printf :: (unknown0: *mg_connection, fmt: string, __args: ..Any) -> s32 {
    push_allocator(temp);
    formatted_text_builder: String_Builder;
    print_to_builder(*formatted_text_builder, fmt, ..__args);
    append(*formatted_text_builder, "\0");
    formatted_text := builder_to_string(*formatted_text_builder);
    return mg_printf_CFormat(unknown0, "%s", formatted_text.data);
} @PrintLike

/* Send a part of the message body, if chunked transfer encoding is set.
* Only use this function after sending a complete HTTP request or response
* header with "Transfer-Encoding: chunked" set. */
mg_send_chunk :: (conn: *mg_connection, chunk: *u8, chunk_len: u32) -> s32 #foreign libcivetweb;

/* Send contents of the entire file together with HTTP headers.
* Parameters:
*   conn: Current connection information.
*   path: Full path to the file to send.
* This function has been superseded by mg_send_mime_file
*/
mg_send_file :: (conn: *mg_connection, path: *u8) -> void #foreign libcivetweb;

/* Send contents of the file without HTTP headers.
* The code must send a valid HTTP response header before using this function.
*
* Parameters:
*   conn: Current connection information.
*   path: Full path to the file to send.
*
* Return:
*   < 0   Error
*/
mg_send_file_body :: (conn: *mg_connection, path: *u8) -> s32 #foreign libcivetweb;

/* Send HTTP error reply. */
mg_send_http_error_CFormat :: (conn: *mg_connection, status_code: s32, fmt: *u8, __args: ..Any) -> s32 #foreign libcivetweb "mg_send_http_error";
mg_send_http_error :: (conn: *mg_connection, status_code: s32, fmt: string, __args: ..Any) -> s32 {
    push_allocator(temp);
    formatted_text_builder: String_Builder;
    print_to_builder(*formatted_text_builder, fmt, ..__args);
    append(*formatted_text_builder, "\0");
    formatted_text := builder_to_string(*formatted_text_builder);
    return mg_send_http_error_CFormat(conn, status_code, "%s", formatted_text.data);
} @PrintLike

/* Send "HTTP 200 OK" response header.
* After calling this function, use mg_write or mg_send_chunk to send the
* response body.
* Parameters:
*   conn: Current connection handle.
*   mime_type: Set Content-Type for the following content.
*   content_length: Size of the following content, if content_length >= 0.
*                   Will set transfer-encoding to chunked, if set to -1.
* Return:
*   < 0   Error
*/
mg_send_http_ok :: (conn: *mg_connection, mime_type: *u8, content_length: s64) -> s32 #foreign libcivetweb;

/* Send "HTTP 30x" redirect response.
* The response has content-size zero: do not send any body data after calling
* this function.
* Parameters:
*   conn: Current connection handle.
*   target_url: New location.
*   redirect_code: HTTP redirect type. Could be 301, 302, 303, 307, 308.
* Return:
*   < 0   Error (-1 send error, -2 parameter error)
*/
mg_send_http_redirect :: (conn: *mg_connection, target_url: *u8, redirect_code: s32) -> s32 #foreign libcivetweb;

/* Send HTTP digest access authentication request.
* Browsers will send a user name and password in their next request, showing
* an authentication dialog if the password is not stored.
* Parameters:
*   conn: Current connection handle.
*   realm: Authentication realm. If NULL is supplied, the sever domain
*          set in the authentication_domain configuration is used.
* Return:
*   < 0   Error
*/
mg_send_digest_access_authentication_request :: (conn: *mg_connection, realm: *u8) -> s32 #foreign libcivetweb;

/* Check if the current request has a valid authentication token set.
* A file is used to provide a list of valid user names, realms and
* password hashes. The file can be created and modified using the
* mg_modify_passwords_file API function.
* Parameters:
*   conn: Current connection handle.
*   realm: Authentication realm. If NULL is supplied, the sever domain
*          set in the authentication_domain configuration is used.
*   filename: Path and name of a file storing multiple password hashes.
* Return:
*   > 0   Valid authentication
*   0     Invalid authentication
*   < 0   Error (all values < 0 should be considered as invalid
*         authentication, future error codes will have negative
*         numbers)
*   -1    Parameter error
*   -2    File not found
*/
mg_check_digest_access_authentication :: (conn: *mg_connection, realm: *u8, filename: *u8) -> s32 #foreign libcivetweb;

/* Send contents of the entire file together with HTTP headers.
* Parameters:
*   conn: Current connection handle.
*   path: Full path to the file to send.
*   mime_type: Content-Type for file.  NULL will cause the type to be
*              looked up by the file extension.
*/
mg_send_mime_file :: (conn: *mg_connection, path: *u8, mime_type: *u8) -> void #foreign libcivetweb;

/* Send contents of the entire file together with HTTP headers.
Parameters:
conn: Current connection information.
path: Full path to the file to send.
mime_type: Content-Type for file.  NULL will cause the type to be
looked up by the file extension.
additional_headers: Additional custom header fields appended to the header.
Each header should start with an X-, to ensure it is
not included twice.
NULL does not append anything.
*/
mg_send_mime_file2 :: (conn: *mg_connection, path: *u8, mime_type: *u8, additional_headers: *u8) -> void #foreign libcivetweb;

/* Store body data into a file. */
mg_store_body :: (conn: *mg_connection, path: *u8) -> s64 #foreign libcivetweb;

/* Read data from the remote end, return number of bytes read.
Return:
0     connection has been closed by peer. No more data could be read.
< 0   read error. No more data could be read from the connection.
> 0   number of bytes read into the buffer. */
mg_read :: (unknown0: *mg_connection, buf: *void, len: u64) -> s32 #foreign libcivetweb;

/* Get the value of particular HTTP header.

This is a helper function. It traverses request_info->http_headers array,
and if the header is present in the array, returns its value. If it is
not present, NULL is returned. */
mg_get_header :: (unknown0: *mg_connection, name: *u8) -> *u8 #foreign libcivetweb;

/* Get a value of particular form variable.

Parameters:
data: pointer to form-uri-encoded buffer. This could be either POST data,
or request_info.query_string.
data_len: length of the encoded data.
var_name: variable name to decode from the buffer
dst: destination buffer for the decoded variable
dst_len: length of the destination buffer

Return:
On success, length of the decoded variable.
On error:
-1 (variable not found).
-2 (destination buffer is NULL, zero length or too small to hold the
decoded variable).

Destination buffer is guaranteed to be '\0' - terminated if it is not
NULL or zero length. */
mg_get_var :: (data: *u8, data_len: u64, var_name: *u8, dst: *u8, dst_len: u64) -> s32 #foreign libcivetweb;

/* Get a value of particular form variable.

Parameters:
data: pointer to form-uri-encoded buffer. This could be either POST data,
or request_info.query_string.
data_len: length of the encoded data.
var_name: variable name to decode from the buffer
dst: destination buffer for the decoded variable
dst_len: length of the destination buffer
occurrence: which occurrence of the variable, 0 is the 1st, 1 the 2nd, ...
this makes it possible to parse a query like
b=x&a=y&a=z which will have occurrence values b:0, a:0 and a:1

Return:
On success, length of the decoded variable.
On error:
-1 (variable not found).
-2 (destination buffer is NULL, zero length or too small to hold the
decoded variable).

Destination buffer is guaranteed to be '\0' - terminated if it is not
NULL or zero length. */
mg_get_var2 :: (data: *u8, data_len: u64, var_name: *u8, dst: *u8, dst_len: u64, occurrence: u64) -> s32 #foreign libcivetweb;

/* Split form encoded data into a list of key value pairs.
A form encoded input might be a query string, the body of a
x-www-form-urlencoded POST request or any other data with this
structure: "keyName1=value1&keyName2=value2&keyName3=value3".
Values might be percent-encoded - this function will transform
them to the unencoded characters.
The input string is modified by this function: To split the
"query_string" member of struct request_info, create a copy first
(e.g., using strdup).
The function itself does not allocate memory. Thus, it is not
required to free any pointer returned from this function.
The output list of is limited to MG_MAX_FORM_FIELDS name-value-
pairs. The default value is reasonably oversized for typical
applications, however, for special purpose systems it might be
required to increase this value at compile time.

Parameters:
data: form encoded input string. Will be modified by this function.
form_fields: output list of name/value-pairs. A buffer with a size
specified by num_form_fields must be provided by the
caller.
num_form_fields: Size of provided form_fields buffer in number of
"struct mg_header" elements.

Return:
On success: number of form_fields filled
On error:
-1 (parameter error). */
mg_split_form_urlencoded :: (data: *u8, form_fields: *mg_header, num_form_fields: u32) -> s32 #foreign libcivetweb;

/* Fetch value of certain cookie variable into the destination buffer.

Destination buffer is guaranteed to be '\0' - terminated. In case of
failure, dst[0] == '\0'. Note that RFC allows many occurrences of the same
parameter. This function returns only first occurrence.

Return:
On success, value length.
On error:
-1 (either "Cookie:" header is not present at all or the requested
parameter is not found).
-2 (destination buffer is NULL, zero length or too small to hold the
value). */
mg_get_cookie :: (cookie: *u8, var_name: *u8, buf: *u8, buf_len: u64) -> s32 #foreign libcivetweb;

/* Download data from the remote web server.
host: host name to connect to, e.g. "foo.com", or "10.12.40.1".
port: port number, e.g. 80.
use_ssl: whether to use SSL connection.
error_buffer, error_buffer_size: error message placeholder.
request_fmt,...: HTTP request.
Return:
On success, valid pointer to the new connection, suitable for mg_read().
On error, NULL. error_buffer contains error message.
Example:
char ebuf[100];
struct mg_connection *conn;
conn = mg_download("google.com", 80, 0, ebuf, sizeof(ebuf),
"%s", "GET / HTTP/1.0\r\nHost: google.com\r\n\r\n");

mg_download is equivalent to calling mg_connect_client followed by
mg_printf and mg_get_response. Using these three functions directly may
allow more control as compared to using mg_download.
*/
mg_download_CFormat :: (host: *u8, port: s32, use_ssl: s32, error_buffer: *u8, error_buffer_size: u64, request_fmt: *u8, __args: ..Any) -> *mg_connection #foreign libcivetweb "mg_download";
mg_download :: (host: *u8, port: s32, use_ssl: s32, error_buffer: *u8, error_buffer_size: u64, request_fmt: string, __args: ..Any) -> *mg_connection {
    push_allocator(temp);
    formatted_text_builder: String_Builder;
    print_to_builder(*formatted_text_builder, request_fmt, ..__args);
    append(*formatted_text_builder, "\0");
    formatted_text := builder_to_string(*formatted_text_builder);
    return mg_download_CFormat(host, port, use_ssl, error_buffer, error_buffer_size, "%s", formatted_text.data);
} @PrintLike

/* Close the connection opened by mg_download(). */
mg_close_connection :: (conn: *mg_connection) -> void #foreign libcivetweb;

/* This structure contains callback functions for handling form fields.
It is used as an argument to mg_handle_form_request. */
mg_form_data_handler :: struct {
    /* This callback function is called, if a new field has been found.
    * The return value of this callback is used to define how the field
    * should be processed.
    *
    * Parameters:
    *   key: Name of the field ("name" property of the HTML input field).
    *   filename: Name of a file to upload, at the client computer.
    *             Only set for input fields of type "file", otherwise NULL.
    *   path: Output parameter: File name (incl. path) to store the file
    *         at the server computer. Only used if MG_FORM_FIELD_STORAGE_STORE
    *         is returned by this callback. Existing files will be
    *         overwritten.
    *   pathlen: Length of the buffer for path.
    *   user_data: Value of the member user_data of mg_form_data_handler
    *
    * Return value:
    *   The callback must return the intended storage for this field
    *   (See MG_FORM_FIELD_STORAGE_*).
    */
    field_found: #type (key: *u8, filename: *u8, path: *u8, pathlen: u64, user_data: *void) -> s32 #c_call;

    /* If the "field_found" callback returned MG_FORM_FIELD_STORAGE_GET,
    * this callback will receive the field data.
    *
    * Parameters:
    *   key: Name of the field ("name" property of the HTML input field).
    *   value: Value of the input field.
    *   user_data: Value of the member user_data of mg_form_data_handler
    *
    * Return value:
    *   The return code determines how the server should continue processing
    *   the current request (See MG_FORM_FIELD_HANDLE_*).
    */
    field_get:   #type (key: *u8, value: *u8, valuelen: u64, user_data: *void) -> s32 #c_call;

    /* If the "field_found" callback returned MG_FORM_FIELD_STORAGE_STORE,
    * the data will be stored into a file. If the file has been written
    * successfully, this callback will be called. This callback will
    * not be called for only partially uploaded files. The
    * mg_handle_form_request function will either store the file completely
    * and call this callback, or it will remove any partial content and
    * not call this callback function.
    *
    * Parameters:
    *   path: Path of the file stored at the server.
    *   file_size: Size of the stored file in bytes.
    *   user_data: Value of the member user_data of mg_form_data_handler
    *
    * Return value:
    *   The return code determines how the server should continue processing
    *   the current request (See MG_FORM_FIELD_HANDLE_*).
    */
    field_store: #type (path: *u8, file_size: s64, user_data: *void) -> s32 #c_call;

    /* User supplied argument, passed to all callback functions. */
    user_data:   *void;
}

/* Return values definition for the "field_found" callback in
* mg_form_data_handler. */
MG_FORM_FIELD_STORAGE :: enum u32 {
    SKIP  :: 0;

    GET   :: 1;

    STORE :: 2;

    ABORT :: 16;
}

/* Return values for "field_get" and "field_store" */
MG_FORM_FIELD_HANDLE :: enum u32 {
    GET   :: 1;

    NEXT  :: 8;

    ABORT :: 16;
}

/* Process form data.
* Returns the number of fields handled, or < 0 in case of an error.
* Note: It is possible that several fields are already handled successfully
* (e.g., stored into files), before the request handling is stopped with an
* error. In this case a number < 0 is returned as well.
* In any case, it is the duty of the caller to remove files once they are
* no longer required. */
mg_handle_form_request :: (conn: *mg_connection, fdh: *mg_form_data_handler) -> s32 #foreign libcivetweb;

/* Convenience function -- create detached thread.
Return: 0 on success, non-0 on error. */
mg_thread_func_t :: #type (unknown0: *void) -> *void #c_call;
mg_start_thread :: (f: mg_thread_func_t, p: *void) -> s32 #foreign libcivetweb;

/* Return builtin mime type for the given file name.
For unrecognized extensions, "text/plain" is returned. */
mg_get_builtin_mime_type :: (file_name: *u8) -> *u8 #foreign libcivetweb;

/* Get text representation of HTTP status code. */
mg_get_response_code_text :: (conn: *mg_connection, response_code: s32) -> *u8 #foreign libcivetweb;

/* Return CivetWeb version. */
mg_version :: () -> *u8 #foreign libcivetweb;

/* URL-decode input buffer into destination buffer.
0-terminate the destination buffer.
form-url-encoded data differs from URI encoding in a way that it
uses '+' as character for space, see RFC 1866 section 8.2.1
http://ftp.ics.uci.edu/pub/ietf/html/rfc1866.txt
Return: length of the decoded data, or -1 if dst buffer is too small. */
mg_url_decode :: (src: *u8, src_len: s32, dst: *u8, dst_len: s32, is_form_url_encoded: s32) -> s32 #foreign libcivetweb;

/* URL-encode input buffer into destination buffer.
returns the length of the resulting buffer or -1
is the buffer is too small. */
mg_url_encode :: (src: *u8, dst: *u8, dst_len: u64) -> s32 #foreign libcivetweb;

/* BASE64-encode input buffer into destination buffer.
returns -1 on OK. */
mg_base64_encode :: (src: *u8, src_len: u64, dst: *u8, dst_len: *u64) -> s32 #foreign libcivetweb;

/* BASE64-decode input buffer into destination buffer.
returns -1 on OK. */
mg_base64_decode :: (src: *u8, src_len: u64, dst: *u8, dst_len: *u64) -> s32 #foreign libcivetweb;

/* MD5 hash given strings.
Buffer 'buf' must be 33 bytes long. Varargs is a NULL terminated list of
ASCIIz strings. When function returns, buf will contain human-readable
MD5 hash. Example:
char buf[33];
mg_md5(buf, "aa", "bb", NULL); */
mg_md5 :: (buf: *[33] u8, __args: ..Any) -> *u8 #foreign libcivetweb;

mg_match_element :: struct {
    str: *u8; /* First character matching wildcard */
    len: u64; /* Number of character matching wildcard */
}

mg_match_context :: struct {
    case_sensitive: s32; /* Input: 1 (case sensitive) or 0 (insensitive) */
    num_matches:    u64; /* Output: Number of wildcard matches returned. */
    match:          [32] mg_match_element; /* Output */
}

/* Print error message to the opened error log stream.
This utilizes the provided logging configuration.
conn: connection (not used for sending data, but to get perameters)
fmt: format string without the line return
...: variable argument list
Example:
mg_cry(conn,"i like %s", "logging"); */
mg_cry_CFormat :: (conn: *mg_connection, fmt: *u8, __args: ..Any) -> void #foreign libcivetweb "mg_cry";
mg_cry :: (conn: *mg_connection, fmt: string, __args: ..Any) {
    push_allocator(temp);
    formatted_text_builder: String_Builder;
    print_to_builder(*formatted_text_builder, fmt, ..__args);
    append(*formatted_text_builder, "\0");
    formatted_text := builder_to_string(*formatted_text_builder);
    mg_cry_CFormat(conn, "%s", formatted_text.data);
} @PrintLike

/* utility methods to compare two buffers, case insensitive. */
mg_strcasecmp :: (s1: *u8, s2: *u8) -> s32 #foreign libcivetweb;
mg_strncasecmp :: (s1: *u8, s2: *u8, len: u64) -> s32 #foreign libcivetweb;

/* Connect to a websocket as a client
Parameters:
host: host to connect to, i.e. "echo.websocket.org" or "192.168.1.1" or
"localhost"
port: server port
use_ssl: make a secure connection to server
error_buffer, error_buffer_size: buffer for an error message
path: server path you are trying to connect to, i.e. if connection to
localhost/app, path should be "/app"
origin: value of the Origin HTTP header
data_func: callback that should be used when data is received from the
server
user_data: user supplied argument

Return:
On success, valid mg_connection object.
On error, NULL. Se error_buffer for details.
*/
mg_connect_websocket_client :: (host: *u8, port: s32, use_ssl: s32, error_buffer: *u8, error_buffer_size: u64, path: *u8, origin: *u8, data_func: mg_websocket_data_handler, close_func: mg_websocket_close_handler, user_data: *void) -> *mg_connection #foreign libcivetweb;

mg_connect_websocket_client_extensions :: (host: *u8, port: s32, use_ssl: s32, error_buffer: *u8, error_buffer_size: u64, path: *u8, origin: *u8, extensions: *u8, data_func: mg_websocket_data_handler, close_func: mg_websocket_close_handler, user_data: *void) -> *mg_connection #foreign libcivetweb;

/* Connect to a TCP server as a client (can be used to connect to a HTTP server)
Parameters:
host: host to connect to, i.e. "www.wikipedia.org" or "192.168.1.1" or
"localhost"
port: server port
use_ssl: make a secure connection to server
error_buffer, error_buffer_size: buffer for an error message

Return:
On success, valid mg_connection object.
On error, NULL. Se error_buffer for details.
*/
mg_connect_client :: (host: *u8, port: s32, use_ssl: s32, error_buffer: *u8, error_buffer_size: u64) -> *mg_connection #foreign libcivetweb;

mg_client_options :: struct {
    host:        *u8;
    port:        s32;
    client_cert: *u8;
    server_cert: *u8;
    host_name:   *u8;
}

mg_connect_client_secure :: (client_options: *mg_client_options, error_buffer: *u8, error_buffer_size: u64) -> *mg_connection #foreign libcivetweb;

mg_connect_websocket_client_secure :: (client_options: *mg_client_options, error_buffer: *u8, error_buffer_size: u64, path: *u8, origin: *u8, data_func: mg_websocket_data_handler, close_func: mg_websocket_close_handler, user_data: *void) -> *mg_connection #foreign libcivetweb;

mg_connect_websocket_client_secure_extensions :: (client_options: *mg_client_options, error_buffer: *u8, error_buffer_size: u64, path: *u8, origin: *u8, extensions: *u8, data_func: mg_websocket_data_handler, close_func: mg_websocket_close_handler, user_data: *void) -> *mg_connection #foreign libcivetweb;

anon_enum :: enum s32 {
    MG_TIMEOUT_INFINITE :: -1;
}

/* Wait for a response from the server
Parameters:
conn: connection
ebuf, ebuf_len: error message placeholder.
timeout: time to wait for a response in milliseconds (if < 0 then wait
forever)

Return:
On success, >= 0
On error/timeout, < 0
*/
mg_get_response :: (conn: *mg_connection, ebuf: *u8, ebuf_len: u64, timeout: s32) -> s32 #foreign libcivetweb;

/* Initialize a new HTTP response
* Parameters:
*   conn: Current connection handle.
*   status: HTTP status code (e.g., 200 for "OK").
* Return:
*   0:    ok
*  -1:    parameter error
*  -2:    invalid connection type
*  -3:    invalid connection status
*  -4:    network error (only if built with NO_RESPONSE_BUFFERING)
*/
mg_response_header_start :: (conn: *mg_connection, status: s32) -> s32 #foreign libcivetweb;

/* Add a new HTTP response header line
* Parameters:
*   conn: Current connection handle.
*   header: Header name.
*   value: Header value.
*   value_len: Length of header value, excluding the terminating zero.
*              Use -1 for "strlen(value)".
* Return:
*   0:    ok
*  -1:    parameter error
*  -2:    invalid connection type
*  -3:    invalid connection status
*  -4:    too many headers
*  -5:    out of memory
*/
mg_response_header_add :: (conn: *mg_connection, header: *u8, value: *u8, value_len: s32) -> s32 #foreign libcivetweb;

/* Add a complete header string (key + value).
* This function is less efficient as compared to mg_response_header_add,
* and should only be used to convert complete HTTP/1.x header lines.
* Parameters:
*   conn: Current connection handle.
*   http1_headers: Header line(s) in the form "name: value\r\n".
* Return:
*  >=0:   no error, number of header lines added
*  -1:    parameter error
*  -2:    invalid connection type
*  -3:    invalid connection status
*  -4:    too many headers
*  -5:    out of memory
*/
mg_response_header_add_lines :: (conn: *mg_connection, http1_headers: *u8) -> s32 #foreign libcivetweb;

/* Send http response
* Parameters:
*   conn: Current connection handle.
* Return:
*   0:    ok
*  -1:    parameter error
*  -2:    invalid connection type
*  -3:    invalid connection status
*  -4:    sending failed (network error)
*/
mg_response_header_send :: (conn: *mg_connection) -> s32 #foreign libcivetweb;

/* Check which features where set when the civetweb library has been compiled.
The function explicitly addresses compile time defines used when building
the library - it does not mean, the feature has been initialized using a
mg_init_library call.
mg_check_feature can be called anytime, even before mg_init_library has
been called.

Parameters:
feature: specifies which feature should be checked
The value is a bit mask. The individual bits are defined as:
1  serve files (NO_FILES not set)
2  support HTTPS (NO_SSL not set)
4  support CGI (NO_CGI not set)
8  support IPv6 (USE_IPV6 set)
16  support WebSocket (USE_WEBSOCKET set)
32  support Lua scripts and Lua server pages (USE_LUA is set)
64  support server side JavaScript (USE_DUKTAPE is set)
128  support caching (NO_CACHING not set)
256  support server statistics (USE_SERVER_STATS is set)
512  support for on the fly compression (USE_ZLIB is set)

These values are defined as MG_FEATURES_*

The result is undefined, if bits are set that do not represent a
defined feature (currently: feature >= 1024).
The result is undefined, if no bit is set (feature == 0).

Return:
If a feature is available, the corresponding bit is set
If a feature is not available, the bit is 0
*/
mg_check_feature :: (feature: u32) -> u32 #foreign libcivetweb;

/* Get information on the system. Useful for support requests.
Parameters:
buffer: Store system information as string here.
buflen: Length of buffer (including a byte required for a terminating 0).
Return:
Available size of system information, excluding a terminating 0.
The information is complete, if the return value is smaller than buflen.
The result is a JSON formatted string, the exact content may vary.
Note:
It is possible to determine the required buflen, by first calling this
function with buffer = NULL and buflen = NULL. The required buflen is
one byte more than the returned value.
*/
mg_get_system_info :: (buffer: *u8, buflen: s32) -> s32 #foreign libcivetweb;

/* Get context information. Useful for server diagnosis.
Parameters:
ctx: Context handle
buffer: Store context information here.
buflen: Length of buffer (including a byte required for a terminating 0).
Return:
Available size of system information, excluding a terminating 0.
The information is complete, if the return value is smaller than buflen.
The result is a JSON formatted string, the exact content may vary.
Note:
It is possible to determine the required buflen, by first calling this
function with buffer = NULL and buflen = NULL. The required buflen is
one byte more than the returned value. However, since the available
context information changes, you should allocate a few bytes more.
*/
mg_get_context_info :: (ctx: *mg_context, buffer: *u8, buflen: s32) -> s32 #foreign libcivetweb;

/* Disable HTTP keep-alive on a per-connection basis.
Reference: https://github.com/civetweb/civetweb/issues/727
Parameters:
conn: Current connection handle.
*/
mg_disable_connection_keep_alive :: (conn: *mg_connection) -> void #foreign libcivetweb;

/* New APIs for enhanced option and error handling.
These mg_*2 API functions have the same purpose as their original versions,
but provide additional options and/or provide improved error diagnostics.

Note: Experimental interfaces may change
*/
mg_error_data :: struct {
    code:             u32; /* error code (number) */
    code_sub:         u32; /* error sub code (number) */
    text:             *u8; /* buffer for error text */
    text_buffer_size: u64; /* size of buffer of "text" */
}

/* Values for error "code" in mg_error_data */
MG_ERROR_DATA_CODE :: enum u32 {
    OK                    :: 0;

    INVALID_PARAM         :: 1;

    INVALID_OPTION        :: 2;

    INIT_TLS_FAILED       :: 3;

    MISSING_OPTION        :: 4;

    DUPLICATE_DOMAIN      :: 5;

    OUT_OF_MEMORY         :: 6;

    SERVER_STOPPED        :: 7;

    INIT_LIBRARY_FAILED   :: 8;

    OS_ERROR              :: 9;

    INIT_PORTS_FAILED     :: 10;

    INIT_USER_FAILED      :: 11;

    INIT_ACL_FAILED       :: 12;

    INVALID_PASS_FILE     :: 13;

    SCRIPT_ERROR          :: 14;

    HOST_NOT_FOUND        :: 15;

    CONNECT_TIMEOUT       :: 16;

    CONNECT_FAILED        :: 17;

    TLS_CLIENT_CERT_ERROR :: 18;

    TLS_SERVER_CERT_ERROR :: 19;

    TLS_CONNECT_ERROR     :: 20;
}

mg_init_data :: struct {
    callbacks:             *mg_callbacks; /* callback function pointer */
    user_data:             *void; /* data */
    configuration_options: **u8;
}

mg_start2 :: (init: *mg_init_data, error: *mg_error_data) -> *mg_context #foreign libcivetweb;

mg_start_domain2 :: (ctx: *mg_context, configuration_options: **u8, error: *mg_error_data) -> s32 #foreign libcivetweb;

#scope_file

#import "Basic"; // For push_context

libcivetweb :: #library "./civetweb/libcivetweb";
