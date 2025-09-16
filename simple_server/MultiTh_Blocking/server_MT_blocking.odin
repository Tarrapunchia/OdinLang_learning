package main

import "base:runtime"
import "core:thread"
import "core:strings"
import "core:fmt"
import "core:net"
import posix "core:sys/posix"
import os "core:os"

// const
BUF_SIZE        :: 4096
MAX_CONNECTIONS :: 10

format_response :: proc(
    status_code: u16,
    status: string,
    content_type: string,
    body : string = "") -> []u8 {

    header := fmt.tprintf(
        "HTTP/1.1 %d %s\r\n" +
        "Content-Type: %s\r\n" +
        "Content-Length: %d\r\n" +
        "Connection: close\r\n" +
        "\r\n",
        status_code,
        status,
        content_type,
        len(body)
    )

    resp := strings.concatenate({header, body}, context.allocator)
    RESP_LEN := len(resp)
    resp_bytes := make([dynamic]u8, context.temp_allocator);
    for x in 0..<RESP_LEN {
        append(&resp_bytes, resp[x])
    }

    return resp_bytes[:]
}

// parse Content-Length
parse_content_length :: proc(headers: []u8) -> int {
    lower := strings.to_lower(string(headers), context.temp_allocator)
    key := "content-length:"
    k := strings.index(lower, key)
    if k < 0 { return -1 }
    start := k + len(key)
    for start < len(lower) && (lower[start] == ' ' || lower[start] == '\t') do start += 1
    n := 0
    have := false
    for start < len(lower) && lower[start] >= '0' && lower[start] <= '9' {
        n = n*10 + int(lower[start]-'0')
        start += 1
        have = true
    }
    if !have { return -1 }
    return n
}

Headers :: struct {
    method: string,
    HTTP_v: string,
    host  : string,
    user_agent: string,
    accept: string,
    content_length: int,
    constent_type: string
}

parse_header_params :: proc(headers: []u8) -> (header_s: Headers, err: net.Resolve_Error) {
    lower := strings.to_lower(string(headers), context.temp_allocator)
    keys := []string{
        "host: ",
        "user-agent: ",
        "accept: ",
        "content-length: ",
        "content-type: "
    }
    for key in keys {
        k := strings.index(lower, key)
        if k < 0 { continue  }
        start := k + len(key)
        // for start < len(lower) && (lower[start] == ' ' || lower[start] == '\t') do start += 1
        n := 0
        have := false
        for start < len(lower) && lower[start] >= '0' && lower[start] <= '9' {
            n = n*10 + int(lower[start]-'0')
            start += 1
            have = true
        }

    }
    key := "content-length:"
    if !have { return -1 }
    return n
}


fill_headers :: proc (headers: []u8) {
    s_headers := (string(headers))
    head_arr := strings.split(s_headers, "\n")


}

handle_client :: proc(client: rawptr) {
    // shadowing of the client arg with cast to the correct data type
    client := net.TCP_Socket(uintptr(client))

    // closing with defer
    defer net.close(client)
    defer free_all(context.temp_allocator)

    buf: [BUF_SIZE]byte
    msg := make([dynamic]byte, context.temp_allocator);
    sep := []u8{13,10,13,10} // "\r\n\r\n"
    end := -1
    read := 0
    for end < 0 {
        n, err := net.recv_tcp(client, buf[:])
        if err != nil {
            fmt.println("[WARNING]Recv error:", err)
            return
        }
        if n == 0 { return }
        append_elems(&msg, ..buf[:n])
        end = strings.index(string(msg[:]), string(sep[:]))
        if len(buf) > 1 << 20 {
            fmt.println("[ERROR]Headers too large")
            return
        }
        read += n
    }
    // headers
    headers := buf[:end]
    header: Headers = fill_headers(headers)
    body_start := end + len(sep)

    fmt.printfln(string(headers))

    // cont_len
    content_len := parse_content_length(headers)
    if content_len < 0 { content_len = 0 }
    else {
        fmt.println("--- BODY START ---")
    }

    // check for bytes of the body attached to the \r\n\r\n
    body_part := read - body_start
    if body_part > 0 {
        fmt.println(string(buf[body_start:]))
    }

    // go on reading
    remaining := content_len - body_part
    fmt.printfln("c l %d, b p %d", content_len, body_part)
    for remaining > 0 {
        n, err := net.recv_tcp(client, buf[:])
        if err != nil {
            fmt.println("[WARNING]Recv error:", err)
            return
        }
        if n == 0 { return }
        append_elems(&msg, ..buf[:n])
        fmt.println(string(buf[:n]))
        remaining -= n
    }

    if (content_len > 0) { fmt.println("--- END BODY ---") }

    // send
    _, send_err := net.send_tcp(client, format_response(200, "OK", "text/html", "Hello from Odin!"))
    if send_err != nil {
        fmt.println("send error:", send_err)
    }
    free_all(context.temp_allocator)
}

listen_s: net.TCP_Socket
err_ls: net.Network_Error
state: net.Link_States
Worker :: struct {
    thread: thread.Thread,
    sock: net.TCP_Socket
}

// signals setup for graceful shutdown with SIGINT
handler_sigint :: proc "c" (posix.Signal) {
    context = runtime.default_context()
    fmt.println("\nSIGINT received.\nClosing...")
    state = net.Link_States.Down
    // if listen_s != 0 do net.close(listen_s)
}

main :: proc() {
    // set up for the socket
    listen_s, err_ls = net.listen_tcp(net.Endpoint {
        port    = 8000,
        address = net.IP4_Loopback // 127.0.0.1
    })
    if err_ls != nil do fmt.panicf("[FATAL]Setting up the listen socket resulted in [%s] error.", err_ls)
    state = net.Link_States.Up
    // defer closing the socket to the end of proc
    defer net.close(listen_s)

    fmt.println("[DEBUG]Listening on 127.0.0.1:8000 for max", MAX_CONNECTIONS, "clients. Press CTRL+C to stop.")

    // // signals setup for graceful shutdown with SIGINT
    // handler_sigint :: proc "c" (posix.Signal) {
    //     context = runtime.default_context()
    //     fmt.println("\nSIGINT received.\nClosing...")
    //     state = net.Link_States.Down
    //     // if listen_s != 0 do net.close(listen_s)
    // }

    posix.signal(posix.Signal(posix.SIGINT), handler_sigint)

    // circolar queue of the active threads handles
    active_workers: [MAX_CONNECTIONS]Worker
    active_nbr := 0

    for state == net.Link_States.Up {
        if (state == net.Link_States.Up) {
            client, _, accept_err := net.accept_tcp(listen_s)
            if accept_err != nil {
                fmt.println("[WARNING]Accept error:", accept_err)
                continue
        }

        // if we reached max conn, waits for the oldest to end
        if active_nbr >= MAX_CONNECTIONS {
            thread.join(&active_workers[0].thread)

            // shifting to the left
            for i in 1..<active_nbr do active_workers[i - 1] = active_workers[i]
            active_nbr -= 1
        }

        // creating the new thread for the client
        if (state == net.Link_States.Up) {
            th := thread.create_and_start_with_data(cast(rawptr)uintptr(client), handle_client)
            active_workers[active_nbr] = Worker { th^, client }
            active_nbr += 1
        }}
    }

    for i in 0..<active_nbr {
        net.close(active_workers[i].sock)
    }

    for i in 0..<active_nbr {
        thread.join(&active_workers[i].thread)
    }
}