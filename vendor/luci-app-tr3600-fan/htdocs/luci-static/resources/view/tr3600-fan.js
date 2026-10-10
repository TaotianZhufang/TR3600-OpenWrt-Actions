'use strict';
'require view';
'require fs';
'require ui';
'require poll';

function exec(args) {
	return fs.exec_direct('/usr/sbin/tr3600-fan', args).then(function(res) {
		if (typeof res === 'string')
			return res;
		if (res && res.code)
			throw new Error(res.stderr || _('Fan control command failed'));
		return res && res.stdout ? res.stdout : '';
	});
}

function parseStatus(output) {
	const status = {};
	(output || '').trim().split(/\n/).forEach(function(line) {
		const pos = line.indexOf('=');
		if (pos > 0)
			status[line.slice(0, pos)] = line.slice(pos + 1);
	});
	return status;
}

function temperatureText(value) {
	const temp = Number(value || 0) / 1000;
	return temp > 0 ? temp.toFixed(1) + ' °C' : _('Unavailable');
}

return view.extend({
	load: function() {
		return exec([ 'get' ]).then(parseStatus);
	},

	render: function(initial) {
		const self = this;
		const mode = E('select', { id: 'tr3600-fan-mode' }, [
			E('option', { value: 'auto' }, _('Automatic thermal control')),
			E('option', { value: 'manual' }, _('Manual speed'))
		]);
		const level = E('input', {
			id: 'tr3600-fan-level', type: 'range', min: '0', max: '3', step: '1'
		});
		const levelText = E('span', { class: 'tr3600-fan-level-text' });
		const temperature = E('span');
		const policy = E('span');
		const availability = E('p', { class: 'cbi-section-descr' });
		const apply = E('button', {
			class: 'cbi-button cbi-button-apply',
			click: function() {
				apply.disabled = true;
				const args = mode.value === 'manual' ?
					[ 'set', 'manual', level.value ] : [ 'set', 'auto' ];
				exec(args).then(function() {
					ui.addNotification(null, E('p', _('Fan setting applied.')));
					return self.load();
				}).then(update).catch(function(err) {
					ui.addNotification(null, E('p', err.message || String(err)), 'error');
				}).finally(function() {
					apply.disabled = false;
				});
			}
		}, _('Apply'));

		function levelLabel(value) {
			return [
				_('Off'), _('Low (about 50%)'), _('Medium (about 75%)'), _('High (100%)')
			][Number(value)] || value;
		}

		function update(status) {
			const available = status.available === '1';
			const max = Math.max(0, Number(status.max_level || 3));
			const current = Math.min(max, Math.max(0, Number(status.level || 0)));
			mode.value = status.mode === 'manual' ? 'manual' : 'auto';
			level.max = String(max);
			level.value = String(current);
			levelText.textContent = levelLabel(current);
			level.disabled = !available || mode.value !== 'manual';
			apply.disabled = !available;
			temperature.textContent = temperatureText(status.temp);
			policy.textContent = status.policy || _('Unavailable');
			availability.textContent = available ?
				_('Manual mode uses the kernel user-space thermal policy. At 100 °C the fan is forced to full speed; at 110 °C automatic thermal control is restored.') :
				_('The PWM fan cooling device was not detected.');
		}

		mode.addEventListener('change', function() {
			level.disabled = mode.value !== 'manual';
		});
		level.addEventListener('input', function() {
			levelText.textContent = levelLabel(level.value);
		});

		update(initial);
		poll.add(function() { return self.load().then(update); }, 5);

		return E('div', { class: 'cbi-map' }, [
			E('h2', {}, _('TR3600 Fan Control')),
			E('div', { class: 'cbi-section' }, [
				E('div', { class: 'cbi-value' }, [
					E('label', { class: 'cbi-value-title', for: 'tr3600-fan-mode' }, _('Mode')),
					E('div', { class: 'cbi-value-field' }, mode)
				]),
				E('div', { class: 'cbi-value' }, [
					E('label', { class: 'cbi-value-title', for: 'tr3600-fan-level' }, _('Fan speed')),
					E('div', { class: 'cbi-value-field' }, [ level, levelText ])
				]),
				E('div', { class: 'cbi-value' }, [
					E('span', { class: 'cbi-value-title' }, _('CPU temperature')),
					E('div', { class: 'cbi-value-field' }, temperature)
				]),
				E('div', { class: 'cbi-value' }, [
					E('span', { class: 'cbi-value-title' }, _('Thermal policy')),
					E('div', { class: 'cbi-value-field' }, policy)
				]),
				availability,
				apply
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
