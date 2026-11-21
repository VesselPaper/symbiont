/* 这份文件由 scripts/range_check.py 生成，别手改。
 * 页面会把这里的结果盖到 range-data.js 的手写判定上。
 */
window.RANGE_RESULTS = {
  "updated": "2026-11-21 16:00",
  "items": {
    "direct-origin": {
      "gw": "拦住",
      "base": "打穿",
      "evidence": "docker port symbiont-server-1 输出 ''；宿主机 8000 是别的服务占着，打 /api/v1/health 拿不到我们后端。裸奔栈 18081 能连。",
      "transcript": [
        {
          "kind": "cmd",
          "title": "docker port symbiont-server-1",
          "text": "（没有输出）",
          "at": "15:52:29"
        },
        {
          "kind": "req",
          "title": "GET http://127.0.0.1:8000/api/v1/health",
          "text": "（没有自定义头）",
          "at": "15:52:29"
        },
        {
          "kind": "res",
          "title": "HTTP 200",
          "text": "content-type: text/html; charset=utf-8\ncontent-length: 6942\n\n<!DOCTYPE html>\r\n<html>\r\n<head>\r\n\r\n<meta http-equiv=\"Content-Type\" content=\"text/html; charset=UTF-8\" />\r\n<link rel=\"stylesheet\" type=\"text/css\" href=\"http://127.0.0.1:8000/c_c2.css\" />\r\n<script src=\"http://127.0.0.1:8000/CLodopfuncs.js\"></script>\r\n<title>Welcome to C-Lodop</title>\r\n</head>\r\n<body onLoad=\"demoCreatePrinterList()\">\r\n<center>\r\n<div id=\"itopform\" >\r\n     <form>\r\n       <h1>欢迎使用C-Lodop打印服务系统\r\n\t   <span class=\"small\">The Cloud Web Service System for Lodop HTML Print</span>\r\n\t</h1><hr>\r\n    </form>\r\n </div>\r\n</center>\r\n\r\n<h3>&nbsp;使用说明：</h3>\r\n\r\n<script>\r\n        function demoPrint(t",
          "at": "15:52:29"
        }
      ],
      "ms": 115,
      "at": "15:52:29"
    },
    "direct-db": {
      "gw": "拦住",
      "base": "打穿",
      "evidence": "docker port symbiont-mysql-1 输出 ''，没有对外发布；裸奔栈 13307 能连，root/root 能直接进。",
      "transcript": [
        {
          "kind": "cmd",
          "title": "docker port symbiont-mysql-1",
          "text": "（没有输出）",
          "at": "15:52:29"
        }
      ],
      "ms": 61,
      "at": "15:52:29"
    },
    "rate-bypass": {
      "gw": "拦住",
      "base": "同网关栈",
      "evidence": "40 个并发请求同时发出：21 个返回 200、19 个返回 429。限流键为客户端 IP，速率上限 8r/s、突发 20，单 IP 并发上限 20。",
      "transcript": [
        {
          "kind": "cmd",
          "title": "40 个线程同步起跑",
          "text": "起跑线同时放行，每个线程请求 /api/v1/health，不重试。",
          "at": "15:52:32"
        },
        {
          "kind": "res",
          "title": "前 6 个响应的状态码",
          "text": "200  200  429  429  200  429\n合计 200×21、429×19，其余为连接失败。",
          "at": "15:52:32"
        }
      ],
      "ms": 3042,
      "at": "15:52:32"
    },
    "burst": {
      "gw": "拦住",
      "base": "同网关栈",
      "evidence": "40 个并发请求同时发出：21 个返回 200、19 个返回 429。限流键为客户端 IP，速率上限 8r/s、突发 20，单 IP 并发上限 20。",
      "transcript": [
        {
          "kind": "cmd",
          "title": "40 个线程同步起跑",
          "text": "起跑线同时放行，每个线程请求 /api/v1/health，不重试。",
          "at": "15:53:26"
        },
        {
          "kind": "res",
          "title": "前 6 个响应的状态码",
          "text": "200  200  200  200  200  200\n合计 200×21、429×19，其余为连接失败。",
          "at": "15:53:26"
        }
      ],
      "ms": 3042,
      "at": "15:53:26"
    },
    "xff": {
      "gw": "拦住",
      "base": "打穿",
      "evidence": "携带 X-Forwarded-For: 6.6.6.6：正式网关回显 172.18.0.1（网关看到的真实对端），修复前网关 9443 回显 6.6.6.6，裸奔对照栈回显 6.6.6.6。两台网关连接同一后端，唯一差异是该头部使用 $remote_addr 覆盖还是追加。",
      "transcript": [
        {
          "kind": "req",
          "title": "GET https://localhost/api/v1/health",
          "text": "X-Forwarded-For: 6.6.6.6",
          "at": "16:00:26"
        },
        {
          "kind": "res",
          "title": "HTTP 200",
          "text": "content-type: application/json\ncontent-length: 106\nx-upstream: 172.18.0.3:8000\nx-frame-options: SAMEORIGIN\n\n{\"status\":\"ok\",\"service\":\"symbiont-server\",\"version\":\"0.1.0\",\"instance\":\"node-3\",\"client_ip\":\"172.18.0.1\"}",
          "at": "16:00:26"
        },
        {
          "kind": "req",
          "title": "GET https://localhost:9443/api/v1/health",
          "text": "X-Forwarded-For: 6.6.6.6",
          "at": "16:00:26"
        },
        {
          "kind": "res",
          "title": "HTTP 200",
          "text": "content-type: application/json\ncontent-length: 103\nx-upstream: 172.18.0.5:8000\nx-frame-options: SAMEORIGIN\n\n{\"status\":\"ok\",\"service\":\"symbiont-server\",\"version\":\"0.1.0\",\"instance\":\"node-1\",\"client_ip\":\"6.6.6.6\"}",
          "at": "16:00:26"
        },
        {
          "kind": "req",
          "title": "GET http://localhost:18081/api/v1/health",
          "text": "X-Forwarded-For: 6.6.6.6",
          "at": "16:00:26"
        },
        {
          "kind": "res",
          "title": "HTTP 200",
          "text": "content-length: 97\ncontent-type: application/json\n\n{\"status\":\"ok\",\"service\":\"symbiont-server\",\"version\":\"0.1.0\",\"instance\":\"\",\"client_ip\":\"6.6.6.6\"}",
          "at": "16:00:26"
        }
      ],
      "ms": 31,
      "at": "16:00:26"
    },
    "body": {
      "gw": "拦住",
      "base": "同网关栈",
      "evidence": "5 MB 的 PUT 请求在网关返回 413，后端未收到该请求；请求体上限配置为 4m。",
      "transcript": [
        {
          "kind": "req",
          "title": "PUT https://localhost/api/v1/saves/0",
          "text": "Content-Type: application/json\nX-Device-Id: range-body-probe\n请求体 5242880 字节",
          "at": "15:52:35"
        },
        {
          "kind": "res",
          "title": "HTTP 413",
          "text": "content-type: text/html\ncontent-length: 176\nx-frame-options: SAMEORIGIN\n\n<html>\r\n<head><title>413 Request Entity Too Large</title></head>\r\n<body>\r\n<center><h1>413 Request Entity Too Large</h1></center>\r\n<hr><center>nginx</center>\r\n</body>\r\n</html>",
          "at": "15:52:35"
        }
      ],
      "ms": 21,
      "at": "15:52:35"
    },
    "slow": {
      "gw": "拦住",
      "base": "同网关栈",
      "evidence": "每两秒发一行请求头，15 秒后连接被断开（client_header_timeout 15s，正文超时同样是 15s）。",
      "transcript": [
        {
          "kind": "cmd",
          "title": "裸 socket，每 2 秒发一行请求头",
          "text": "已发送 2 行，15.0 秒后连接关闭（收到 EOF 或报错）",
          "at": "15:52:50"
        }
      ],
      "ms": 15012,
      "at": "15:52:50"
    },
    "smuggling": {
      "gw": "拦住",
      "base": "同网关栈",
      "evidence": "同一请求同时带 Content-Length: 6 和 Transfer-Encoding: chunked，网关回 HTTP/1.1 400 Bad Request。",
      "transcript": [
        {
          "kind": "req",
          "title": "裸 socket 发原始报文",
          "text": "POST /api/v1/events HTTP/1.1\r\nHost: localhost\r\nContent-Length: 6\r\nTransfer-Encoding: chunked\r\n\r\n0",
          "at": "15:52:50"
        },
        {
          "kind": "res",
          "title": "原始回包",
          "text": "HTTP/1.1 400 Bad Request\r\nServer: nginx\r\nDate: Sat, 21 Nov 2026 07:52:50 GMT\r\nContent-Type: text/html\r\nContent-Length: 150\r\nConnection: close\r\nX-Content-Type-Options: nosniff\r\nX-Frame-Options: SAMEORIGIN\r\nReferrer-Policy: no-referrer-when-downgrade\r\n\r\n<html>\r\n<head><title>400 Bad Request</title></head>\r\n<body>\r\n<center><h1>400 Bad Request</h1></center>\r\n<hr><center>nginx</center>\r\n</body>\r\n</html>",
          "at": "15:52:50"
        }
      ],
      "ms": 4,
      "at": "15:52:50"
    },
    "tls": {
      "gw": "拦住",
      "base": "打穿",
      "evidence": "容器内用放开旧协议的 openssl 握手：TLS1.0 rejected，TLS1.1 rejected，TLS1.2 ok。被拒时服务端回的是 tlsv1 alert protocol version。裸奔栈整条链路是明文 HTTP，不需要握手就能读。",
      "transcript": [
        {
          "kind": "cmd",
          "title": "docker exec symbiont-server-1 sh -c printf 'openssl_conf = openssl_init\\n[openssl_init]\\nssl_conf = ssl_sect\\n[ssl_sect]\\nsystem_default = system_default_sect\\n[system_default_sect]\\nMinProtocol = TLSv1\\nCipherString = DEFAULT@SECLEVEL=0\\n' > /tmp/legacy.cnf; echo | OPENSSL_CONF=/tmp/legacy.cnf openssl s_client -connect proxy:8443 -tls1 2>&1 | grep -E 'alert protocol version|New, TLS'",
          "text": "4057299E83750000:error:0A00042E:SSL routines:ssl3_read_bytes:tlsv1 alert protocol version:../ssl/record/rec_layer_s3.c:918:SSL alert number 70",
          "at": "15:52:50"
        },
        {
          "kind": "cmd",
          "title": "docker exec symbiont-server-1 sh -c printf 'openssl_conf = openssl_init\\n[openssl_init]\\nssl_conf = ssl_sect\\n[ssl_sect]\\nsystem_default = system_default_sect\\n[system_default_sect]\\nMinProtocol = TLSv1\\nCipherString = DEFAULT@SECLEVEL=0\\n' > /tmp/legacy.cnf; echo | OPENSSL_CONF=/tmp/legacy.cnf openssl s_client -connect proxy:8443 -tls1_1 2>&1 | grep -E 'alert protocol version|New, TLS'",
          "text": "40F7C5E7F47E0000:error:0A00042E:SSL routines:ssl3_read_bytes:tlsv1 alert protocol version:../ssl/record/rec_layer_s3.c:918:SSL alert number 70",
          "at": "15:52:51"
        },
        {
          "kind": "cmd",
          "title": "docker exec symbiont-server-1 sh -c printf 'openssl_conf = openssl_init\\n[openssl_init]\\nssl_conf = ssl_sect\\n[ssl_sect]\\nsystem_default = system_default_sect\\n[system_default_sect]\\nMinProtocol = TLSv1\\nCipherString = DEFAULT@SECLEVEL=0\\n' > /tmp/legacy.cnf; echo | OPENSSL_CONF=/tmp/legacy.cnf openssl s_client -connect proxy:8443 -tls1_2 2>&1 | grep -E 'alert protocol version|New, TLS'",
          "text": "New, TLSv1.2, Cipher is ECDHE-RSA-AES256-GCM-SHA384",
          "at": "15:52:51"
        }
      ],
      "ms": 446,
      "at": "15:52:51"
    },
    "noauth-write": {
      "gw": "打穿",
      "base": "同网关栈",
      "evidence": "从没出现过的设备 id 第一次 PUT 回 200，服务端顺手建了匿名账号 device:range-0cde2193a735。",
      "transcript": [
        {
          "kind": "req",
          "title": "PUT https://localhost/api/v1/saves/0",
          "text": "Content-Type: application/json\nX-Device-Id: range-0cde2193a735\n请求体 24 字节",
          "at": "15:52:51"
        },
        {
          "kind": "res",
          "title": "HTTP 200",
          "text": "content-type: application/json\ncontent-length: 64\nx-upstream: 172.18.0.3:8000\nx-frame-options: SAMEORIGIN\n\n{\"slot\":0,\"updated_at\":\"2026-11-21T07:52:51\",\"rev\":1,\"bytes\":20}",
          "at": "15:52:51"
        }
      ],
      "ms": 45,
      "at": "15:52:51"
    },
    "guess-id": {
      "gw": "打穿",
      "base": "同网关栈",
      "evidence": "拿同一个设备 id 再 GET，回 200，正文里带着刚写进去的 mark。",
      "transcript": [
        {
          "kind": "req",
          "title": "PUT https://localhost/api/v1/saves/0",
          "text": "Content-Type: application/json\nX-Device-Id: range-cc1a188d9818\n请求体 41 字节",
          "at": "15:52:51"
        },
        {
          "kind": "res",
          "title": "HTTP 200",
          "text": "content-type: application/json\ncontent-length: 64\nx-upstream: 172.18.0.5:8000\nx-frame-options: SAMEORIGIN\n\n{\"slot\":0,\"updated_at\":\"2026-11-21T07:52:51\",\"rev\":1,\"bytes\":37}",
          "at": "15:52:51"
        },
        {
          "kind": "req",
          "title": "GET https://localhost/api/v1/saves/0",
          "text": "X-Device-Id: range-cc1a188d9818",
          "at": "15:52:51"
        },
        {
          "kind": "res",
          "title": "HTTP 200",
          "text": "content-type: application/json\ncontent-length: 98\nx-upstream: 172.18.0.4:8000\nx-frame-options: SAMEORIGIN\n\n{\"slot\":0,\"updated_at\":\"2026-11-21T07:52:51\",\"rev\":1,\"save_data\":{\"hp\":7,\"_rev\":1,\"mark\":\"guess\"}}",
          "at": "15:52:51"
        }
      ],
      "ms": 61,
      "at": "15:52:51"
    },
    "base-rev": {
      "gw": "打穿",
      "base": "同网关栈",
      "evidence": "不带 base_rev 的 PUT 回 200，存档被覆盖；带陈旧 base_rev 的 PUT 回 409。版本校验能挡住并发的旧写，挡不住直接不带版本号的写。",
      "transcript": [
        {
          "kind": "req",
          "title": "PUT https://localhost/api/v1/saves/0",
          "text": "Content-Type: application/json\nX-Device-Id: range-8f94104a1471\n请求体 24 字节",
          "at": "15:52:51"
        },
        {
          "kind": "res",
          "title": "HTTP 200",
          "text": "content-type: application/json\ncontent-length: 64\nx-upstream: 172.18.0.3:8000\nx-frame-options: SAMEORIGIN\n\n{\"slot\":0,\"updated_at\":\"2026-11-21T07:52:51\",\"rev\":1,\"bytes\":20}",
          "at": "15:52:51"
        },
        {
          "kind": "req",
          "title": "PUT https://localhost/api/v1/saves/0",
          "text": "Content-Type: application/json\nX-Device-Id: range-8f94104a1471\n请求体 25 字节",
          "at": "15:52:51"
        },
        {
          "kind": "res",
          "title": "HTTP 200",
          "text": "content-type: application/json\ncontent-length: 64\nx-upstream: 172.18.0.5:8000\nx-frame-options: SAMEORIGIN\n\n{\"slot\":0,\"updated_at\":\"2026-11-21T07:52:51\",\"rev\":2,\"bytes\":21}",
          "at": "15:52:51"
        },
        {
          "kind": "req",
          "title": "PUT https://localhost/api/v1/saves/0",
          "text": "Content-Type: application/json\nX-Device-Id: range-8f94104a1471\n请求体 40 字节",
          "at": "15:52:51"
        },
        {
          "kind": "res",
          "title": "HTTP 409",
          "text": "content-type: application/json\ncontent-length: 88\nx-upstream: 172.18.0.4:8000\nx-frame-options: SAMEORIGIN\n\n{\"detail\":{\"message\":\"存档已被别处修改\",\"rev\":2,\"save_data\":{\"hp\":99,\"_rev\":2}}}",
          "at": "15:52:51"
        }
      ],
      "ms": 84,
      "at": "15:52:51"
    },
    "ts-forge": {
      "gw": "打穿",
      "base": "同网关栈",
      "evidence": "埋点里带 ts=0，接口回 200，库里 created_at 记成 1970-01-01 00:00:00，审计时间跟着客户端走。",
      "transcript": [
        {
          "kind": "req",
          "title": "POST https://localhost/api/v1/events",
          "text": "Content-Type: application/json\n请求体 88 字节",
          "at": "15:52:51"
        },
        {
          "kind": "res",
          "title": "HTTP 200",
          "text": "content-type: application/json\ncontent-length: 14\nx-upstream: 172.18.0.3:8000\nx-frame-options: SAMEORIGIN\n\n{\"accepted\":1}",
          "at": "15:52:51"
        },
        {
          "kind": "cmd",
          "title": "docker exec symbiont-mysql-1 mysql -usymbiont -p68dc3df594adc02f65315925b67947e0a4e44f00e1b9817c71d6a4d3854c7f42 -N -B -e select created_at from symbiont.events where json_extract(payload, '$.marker') = 'range-ts-ae3452c1'",
          "text": "1970-01-01 00:00:00",
          "at": "15:52:51"
        }
      ],
      "ms": 118,
      "at": "15:52:51"
    },
    "bulk-account": {
      "gw": "打穿",
      "base": "同网关栈",
      "evidence": "按每秒六个换 40 个新设备 id 写存档，40 个回 200，库里多出 40 个匿名账号；限流只按 IP 记速度，换 IP 就没有上限。",
      "transcript": [
        {
          "kind": "req",
          "title": "PUT https://localhost/api/v1/saves/0",
          "text": "Content-Type: application/json\nX-Device-Id: range-bulk-5270f995fb\n请求体 24 字节",
          "at": "15:52:51"
        },
        {
          "kind": "res",
          "title": "HTTP 200",
          "text": "content-type: application/json\ncontent-length: 64\nx-upstream: 172.18.0.5:8000\nx-frame-options: SAMEORIGIN\n\n{\"slot\":0,\"updated_at\":\"2026-11-21T07:52:51\",\"rev\":1,\"bytes\":20}",
          "at": "15:52:51"
        },
        {
          "kind": "req",
          "title": "PUT https://localhost/api/v1/saves/0",
          "text": "Content-Type: application/json\nX-Device-Id: range-bulk-70387aa94e\n请求体 24 字节",
          "at": "15:52:51"
        },
        {
          "kind": "res",
          "title": "HTTP 200",
          "text": "content-type: application/json\ncontent-length: 64\nx-upstream: 172.18.0.4:8000\nx-frame-options: SAMEORIGIN\n\n{\"slot\":0,\"updated_at\":\"2026-11-21T07:52:51\",\"rev\":1,\"bytes\":20}",
          "at": "15:52:51"
        },
        {
          "kind": "req",
          "title": "PUT https://localhost/api/v1/saves/0",
          "text": "Content-Type: application/json\nX-Device-Id: range-bulk-3f5a7863cb\n请求体 24 字节",
          "at": "15:52:51"
        },
        {
          "kind": "res",
          "title": "HTTP 200",
          "text": "content-type: application/json\ncontent-length: 64\nx-upstream: 172.18.0.3:8000\nx-frame-options: SAMEORIGIN\n\n{\"slot\":0,\"updated_at\":\"2026-11-21T07:52:51\",\"rev\":1,\"bytes\":20}",
          "at": "15:52:51"
        },
        {
          "kind": "req",
          "title": "PUT https://localhost/api/v1/saves/0",
          "text": "Content-Type: application/json\nX-Device-Id: range-bulk-8ed70ba6db\n请求体 24 字节",
          "at": "15:52:52"
        },
        {
          "kind": "res",
          "title": "HTTP 200",
          "text": "content-type: application/json\ncontent-length: 64\nx-upstream: 172.18.0.5:8000\nx-frame-options: SAMEORIGIN\n\n{\"slot\":0,\"updated_at\":\"2026-11-21T07:52:52\",\"rev\":1,\"bytes\":20}",
          "at": "15:52:52"
        },
        {
          "kind": "req",
          "title": "PUT https://localhost/api/v1/saves/0",
          "text": "Content-Type: application/json\nX-Device-Id: range-bulk-f88ba17aab\n请求体 24 字节",
          "at": "15:52:52"
        },
        {
          "kind": "res",
          "title": "HTTP 200",
          "text": "content-type: application/json\ncontent-length: 64\nx-upstream: 172.18.0.4:8000\nx-frame-options: SAMEORIGIN\n\n{\"slot\":0,\"updated_at\":\"2026-11-21T07:52:52\",\"rev\":1,\"bytes\":20}",
          "at": "15:52:52"
        },
        {
          "kind": "req",
          "title": "PUT https://localhost/api/v1/saves/0",
          "text": "Content-Type: application/json\nX-Device-Id: range-bulk-80dcc566f7\n请求体 24 字节",
          "at": "15:52:52"
        },
        {
          "kind": "res",
          "title": "HTTP 200",
          "text": "content-type: application/json\ncontent-length: 64\nx-upstream: 172.18.0.3:8000\nx-frame-options: SAMEORIGIN\n\n{\"slot\":0,\"updated_at\":\"2026-11-21T07:52:52\",\"rev\":1,\"bytes\":20}",
          "at": "15:52:52"
        },
        {
          "kind": "req",
          "title": "PUT https://localhost/api/v1/saves/0",
          "text": "Content-Type: application/json\nX-Device-Id: range-bulk-9cf45b59c8\n请求体 24 字节",
          "at": "15:52:52"
        },
        {
          "kind": "res",
          "title": "HTTP 200",
          "text": "content-type: application/json\ncontent-length: 64\nx-upstream: 172.18.0.5:8000\nx-frame-options: SAMEORIGIN\n\n{\"slot\":0,\"updated_at\":\"2026-11-21T07:52:52\",\"rev\":1,\"bytes\":20}",
          "at": "15:52:52"
        },
        {
          "kind": "req",
          "title": "PUT https://localhost/api/v1/saves/0",
          "text": "Content-Type: application/json\nX-Device-Id: range-bulk-f38dcd0ffc\n请求体 24 字节",
          "at": "15:52:52"
        },
        {
          "kind": "res",
          "title": "HTTP 200",
          "text": "content-type: application/json\ncontent-length: 64\nx-upstream: 172.18.0.4:8000\nx-frame-options: SAMEORIGIN\n\n{\"slot\":0,\"updated_at\":\"2026-11-21T07:52:52\",\"rev\":1,\"bytes\":20}",
          "at": "15:52:52"
        },
        {
          "kind": "req",
          "title": "PUT https://localhost/api/v1/saves/0",
          "text": "Content-Type: application/json\nX-Device-Id: range-bulk-a23ad6bdf0\n请求体 24 字节",
          "at": "15:52:53"
        },
        {
          "kind": "res",
          "title": "HTTP 200",
          "text": "content-type: application/json\ncontent-length: 64\nx-upstream: 172.18.0.3:8000\nx-frame-options: SAMEORIGIN\n\n{\"slot\":0,\"updated_at\":\"2026-11-21T07:52:53\",\"rev\":1,\"bytes\":20}",
          "at": "15:52:53"
        },
        {
          "kind": "req",
          "title": "PUT https://localhost/api/v1/saves/0",
          "text": "Content-Type: application/json\nX-Device-Id: range-bulk-e52c6b9597\n请求体 24 字节",
          "at": "15:52:53"
        },
        {
          "kind": "res",
          "title": "HTTP 200",
          "text": "content-type: application/json\ncontent-length: 64\nx-upstream: 172.18.0.5:8000\nx-frame-options: SAMEORIGIN\n\n{\"slot\":0,\"updated_at\":\"2026-11-21T07:52:53\",\"rev\":1,\"bytes\":20}",
          "at": "15:52:53"
        },
        {
          "kind": "req",
          "title": "PUT https://localhost/api/v1/saves/0",
          "text": "Content-Type: application/json\nX-Device-Id: range-bulk-3f36a828f1\n请求体 24 字节",
          "at": "15:52:53"
        },
        {
          "kind": "res",
          "title": "HTTP 200",
          "text": "content-type: application/json\ncontent-length: 64\nx-upstream: 172.18.0.4:8000\nx-frame-options: SAMEORIGIN\n\n{\"slot\":0,\"updated_at\":\"2026-11-21T07:52:53\",\"rev\":1,\"bytes\":20}",
          "at": "15:52:53"
        },
        {
          "kind": "req",
          "title": "PUT https://localhost/api/v1/saves/0",
          "text": "Content-Type: application/json\nX-Device-Id: range-bulk-8f5c94e4bc\n请求体 24 字节",
          "at": "15:52:53"
        },
        {
          "kind": "res",
          "title": "HTTP 200",
          "text": "content-type: application/json\ncontent-length: 64\nx-upstream: 172.18.0.3:8000\nx-frame-options: SAMEORIGIN\n\n{\"slot\":0,\"updated_at\":\"2026-11-21T07:52:53\",\"rev\":1,\"bytes\":20}",
          "at": "15:52:53"
        }
      ],
      "ms": 7893,
      "at": "15:52:59"
    },
    "plain-save": {
      "gw": "打穿",
      "base": "打穿",
      "evidence": "直接 select save_data，看到的是明文 JSON：{\"hp\": 1, \"_rev\": 1}",
      "transcript": [
        {
          "kind": "cmd",
          "title": "docker exec symbiont-mysql-1 mysql -usymbiont -p68dc3df594adc02f65315925b67947e0a4e44f00e1b9817c71d6a4d3854c7f42 -N -B -e select save_data from symbiont.saves order by id desc limit 1",
          "text": "{\"hp\": 1, \"_rev\": 1}",
          "at": "15:52:59"
        }
      ],
      "ms": 110,
      "at": "15:52:59"
    },
    "docs-leak": {
      "gw": "拦住",
      "base": "打穿",
      "evidence": "网关 /docs 回 404（不挂 /api 前缀的路径到不了后端），裸奔栈 /docs 回 200。",
      "transcript": [
        {
          "kind": "req",
          "title": "GET https://localhost/docs",
          "text": "（没有自定义头）",
          "at": "15:52:59"
        },
        {
          "kind": "res",
          "title": "HTTP 404",
          "text": "content-type: text/html\ncontent-length: 146\nx-frame-options: SAMEORIGIN\n\n<html>\r\n<head><title>404 Not Found</title></head>\r\n<body>\r\n<center><h1>404 Not Found</h1></center>\r\n<hr><center>nginx</center>\r\n</body>\r\n</html>",
          "at": "15:52:59"
        },
        {
          "kind": "req",
          "title": "GET http://localhost:18081/docs",
          "text": "（没有自定义头）",
          "at": "15:52:59"
        },
        {
          "kind": "res",
          "title": "HTTP 200",
          "text": "content-length: 963\ncontent-type: text/html; charset=utf-8\n\n\n    <!DOCTYPE html>\n    <html>\n    <head>\n    <link type=\"text/css\" rel=\"stylesheet\" href=\"https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui.css\">\n    <link rel=\"shortcut icon\" href=\"https://fastapi.tiangolo.com/img/favicon.png\">\n    <title>Symbiont Server — 共生之缚 后端 - Swagger UI</title>\n    </head>\n    <body>\n    <div id=\"swagger-ui\">\n    </div>\n    <script src=\"https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui-bundle.js\"></script>\n    <!-- `SwaggerUIBundle` is now available on the page -->\n    <script>\n    const ui = SwaggerUIBundle({\n        url: '/openapi.json',\n    \"dom_id",
          "at": "15:52:59"
        }
      ],
      "ms": 7,
      "at": "15:52:59"
    },
    "default-pass": {
      "gw": "拦住",
      "base": "打穿",
      "evidence": "裸奔栈 root/root 能进，读到 users 共 2 行；网关栈 root/root 进不去，口令是 gen_env 生成的随机值。",
      "transcript": [
        {
          "kind": "cmd",
          "title": "docker exec symbiont-baseline-mysql-1 mysql -uroot -proot -N -B -e select count(*) from symbiont.users",
          "text": "2",
          "at": "15:52:59"
        },
        {
          "kind": "cmd",
          "title": "docker exec symbiont-mysql-1 mysql -uroot -proot -N -B -e select 1",
          "text": "mysql: [Warning] Using a password on the command line interface can be insecure.\nERROR 1045 (28000): Access denied for user 'root'@'localhost' (using password: YES)",
          "at": "15:52:59"
        }
      ],
      "ms": 197,
      "at": "15:52:59"
    },
    "enum-users": {
      "gw": "拦住",
      "base": "打穿",
      "evidence": "裸奔栈能直接读到账号表，前几行是 ['mysql: [Warning] Using a password on the command line interface can be insecure.', \"ERROR 1045 (28000): Access denied for user 'symbiont'@'localhost' (using password: YES)\"]；匿名账号用户名就是 device: 加设备 id。",
      "transcript": [
        {
          "kind": "cmd",
          "title": "docker exec symbiont-baseline-mysql-1 mysql -usymbiont -p68dc3df594adc02f65315925b67947e0a4e44f00e1b9817c71d6a4d3854c7f42 -N -B -e select username from symbiont.users limit 3",
          "text": "mysql: [Warning] Using a password on the command line interface can be insecure.\nERROR 1045 (28000): Access denied for user 'symbiont'@'localhost' (using password: YES)",
          "at": "15:52:59"
        }
      ],
      "ms": 106,
      "at": "15:52:59"
    },
    "secret-default": {
      "gw": "打穿",
      "base": "同网关栈",
      "evidence": "config.py 里默认值还在，compose 没有注入 SYMBIONT_SECRET_KEY。现在还没有代码拿它签名，签名功能一接上就直接可用。",
      "transcript": [],
      "ms": 0,
      "at": "15:52:59"
    },
    "container-user": {
      "gw": "拦住",
      "base": "打穿",
      "evidence": "网关跑在 nginx，后端跑在 app；裸奔栈后端跑在 app。",
      "transcript": [
        {
          "kind": "cmd",
          "title": "docker inspect -f {{.Config.User}} symbiont-proxy-1",
          "text": "nginx",
          "at": "15:52:59"
        },
        {
          "kind": "cmd",
          "title": "docker inspect -f {{.Config.User}} symbiont-server-1",
          "text": "app",
          "at": "15:52:59"
        },
        {
          "kind": "cmd",
          "title": "docker inspect -f {{.Config.User}} symbiont-baseline-server-1",
          "text": "app",
          "at": "15:52:59"
        }
      ],
      "ms": 180,
      "at": "15:52:59"
    },
    "log-mask": {
      "gw": "拦住",
      "base": "同网关栈",
      "evidence": "最近 80 行网关日志里设备 id 出现 0 次，请求体内容没出现；日志格式只记 IP、UA、上游地址和耗时。",
      "transcript": [
        {
          "kind": "cmd",
          "title": "docker logs --tail 80 symbiont-proxy-1",
          "text": "172.18.0.1 \"GET /api/v1/health HTTP/1.1\" 429 162 rt=0.000 urt=- ua=-\n172.18.0.1 \"GET /api/v1/health HTTP/1.1\" 200 106 rt=0.003 urt=0.003 ua=172.18.0.4:8000\n172.18.0.1 \"GET /api/v1/health HTTP/1.1\" 200 106 rt=0.003 urt=0.004 ua=172.18.0.3:8000\n172.18.0.1 \"GET /api/v1/health HTTP/1.1\" 200 106 rt=0.004 urt=0.004 ua=172.18.0.3:8000\n172.18.0.1 \"GET /api/v1/health HTTP/1.1\" 200 106 rt=0.005 urt=0.005 ua=172.18.0.3:8000\n172.18.0.1 \"GET /api/v1/health HTTP/1.1\" 200 106 rt=0.006 urt=0.006 ua=172.18.0.5:8000\n172.18.0.1 \"GET /api/v1/health HTTP/1.1\" 200 106 rt=0.008 urt=0.008 ua=172.18.0.5:8000\n172.18.0.1 \"GET /api/v1/health HTTP/1.1\" 200 106 rt=0.006 urt=0.005 ua=172.18.0.5:8000\n172.18.0.1 \"GET /api/v\n…（后面还有 4998 字，截断）",
          "at": "15:53:00"
        }
      ],
      "ms": 75,
      "at": "15:53:00"
    },
    "tag-float": {
      "gw": "拦住",
      "base": "同网关栈",
      "evidence": "IMAGE_TAG=8ba7443-dirty，对应镜像在本地；不走 latest。",
      "transcript": [
        {
          "kind": "cmd",
          "title": "docker images --format {{.Repository}}:{{.Tag}} symbiont-server",
          "text": "symbiont-server:8ba7443-dirty\nsymbiont-server:local\nsymbiont-server:probe\nsymbiont-server:77440c7-dirty\nsymbiont-server:8631af1-dirty\nsymbiont-server:9bbd6e0-dirty",
          "at": "15:53:00"
        }
      ],
      "ms": 89,
      "at": "15:53:00"
    },
    "env-plain": {
      "gw": "打穿",
      "base": "同网关栈",
      "evidence": "deploy/.env 里数据库口令是明文；gitignore 挡住了进仓库，本机任何进程都能读到。",
      "transcript": [],
      "ms": 0,
      "at": "15:53:00"
    },
    "clickjack": {
      "gw": "拦住",
      "base": "打穿",
      "evidence": "网关 /status.html 回 X-Frame-Options: SAMEORIGIN；裸奔栈 /docs 回 无；靶场自己的受害者页回 无。三页来自三个不同站点，对照页里框住的结果与此一致。",
      "transcript": [
        {
          "kind": "req",
          "title": "GET https://localhost/status.html",
          "text": "（没有自定义头）",
          "at": "15:53:00"
        },
        {
          "kind": "res",
          "title": "HTTP 200",
          "text": "content-type: text/html\ncontent-length: 7547\nx-frame-options: SAMEORIGIN\n\n<!DOCTYPE html>\n<html lang=\"zh-CN\">\n<head>\n<meta charset=\"utf-8\">\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n<title>共生之缚 · 网关状态</title>\n<style>\n  :root { color-scheme: dark; }\n  * { box-sizing: border-box; }\n  body {\n    margin: 0; padding: 32px 24px 48px;\n    background: #0a0c10; color: #cfd6e4;\n    font: 14px/1.6 \"Segoe UI\", \"Microsoft YaHei\", system-ui, sans-serif;\n  }\n  .wrap { max-width: 880px; margin: 0 auto; }\n  h1 { font-size: 20px; font-weight: 600; margin: 0 0 2px; }\n  .sub { color: #6c7891; font-size: 12px; margin-bottom: 24px; }\n\n  .bar { display: flex; ga",
          "at": "15:53:00"
        },
        {
          "kind": "req",
          "title": "GET http://localhost:18081/docs",
          "text": "（没有自定义头）",
          "at": "15:53:00"
        },
        {
          "kind": "res",
          "title": "HTTP 200",
          "text": "content-length: 963\ncontent-type: text/html; charset=utf-8\n\n\n    <!DOCTYPE html>\n    <html>\n    <head>\n    <link type=\"text/css\" rel=\"stylesheet\" href=\"https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui.css\">\n    <link rel=\"shortcut icon\" href=\"https://fastapi.tiangolo.com/img/favicon.png\">\n    <title>Symbiont Server — 共生之缚 后端 - Swagger UI</title>\n    </head>\n    <body>\n    <div id=\"swagger-ui\">\n    </div>\n    <script src=\"https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui-bundle.js\"></script>\n    <!-- `SwaggerUIBundle` is now available on the page -->\n    <script>\n    const ui = SwaggerUIBundle({\n        url: '/openapi.json',\n    \"dom_id",
          "at": "15:53:00"
        },
        {
          "kind": "req",
          "title": "GET http://127.0.0.1:18080/attack/victim.html",
          "text": "（没有自定义头）",
          "at": "15:53:00"
        },
        {
          "kind": "res",
          "title": "HTTP 200",
          "text": "content-type: text/html\ncontent-length: 1310\n\n<!DOCTYPE html>\n<html lang=\"zh-CN\">\n<head>\n<meta charset=\"utf-8\">\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n<title>补偿奖励 · 云端存档</title>\n<link rel=\"stylesheet\" href=\"/attack/product.css\">\n</head>\n<body>\n<header class=\"p-head\">\n  <span class=\"brand\">共生之缚 · 云端存档</span>\n  <span class=\"who\">补偿活动</span>\n</header>\n\n<main class=\"p-main\">\n  <h1>补偿奖励</h1>\n  <div class=\"p-card\">\n    <p>上一轮存档维护期间，部分设备的数据写入出现延迟。受影响的设备可在本页领取一次补偿。</p>\n    <p class=\"muted\">补偿内容：存档槽位扩容一次，有效期 7 天。</p>\n    <button class=\"p-btn\" id=\"btn\">领取补偿</button>\n    <p class=\"p-result\" id=\"count\">尚未领取</p>\n  </div>",
          "at": "15:53:00"
        }
      ],
      "ms": 33,
      "at": "15:53:00"
    },
    "csrf": {
      "gw": "拦住",
      "base": "同网关栈",
      "evidence": "表单 GET 回 400，表单 POST 回 405，预检回 405；响应里 Set-Cookie 一个都没有。后端没有会话，跨站请求没有可借用的身份。",
      "transcript": [
        {
          "kind": "req",
          "title": "GET https://localhost/api/v1/saves/0",
          "text": "（没有自定义头）",
          "at": "15:53:00"
        },
        {
          "kind": "res",
          "title": "HTTP 400",
          "text": "content-type: application/json\ncontent-length: 31\nx-upstream: 172.18.0.4:8000\nx-frame-options: SAMEORIGIN\n\n{\"detail\":\"缺少 X-Device-Id\"}",
          "at": "15:53:00"
        },
        {
          "kind": "req",
          "title": "POST https://localhost/api/v1/saves/0",
          "text": "Content-Type: application/x-www-form-urlencoded\n请求体 11 字节",
          "at": "15:53:00"
        },
        {
          "kind": "res",
          "title": "HTTP 405",
          "text": "content-type: application/json\ncontent-length: 31\nx-upstream: 172.18.0.3:8000\nx-frame-options: SAMEORIGIN\n\n{\"detail\":\"Method Not Allowed\"}",
          "at": "15:53:00"
        },
        {
          "kind": "req",
          "title": "OPTIONS https://localhost/api/v1/saves/0",
          "text": "Origin: https://127.0.0.1\nAccess-Control-Request-Method: PUT\nAccess-Control-Request-Headers: x-device-id",
          "at": "15:53:00"
        },
        {
          "kind": "res",
          "title": "HTTP 405",
          "text": "content-type: application/json\ncontent-length: 31\nx-upstream: 172.18.0.5:8000\nx-frame-options: SAMEORIGIN\n\n{\"detail\":\"Method Not Allowed\"}",
          "at": "15:53:00"
        }
      ],
      "ms": 13,
      "at": "15:53:00"
    },
    "cors-read": {
      "gw": "拦住",
      "base": "拦住",
      "evidence": "带 Origin 请求，响应里 Access-Control-Allow-Origin 没有，浏览器读不到正文。",
      "transcript": [
        {
          "kind": "req",
          "title": "GET https://localhost/api/v1/health",
          "text": "Origin: https://127.0.0.1",
          "at": "15:53:00"
        },
        {
          "kind": "res",
          "title": "HTTP 200",
          "text": "content-type: application/json\ncontent-length: 106\nx-upstream: 172.18.0.4:8000\nx-frame-options: SAMEORIGIN\n\n{\"status\":\"ok\",\"service\":\"symbiont-server\",\"version\":\"0.1.0\",\"instance\":\"node-2\",\"client_ip\":\"172.18.0.1\"}",
          "at": "15:53:00"
        }
      ],
      "ms": 5,
      "at": "15:53:00"
    },
    "tamper": {
      "gw": "打穿",
      "base": "同网关栈",
      "evidence": "把存档内容改成自定义武器再上传，读回来原样保留，服务端不校验内容。",
      "transcript": [
        {
          "kind": "req",
          "title": "PUT https://localhost/api/v1/saves/0",
          "text": "Content-Type: application/json\nX-Device-Id: range-c66a6e30095b\n请求体 64 字节",
          "at": "15:53:00"
        },
        {
          "kind": "res",
          "title": "HTTP 200",
          "text": "content-type: application/json\ncontent-length: 64\nx-upstream: 172.18.0.3:8000\nx-frame-options: SAMEORIGIN\n\n{\"slot\":0,\"updated_at\":\"2026-11-21T07:53:00\",\"rev\":1,\"bytes\":52}",
          "at": "15:53:00"
        },
        {
          "kind": "req",
          "title": "GET https://localhost/api/v1/saves/0",
          "text": "X-Device-Id: range-c66a6e30095b",
          "at": "15:53:00"
        },
        {
          "kind": "res",
          "title": "HTTP 200",
          "text": "content-type: application/json\ncontent-length: 119\nx-upstream: 172.18.0.5:8000\nx-frame-options: SAMEORIGIN\n\n{\"slot\":0,\"updated_at\":\"2026-11-21T07:53:00\",\"rev\":1,\"save_data\":{\"hp\":5,\"_rev\":1,\"flag\":true,\"weapon\":\"改过的剑\"}}",
          "at": "15:53:00"
        }
      ],
      "ms": 39,
      "at": "15:53:00"
    },
    "xss": {
      "gw": "拦住",
      "base": "同网关栈",
      "evidence": "把 <script> 塞进埋点，再翻四个页面，命中 零处；接口只回 JSON，没有页面把用户输入当 HTML 渲染。",
      "transcript": [
        {
          "kind": "req",
          "title": "POST https://localhost/api/v1/events",
          "text": "Content-Type: application/json\n请求体 87 字节",
          "at": "15:53:00"
        },
        {
          "kind": "res",
          "title": "HTTP 200",
          "text": "content-type: application/json\ncontent-length: 14\nx-upstream: 172.18.0.4:8000\nx-frame-options: SAMEORIGIN\n\n{\"accepted\":1}",
          "at": "15:53:00"
        },
        {
          "kind": "req",
          "title": "GET https://localhost/",
          "text": "（没有自定义头）",
          "at": "15:53:00"
        },
        {
          "kind": "res",
          "title": "HTTP 302",
          "text": "content-type: text/html\ncontent-length: 138\nx-frame-options: SAMEORIGIN\n\n<html>\r\n<head><title>302 Found</title></head>\r\n<body>\r\n<center><h1>302 Found</h1></center>\r\n<hr><center>nginx</center>\r\n</body>\r\n</html>",
          "at": "15:53:00"
        },
        {
          "kind": "req",
          "title": "GET https://localhost/status.html",
          "text": "（没有自定义头）",
          "at": "15:53:00"
        },
        {
          "kind": "res",
          "title": "HTTP 200",
          "text": "content-type: text/html\ncontent-length: 7547\nx-frame-options: SAMEORIGIN\n\n<!DOCTYPE html>\n<html lang=\"zh-CN\">\n<head>\n<meta charset=\"utf-8\">\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n<title>共生之缚 · 网关状态</title>\n<style>\n  :root { color-scheme: dark; }\n  * { box-sizing: border-box; }\n  body {\n    margin: 0; padding: 32px 24px 48px;\n    background: #0a0c10; color: #cfd6e4;\n    font: 14px/1.6 \"Segoe UI\", \"Microsoft YaHei\", system-ui, sans-serif;\n  }\n  .wrap { max-width: 880px; margin: 0 auto; }\n  h1 { font-size: 20px; font-weight: 600; margin: 0 0 2px; }\n  .sub { color: #6c7891; font-size: 12px; margin-bottom: 24px; }\n\n  .bar { display: flex; ga",
          "at": "15:53:00"
        },
        {
          "kind": "req",
          "title": "GET http://127.0.0.1:18080/attack/",
          "text": "（没有自定义头）",
          "at": "15:53:00"
        },
        {
          "kind": "res",
          "title": "HTTP 200",
          "text": "content-type: text/html\ncontent-length: 7009\n\n<!DOCTYPE html>\n<html lang=\"zh-CN\">\n<head>\n<meta charset=\"utf-8\">\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n<title>攻防检测总览 · 共生之缚</title>\n<link rel=\"stylesheet\" href=\"/attack/range.css\">\n</head>\n<body data-page=\"overview\">\n<div class=\"shell\">\n  <aside class=\"rail\" id=\"rail\"></aside>\n\n  <main class=\"content\">\n    <header class=\"hero\">\n      <div>\n        <span class=\"eyebrow\">攻击面清单 · 五层</span>\n        <h1>攻防检测总览</h1>\n      </div>\n      <div class=\"figs\" id=\"stats\"></div>\n    </header>\n\n    <div class=\"actions\">\n      <button id=\"btn-all\">重新执行全部检测</button>\n      <button",
          "at": "15:53:00"
        },
        {
          "kind": "req",
          "title": "GET http://127.0.0.1:18080/attack/index.html",
          "text": "（没有自定义头）",
          "at": "15:53:00"
        },
        {
          "kind": "res",
          "title": "HTTP 200",
          "text": "content-type: text/html\ncontent-length: 7009\n\n<!DOCTYPE html>\n<html lang=\"zh-CN\">\n<head>\n<meta charset=\"utf-8\">\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n<title>攻防检测总览 · 共生之缚</title>\n<link rel=\"stylesheet\" href=\"/attack/range.css\">\n</head>\n<body data-page=\"overview\">\n<div class=\"shell\">\n  <aside class=\"rail\" id=\"rail\"></aside>\n\n  <main class=\"content\">\n    <header class=\"hero\">\n      <div>\n        <span class=\"eyebrow\">攻击面清单 · 五层</span>\n        <h1>攻防检测总览</h1>\n      </div>\n      <div class=\"figs\" id=\"stats\"></div>\n    </header>\n\n    <div class=\"actions\">\n      <button id=\"btn-all\">重新执行全部检测</button>\n      <button",
          "at": "15:53:00"
        }
      ],
      "ms": 67,
      "at": "15:53:00"
    }
  }
};
