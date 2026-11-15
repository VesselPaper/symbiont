/* 载入页逻辑：由 scripts/export_web.ps1 内联进导出产物的 index.html
 *
 * 只做搬运：读 Godot 自己更新的 <progress id="status-progress">，把数值画到我们自己的
 * 进度条上。不碰引擎启动流程，引擎失败时 Godot 的 notice 照常显示。
 */
(function () {
	var nativeBar = null;
	var fill = null;
	var pct = null;
	var title = null;
	var started = false;

	function bytes(n) {
		if (!n) { return ''; }
		if (n >= 1048576) { return (n / 1048576).toFixed(1) + ' MB'; }
		if (n >= 1024) { return (n / 1024).toFixed(0) + ' KB'; }
		return n + ' B';
	}

	function build() {
		var overlay = document.getElementById('status');
		if (!overlay || overlay.dataset.symReady === '1') { return; }
		overlay.dataset.symReady = '1';
		nativeBar = document.getElementById('status-progress');

		var wrap = document.createElement('div');
		wrap.id = 'sym-load';

		title = document.createElement('div');
		title.id = 'sym-title';
		title.textContent = '共生之缚';

		var sub = document.createElement('div');
		sub.id = 'sym-sub';
		sub.appendChild(document.createTextNode('正在载入'));
		var dots = document.createElement('span');
		dots.id = 'sym-dots';
		dots.textContent = '···';
		sub.appendChild(dots);

		var track = document.createElement('div');
		track.id = 'sym-track';
		fill = document.createElement('div');
		fill.id = 'sym-fill';
		track.appendChild(fill);

		pct = document.createElement('div');
		pct.id = 'sym-pct';
		pct.textContent = '准备中';

		var hint = document.createElement('div');
		hint.id = 'sym-hint';
		hint.textContent = '首次载入约 100 MB，之后走缓存';

		wrap.appendChild(title);
		wrap.appendChild(sub);
		wrap.appendChild(track);
		wrap.appendChild(pct);
		wrap.appendChild(hint);
		overlay.appendChild(wrap);
	}

	function tick() {
		// 加载完成后 Godot 会把整个 #status 移除，这时候停下来
		if (!document.getElementById('status')) { return; }

		if (!started) { build(); started = true; }

		if (nativeBar && nativeBar.hasAttribute('value') && nativeBar.max > 0) {
			var ratio = Math.min(1, nativeBar.value / nativeBar.max);
			fill.style.width = (ratio * 100).toFixed(1) + '%';
			pct.textContent = Math.round(ratio * 100) + '%　' +
				bytes(nativeBar.value) + ' / ' + bytes(nativeBar.max);
		}

		requestAnimationFrame(tick);
	}

	if (document.readyState === 'loading') {
		document.addEventListener('DOMContentLoaded', tick);
	} else {
		tick();
	}
}());
