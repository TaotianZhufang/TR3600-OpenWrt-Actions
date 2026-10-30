'use strict';
'require view';
'require rpc';
'require ui';
'require poll';

var callStatus = rpc.declare({ object: 'minieap', method: 'status', expect: { '': {} } });
var callSave = rpc.declare({ object: 'minieap', method: 'save', params: ['username', 'password', 'nic', 'module', 'autorestart'], expect: { '': {} } });
var callSet = rpc.declare({ object: 'minieap', method: 'set_enabled', params: ['enabled'], expect: { '': {} } });
var callRestart = rpc.declare({ object: 'minieap', method: 'restart', expect: { '': {} } });

return view.extend({
	load: function() { return callStatus(); },

	render: function(data) {
		var st = data || {};
		var runState = E('span', {});
		var ipState = E('span', {});
		var user = E('input', { 'class': 'cbi-input-text', value: st.username || '' });
		var pass = E('input', { 'class': 'cbi-input-text', type: 'password' });
		var nic = E('input', { 'class': 'cbi-input-text', value: st.nic || 'eth0' });
		var moduleSel = E('select', { 'class': 'cbi-input-select' },
			['rjv3', 'h3c', 'standard'].map(function(m) {
				return E('option', { value: m, selected: (st.module || 'rjv3') === m }, m);
			}));
		var arOpts = [
			['0', '关闭'], ['30', '每 30 分钟'], ['60', '每 1 小时'],
			['180', '每 3 小时'], ['360', '每 6 小时'], ['720', '每 12 小时'], ['1440', '每天 04:00']
		];
		var arSel = E('select', { 'class': 'cbi-input-select' }, arOpts.map(function(o) {
			return E('option', { value: o[0], selected: String(st.autorestart || '0') === o[0] }, o[1]);
		}));
		var saveBtn = E('button', { 'class': 'cbi-button cbi-button-apply', type: 'button' }, '保存');
		var enableBtn = E('button', { 'class': 'cbi-button cbi-button-apply', type: 'button' }, st.enabled ? '停用服务' : '启用服务');
		var restartBtn = E('button', { 'class': 'cbi-button cbi-button-neutral', type: 'button' }, '重启');

		var show = function(d) {
			if (!d) return;
			st = d;
			runState.textContent = d.running ? '运行中' : '已停止';
			runState.style.color = d.running ? '#2e7d32' : '#c62828';
			ipState.textContent = d.ip ? d.nic + ' → ' + d.ip : '（' + d.nic + ' 没有 IPv4 地址）';
			enableBtn.textContent = d.enabled ? '停用服务' : '启用服务';
			if (document.activeElement !== user) user.value = d.username || '';
			if (document.activeElement !== nic) nic.value = d.nic || 'eth0';
			if (document.activeElement !== moduleSel) moduleSel.value = d.module || 'rjv3';
			if (document.activeElement !== arSel) arSel.value = String(d.autorestart || '0');
			pass.placeholder = d.has_password ? '已设置，留空不改' : '';
		};

		var busy = function(on) {
			[saveBtn, enableBtn, restartBtn].forEach(function(b) { b.disabled = on; });
		};

		var act = function(promise, msg) {
			busy(true);
			promise.then(function(r) {
				show(r);
				ui.addNotification(null, E('p', {}, msg));
			}).catch(function(e) {
				ui.addNotification(null, E('p', {}, e.message || '操作失败'), 'error');
			}).finally(function() { busy(false); });
		};

		saveBtn.addEventListener('click', function() {
			act(callSave(user.value.trim(), pass.value, nic.value.trim(), moduleSel.value, arSel.value), '已保存');
			pass.value = '';
		});
		enableBtn.addEventListener('click', function() {
			act(callSet(st.enabled ? '0' : '1'), st.enabled ? '已停用' : '已启用');
		});
		restartBtn.addEventListener('click', function() {
			act(callRestart(), '已重启');
		});

		show(data);
		poll.add(function() {
			return callStatus().then(show).catch(function() {});
		}, 5);

		var row = function(label, content) {
			return E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, label),
				E('div', { 'class': 'cbi-value-field' }, content)
			]);
		};

		return E('div', {}, [
			E('h2', {}, '校园网 802.1X 认证（minieap）'),
			E('div', { 'class': 'cbi-section' }, [
				row('状态', [runState, ' ', ipState]),
				row('学号 / 用户名', user),
				row('密码', pass),
				row('认证网卡', nic),
				row('认证方式', moduleSel),
				row('自动重启', arSel),
				E('div', { 'class': 'cbi-section-actions' }, [saveBtn, ' ', enableBtn, ' ', restartBtn])
			]),
			E('p', { 'class': 'cbi-section-description' }, '配置写入 /etc/minieap.conf。认证成功后从校园网 DHCP 获取地址；校园网一般接 WAN 口（eth0）。填好账号后点「启用服务」。')
		]);
	}
});
