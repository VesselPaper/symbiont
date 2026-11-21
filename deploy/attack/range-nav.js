/* 左侧导航，所有控制台页面共用。
 *
 * 为什么用脚本生成而不是每页抄一份：五个页面加两个对照页，抄一遍以后改导航要改七处，
 * 迟早漏掉一处。这里只按 body 上的 data-page 认当前页，其余交给浏览器。
 */
(function () {
  var groups = [
    {
      title: '导航',
      items: [
        { key: 'overview', href: '/attack/', label: '检测总览' },
        { key: 'demo', href: '/attack/demo.html', label: '演示流程' },
        { key: 'lab', href: 'http://127.0.0.1:18090/', label: '云端存档' }
      ]
    },
    {
      title: '攻击面',
      items: [
        { key: 'layer-browser', href: '/attack/#layer-browser', label: '浏览器侧' },
        { key: 'layer-gateway', href: '/attack/#layer-gateway', label: '入口代理层' },
        { key: 'layer-app', href: '/attack/#layer-app', label: '应用层' },
        { key: 'layer-data', href: '/attack/#layer-data', label: '数据层' },
        { key: 'layer-ops', href: '/attack/#layer-ops', label: '部署与供应链' }
      ]
    },
    {
      title: '对照页',
      items: [
        { key: 'csrf', href: '/attack/csrf.html', label: '跨站请求伪造' },
        { key: 'clickjack', href: '/attack/clickjacking.html', label: '点击劫持' }
      ]
    }
  ];

  var page = document.body.getAttribute('data-page') || '';
  var html = '<div class="brand"><b>共生之缚</b><span>攻防靶场</span></div><nav>';
  groups.forEach(function (group) {
    html += '<div class="group">' + group.title + '</div>';
    group.items.forEach(function (item) {
      var on = item.key === page ? ' class="on"' : '';
      var blank = item.href.indexOf('http://') === 0 ? ' target="_blank"' : '';
      html += '<a href="' + item.href + '"' + on + blank + '>' + item.label + '</a>';
    });
  });
  html += '</nav><div class="rail-foot">网关 443 · 裸奔对照 18081<br>靶站 18090 · 控制 18082';
  if (window.RANGE_RESULTS && window.RANGE_RESULTS.updated) {
    html += '<br>判定更新 ' + window.RANGE_RESULTS.updated;
  }
  html += '</div>';

  var rail = document.getElementById('rail');
  if (rail) { rail.innerHTML = html; }
})();
