/* 靶场清单与判定。
 *
 * 为什么用 .js 不用 JSON：这页要能直接在浏览器里打开，也要能挂在 /attack/ 下被
 * 不同域名访问。fetch 一个 json 在 file:// 和跨域下都会被挡，写成赋值脚本就没这问题。
 *
 * 判定的三个值：拦住、打穿、待打。待打表示还没真正打过，页面上摆着，收工前要清零。
 * 每条 evidence 写的都是本机实测到的东西，或者能对着配置和代码指出来的位置。
 * 改判定的规矩：先测，再改这里，别把还没测的写成拦住。
 *
 * 改这个文件不要用 PowerShell 的 Get-Content | Set-Content，
 * 它按 ANSI 读再按 UTF-8 写，中文整份变乱码（这次已经踩过一回）。
 */
window.RANGE = {
  updated: '2026-11-17',
  stacks: [
    { name: '网关栈', url: 'https://localhost', note: '80 跳 443，自签证书' },
    { name: '修复前网关', url: 'https://localhost:9443', note: '只差 X-Forwarded-For 那一行，专门留着演示打穿' },
    { name: '裸奔对照栈', url: 'http://localhost:18081', note: '没有网关，后端直连宿主机' }
  ],
  layers: [
    {
      id: 'browser',
      title: '浏览器侧',
      intro: '本层检测由浏览器行为触发，打开对照页即可观察结果。',
      items: [
        {
          id: 'clickjack',
          name: '点击劫持',
          how: '在对照页内分别以跨站方式嵌入网关页面、裸奔对照栈接口文档与靶场受害者页，观察浏览器是否允许渲染。',
          gw: '拦住', base: '打穿',
          evidence: '网关响应带 X-Frame-Options: SAMEORIGIN，从别的站点内嵌时框里是灰底加一个坏掉的图标，就是被浏览器拒了；裸奔栈 /docs 不带任何 frame 相关头，框里能正常显示它的页面。裸奔栈那一栏的 Swagger 前端脚本要从外网拉，本机没网时只停在加载圈，不影响判断。',
          link: { href: '/attack/clickjacking.html', text: '对照页' }
        },
        {
          id: 'csrf',
          name: '跨站请求伪造',
          how: '在对照页内依次发送跨站表单 GET、跨站表单 POST 与携带自定义请求头的跨站请求。',
          gw: '拦住', base: '同网关栈',
          evidence: '表单 GET 回 400 缺 X-Device-Id，表单 POST 回 405，带自定义头的 fetch 卡在预检。后端没有 cookie 也没有会话，跨站请求没有任何身份可借。这一条的结论不是这里守住了，是身份本来就不存在，问题挪到应用层的无认证那一行。',
          link: { href: '/attack/csrf.html', text: '对照页' }
        },
        {
          id: 'cors-read',
          name: '跨站读取',
          how: '从 127.0.0.1 页面请求网关 /api/v1/health，尝试读取响应正文。',
          gw: '拦住', base: '拦住',
          evidence: '两边响应都没有 Access-Control-Allow-Origin，浏览器直接抛 TypeError，读不到内容。'
        },
        {
          id: 'tamper',
          name: '本地存档篡改再上传',
          how: '修改客户端持有的存档内容后，重新 PUT 至 /api/v1/saves/0。',
          gw: '打穿', base: '同网关栈',
          evidence: '实测 PUT 上去的 save_data 原样落库，服务端不校验内容，只把 _rev 加一。'
        },
        {
          id: 'xss',
          name: '存储型 XSS',
          how: '向埋点、存档与昵称字段写入脚本，检查是否存在将其作为 HTML 渲染的页面。',
          gw: '待打', base: '待打',
          evidence: '目前接口只回 JSON，没有页面回显用户输入，这一招还没找到落点，待打。'
        }
      ]
    },
    {
      id: 'gateway',
      title: '入口代理层',
      intro: '本层检测沿网关链路执行，检测项页面提供执行按钮，复现命令保留给需要复现的场合。',
      items: [
        {
          id: 'direct-origin',
          name: '直连源站',
          how: '绕过网关，直接连接后端 8000 端口。',
          gw: '拦住', base: '打穿',
          evidence: 'docker port symbiont-server-1 输出为空，后端只在容器内 8000；裸奔栈映射到宿主机 18081，curl 直接通。',
          cmd: 'curl.exe -s http://localhost:18081/api/v1/health'
        },
        {
          id: 'direct-db',
          name: '直连数据库',
          how: '从宿主机直接连接数据库 3306 端口。',
          gw: '拦住', base: '打穿',
          evidence: 'docker port symbiont-mysql-1 输出为空；裸奔栈映射到 13307，root/root 能进，直接读到 users 表。',
          cmd: 'docker exec symbiont-baseline-mysql-1 mysql -uroot -proot -e "select count(*) from symbiont.users"'
        },
        {
          id: 'rate-bypass',
          name: '限流绕过',
          how: '更换路径与方法并施加并发，检验是否可绕过 8r/s 限流。',
          gw: '拦住', base: '同网关栈',
          evidence: '限流键是客户端 IP，/api/ 下所有路径共用同一个 zone，换路径不加额度。实测 40 个并发同时放，21 个 200、19 个 429。',
          cmd: 'python scripts/measure_rate.py https://localhost/api/v1/health 40'
        },
        {
          id: 'xff',
          name: '伪造 X-Forwarded-For',
          how: '在请求头中写入 X-Forwarded-For，检验后端是否采信该值。',
          gw: '拦住', base: '打穿',
          evidence: '修复前打穿：网关原来写 $proxy_add_x_forwarded_for，语义是追加，客户端塞的 6.6.6.6 留在最左边，后端 health.py 取的正是最左边那个，回显就是 6.6.6.6。改成 $remote_addr 覆盖写入后重测，同一个请求回显的是 172.18.0.1，也就是网关看到的真实对端；连 X-Real-IP 一起伪造也不认。裸奔栈没有网关，同一个请求照样回 6.6.6.6。',
          cmd: 'curl.exe -k -s -H "X-Forwarded-For: 6.6.6.6" https://localhost:9443/api/v1/health'
        },
        {
          id: 'burst',
          name: '并发打爆',
          how: '同一时刻并发发送 40 个请求，观察限流与拒绝情况。',
          gw: '拦住', base: '同网关栈',
          evidence: '40 个并发里 19 个被 429 挡回，单 IP 并发上限 20，请求不等后端忙起来就被拒了。',
          cmd: 'python scripts/measure_rate.py https://localhost/api/v1/health 40'
        },
        {
          id: 'body',
          name: '超大请求体',
          how: '构造 5 MB 请求体发送至网关，观察是否被拒绝。',
          gw: '拦住', base: '同网关栈',
          evidence: '5,242,880 字节的 PUT 在网关直接回 413，后端日志里没有这一次请求。上限配的是 4m。',
          cmd: 'fsutil file createnew tmp\\5mb.bin 5242880\ncurl.exe -k -s -o NUL -w "%{http_code}" -X PUT --data-binary "@tmp/5mb.bin" -H "X-Device-Id: attack-probe-0003" https://localhost/api/v1/saves/0'
        },
        {
          id: 'slow',
          name: '慢连接',
          how: '分段发送请求头与正文，延长连接占用时间。',
          gw: '待打', base: '待打',
          evidence: '配置里头部和正文各 15 秒超时，还没真拿慢速客户端打过。'
        },
        {
          id: 'tls',
          name: 'TLS 版本',
          how: '以 TLS 1.0 与 TLS 1.1 发起握手，检验协议版本限制。',
          gw: '待打', base: '打穿',
          evidence: '网关只开 TLSv1.2 和 TLSv1.3；裸奔栈整条链路是明文 HTTP。还没做握手实测。'
        },
        {
          id: 'smuggling',
          name: '请求走私',
          how: '同一请求同时携带 Content-Length 与 Transfer-Encoding，观察前后端解析差异。',
          gw: '待打', base: '同网关栈',
          evidence: '还没打。'
        }
      ]
    },
    {
      id: 'app',
      title: '应用层',
      intro: '本层检测接口自身的身份与校验，可在检测项页面直接执行。',
      items: [
        {
          id: 'noauth-write',
          name: '无认证写存档',
          how: '使用任意 X-Device-Id 写入存档，检验是否存在身份校验。',
          gw: '打穿', base: '同网关栈',
          evidence: '实测一个从没出现过的设备 id 第一次 PUT 就回 200，服务端顺手建了匿名账号。',
          cmd: '\'{"save_data":{"hp":1}}\' | Set-Content tmp\\probe_save.json -Encoding ascii\ncurl.exe -k -s -X PUT https://localhost/api/v1/saves/0 -H "Content-Type: application/json" -H "X-Device-Id: attack-probe-0002" -d "@tmp/probe_save.json"'
        },
        {
          id: 'guess-id',
          name: '猜测设备 id 读取存档',
          how: '取得他人设备 id 后读取其存档。',
          gw: '打穿', base: '同网关栈',
          evidence: 'id 只校验长度 8 到 64，没有签名也没有归属校验，知道字符串就能读写。',
          cmd: 'curl.exe -k -s https://localhost/api/v1/saves/0 -H "X-Device-Id: attack-probe-0001"'
        },
        {
          id: 'base-rev',
          name: 'base_rev 竞态覆盖',
          how: '省略 base_rev 重复写入，检验是否覆盖他人存档。',
          gw: '打穿', base: '同网关栈',
          evidence: '实测线上那一版不带 base_rev 的 PUT 直接把 hp 从 1 覆盖成 99，回 200。带 base_rev 0 和带 base_rev 1 也回 200，说明线上镜像里根本没有仓库那段 409 校验：仓库 server/app/routers/saves.py 有 base_rev 检查，跑着的却是 77440c7 那个旧镜像，响应里连 rev 字段都没有。要打 409 得先重建后端镜像。',
          cmd: '\'{"save_data":{"hp":99}}\' | Set-Content tmp\\probe_overwrite.json -Encoding ascii\ncurl.exe -k -s -X PUT https://localhost/api/v1/saves/0 -H "Content-Type: application/json" -H "X-Device-Id: attack-probe-0001" -d "@tmp/probe_overwrite.json"'
        },
        {
          id: 'ts-forge',
          name: '事件时间戳伪造',
          how: '在埋点数据中写入伪造时间戳，检验入库时间是否跟随客户端。',
          gw: '待打', base: '同网关栈',
          evidence: 'events.py 里 created_at 直接拿客户端 ts 换算写入，还没实测。单批 50 条的上限是有的。'
        },
        {
          id: 'bulk-account',
          name: '批量建号',
          how: '循环更换设备 id 写入存档，批量生成匿名账号。',
          gw: '待打', base: '同网关栈',
          evidence: '每个新 id 第一次写入就建号，限流只是按 IP 记速度，换 IP 就没有上限。还没真跑一遍。'
        },
        {
          id: 'docs-leak',
          name: '接口文档泄漏',
          how: '直接访问 /docs 与 /openapi.json，检验接口文档暴露情况。',
          gw: '拦住', base: '打穿',
          evidence: '网关 /docs 回 404，不挂 /api 前缀的路径到不了后端；裸奔栈 /docs 回 200，整套接口和字段都白送。',
          cmd: 'curl.exe -k -s -o NUL -w "%{http_code}`n" https://localhost/docs'
        }
      ]
    },
    {
      id: 'data',
      title: '数据层',
      intro: '本层检查数据库暴露情况，多数检测项仅在没有网关的对照栈上成立。',
      items: [
        {
          id: 'default-pass',
          name: '默认口令',
          how: '使用常见口令尝试登录数据库账号。',
          gw: '拦住', base: '打穿',
          evidence: '网关栈的库不对外，口令由 scripts/gen_env.ps1 随机生成；裸奔栈用 root/root 直接进得去。',
          cmd: 'docker exec symbiont-baseline-mysql-1 mysql -uroot -proot -e "select 1"'
        },
        {
          id: 'enum-users',
          name: '枚举 users 表',
          how: '进入数据库后读取账号表，与设备 id 对照。',
          gw: '拦住', base: '打穿',
          evidence: '裸奔栈 root/root 进去能直接 select users，匿名账号的用户名就是 device: 加设备 id 拼出来的，一读就能对上号。',
          cmd: 'docker exec symbiont-baseline-mysql-1 mysql -uroot -proot -e "select id,username from symbiont.users"'
        },
        {
          id: 'plain-save',
          name: '存档明文',
          how: '检查存档字段是否以明文 JSON 存储。',
          gw: '待打', base: '待打',
          evidence: '表结构里 save_data 是 JSON 类型，还没进库实际看过一条。'
        },
        {
          id: 'secret-default',
          name: 'secret_key 默认值',
          how: '使用源码中的默认密钥签发自定义凭据。',
          gw: '打穿', base: '同网关栈',
          evidence: 'config.py 里 secret_key 默认 dev-secret-change-me，compose 没有注入 SYMBIONT_SECRET_KEY。现在还没有代码拿它签东西，这一条是留着的一颗雷，签名功能一接上就直接可用。'
        }
      ]
    },
    {
      id: 'ops',
      title: '部署与供应链',
      intro: '本层检查容器运行身份、镜像来源与密钥管理。',
      items: [
        {
          id: 'container-user',
          name: '容器权限',
          how: '检查容器运行身份与宿主机目录挂载权限。',
          gw: '拦住', base: '打穿',
          evidence: '网关以 nginx 用户跑，后端以 app 用户跑，uid 10001，都不是 root；挂载只有证书和游戏包，都是只读。裸奔栈没有这层配置，容器默认身份跑着。'
        },
        {
          id: 'log-mask',
          name: '日志脱敏',
          how: '检查访问日志是否记录设备 id、请求体与密钥。',
          gw: '待打', base: '同网关栈',
          evidence: '访问日志格式带 IP、UA、上游地址和耗时，请求体不进日志；还没逐项过一遍。'
        },
        {
          id: 'tag-float',
          name: '镜像 tag 浮动',
          how: '使用浮动镜像 tag 拉取镜像，检验内容是否固定。',
          gw: '拦住', base: '同网关栈',
          evidence: '.env 里 IMAGE_TAG=77440c7-dirty 钉在具体提交上，不走 latest。今天改网关配置时按这个旧 tag 重建了一次网关镜像，镜像内容比 tag 名新，这一处要等下一次统一重建才对得上。'
        },
        {
          id: 'env-plain',
          name: '.env 明文密钥',
          how: '读取 deploy/.env，检验口令是否以明文保存。',
          gw: '打穿', base: '同网关栈',
          evidence: 'deploy/.env 里数据库口令是明文，.gitignore 挡住了不让进仓库，但本机任何进程都能读到。'
        }
      ]
    }
  ]
};
