'use strict';
'require view';
'require rpc';
'require ui';
'require poll';

var callStatus = rpc.declare({ object: 'homebox', method: 'status', expect: { '': {} } });
var callSet = rpc.declare({ object: 'homebox', method: 'set_enabled', params: ['enabled'], expect: { '': {} } });

return view.extend({
	load: function() { return callStatus(); },

	render: function(data) {
		var statusText = E('span', {});
		var checkbox = E('input', { type: 'checkbox', 'class': 'cbi-input-checkbox' });

		function refresh(d) {
			if (!d) return;
			checkbox.checked = !!d.enabled;
			statusText.textContent = d.running ? '运行中' : '已停止';
			statusText.style.color = d.running ? '#2e7d32' : '#c62828';
		}

		checkbox.addEventListener('change', function() {
			var want = checkbox.checked;
			checkbox.disabled = true;
			callSet(want).then(function(r) {
				refresh(r);
				ui.addNotification(null, E('p', {}, want ? '已启用并启动 homebox' : '已停用 homebox'));
			}).catch(function(e) {
				ui.addNotification(null, E('p', {}, e.message || '操作失败'), 'error');
				refresh(data);
			}).finally(function() { checkbox.disabled = false; });
		});

		refresh(data);
		poll.add(function() {
			return callStatus().then(refresh).catch(function() {});
		}, 5);

		var host = window.location.hostname || '192.168.1.1';
		var url = 'http://' + host + ':3300';

		return E('div', {}, [
			E('h2', {}, 'homebox 测速服务'),
			E('div', { 'class': 'cbi-section' }, [
				E('div', { 'class': 'cbi-value' }, [
					E('label', { 'class': 'cbi-value-title' }, '启用'),
					E('div', { 'class': 'cbi-value-field' }, [ checkbox, ' ', E('span', {}, '开机自启并立即启动') ])
				]),
				E('div', { 'class': 'cbi-value' }, [
					E('label', { 'class': 'cbi-value-title' }, '当前状态'),
					E('div', { 'class': 'cbi-value-field' }, statusText)
				]),
				E('div', { 'class': 'cbi-value' }, [
					E('label', { 'class': 'cbi-value-title' }, '访问地址'),
					E('div', { 'class': 'cbi-value-field' }, E('a', { href: url, target: '_blank' }, url))
				])
			])
		]);
	}
});
