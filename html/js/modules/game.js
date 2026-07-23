// ===========================================================================
//  RTS NUI - Game Module (HUD, Unit Rendering, Objectives, Airstrike)
// ===========================================================================

(function() {
    if (!window.TacticalRTS) return;

    TacticalRTS.startGameUI = function(data) {
        var cpEl = document.getElementById('cpValue');
        if (cpEl) cpEl.textContent = '6000';
        var incEl = document.getElementById('incomeValue');
        if (incEl) incEl.textContent = '+700';

        // Music
        var music = document.getElementById('bgMusic');
        if (music && data.music) {
            music.querySelector('source').src = 'sounds/' + data.music;
            music.load();
            music.play().catch(function() {});
        }
    };

    TacticalRTS.updateResourceDisplay = function(points, income) {
        var cp = document.getElementById('cpValue');
        var inc = document.getElementById('incomeValue');
        if (cp) cp.textContent = Math.floor(points);
        if (inc) inc.textContent = '+' + Math.floor(income || 0);
    };

    TacticalRTS.updateMatchTimer = function(d) {
        var mins = Math.floor(d / 60);
        var secs = d % 60;
        setText('timeValue', String(mins).padStart(2, '0') + ':' + String(secs).padStart(2, '0'));
    };

    // ---- Unit Position Rendering ----
    TacticalRTS.renderUnitPositions = function(units) {
        if (!TacticalRTS.overlayContainer) {
            TacticalRTS.overlayContainer = document.getElementById('game-input-layer');
            if (!TacticalRTS.overlayContainer) return;
        }
        var now = Date.now();
        var sw = window.innerWidth || 1920;
        var sh = window.innerHeight || 1080;

        units.forEach(function(unit) {
            var id = String(unit.id);
            var el = TacticalRTS.unitElements[id];
            if (!el) {
                el = document.createElement('div');
                el.className = 'unit-hitbox';
                el.dataset.id = id;

                el.onmousedown = function(e) {
                    e.stopPropagation();
                    if (e.button === 0 && unit.team === TacticalRTS.gameState.team) {
                        TacticalRTS.fetchNUI('selectUnit', { unitId: parseInt(id) });
                    } else if (e.button === 2 && unit.team !== TacticalRTS.gameState.team) {
                        TacticalRTS.fetchNUI('issueCommand', { type: 'attack', targetId: parseInt(id) });
                        el.style.borderColor = 'red';
                        setTimeout(function() { el.style.borderColor = 'transparent'; }, 200);
                    }
                };

                el.innerHTML =
                    '<div class="unit-health-bar">' +
                        '<div class="unit-health-text"></div>' +
                        '<div class="unit-damage-flash"></div>' +
                        '<div class="unit-health-fill"></div>' +
                    '</div>';
                TacticalRTS.overlayContainer.appendChild(el);
                TacticalRTS.unitElements[id] = el;
            }

            el.style.display = 'block';
            el.dataset.lastSeen = now;

            var x = (unit.x * sw).toFixed(0);
            var y = (unit.y * sh).toFixed(0);
            el.style.transform = 'translate(' + x + 'px, ' + y + 'px)';

            // Health text
            var textEl = el.querySelector('.unit-health-text');
            if (textEl) {
                var minH = 100, effRange = unit.max - minH;
                var effCur = Math.max(0, unit.cur - minH);
                var display = effRange > 0 ? Math.floor((effCur / effRange) * unit.max) : 0;
                textEl.textContent = display + '/' + unit.max;
            }

            // Health bar
            var fill = el.querySelector('.unit-health-fill');
            var flash = el.querySelector('.unit-damage-flash');
            var pct = Math.max(0, Math.min(100, ((unit.cur - 100) / (unit.max - 100)) * 100));
            if (fill) fill.style.width = pct + '%';
            if (flash) flash.style.width = pct + '%';

            // Selection state
            var selected = TacticalRTS.gameState.selectedUnits.includes(parseInt(id));
            el.classList.toggle('selected', selected);
            el.style.borderColor = selected ? '#00ff00' : 'transparent';
        });

        // Cleanup stale
        Object.keys(TacticalRTS.unitElements).forEach(function(key) {
            var el = TacticalRTS.unitElements[key];
            if (parseInt(el.dataset.lastSeen || 0) !== now) {
                if (now - parseInt(el.dataset.lastSeen || 0) > 2000) {
                    el.remove();
                    delete TacticalRTS.unitElements[key];
                } else {
                    el.style.display = 'none';
                }
            }
        });
    };

    // ---- Objectives ----
    TacticalRTS.renderObjectiveMarkers = function(objectives) {
        if (!objectives) return;
        var arr = Array.isArray(objectives) ? objectives : Object.values(objectives);
        if (!TacticalRTS.overlayContainer) {
            TacticalRTS.overlayContainer = document.getElementById('game-input-layer');
        }
        var sw = window.innerWidth || 1920, sh = window.innerHeight || 1080;
        var now = Date.now();

        arr.forEach(function(obj) {
            var elId = 'obj-' + obj.name.replace(/\s+/g, '-');
            var el = document.getElementById(elId);
            if (!el) {
                el = document.createElement('div');
                el.id = elId;
                el.className = 'objective-box';
                el.innerHTML =
                    '<div class="obj-icon"><i class="fas"></i></div>' +
                    '<div class="obj-bar-bg"><div class="obj-bar-fill"></div></div>' +
                    '<div class="obj-name">' + obj.name + '</div>';
                TacticalRTS.overlayContainer.appendChild(el);
            }
            el.dataset.lastSeen = now;
            el.style.display = 'flex';
            el.style.transform = 'translate(' + (obj.x * sw).toFixed(0) + 'px, ' + (obj.y * sh).toFixed(0) + 'px) translate(-50%, -50%)';

            var fill = el.querySelector('.obj-bar-fill');
            if (fill) {
                fill.style.width = (obj.progress || 0) + '%';
                fill.style.backgroundColor = TacticalRTS.getTeamColor(obj.owner || obj.capper || 0);
            }
        });

        document.querySelectorAll('.objective-box').forEach(function(el) {
            if (parseInt(el.dataset.lastSeen) !== now) el.style.display = 'none';
        });
    };

    TacticalRTS.updateObjectiveState = function(d) {
        var mainBar = document.getElementById('objectiveProgress');
        var mainText = document.getElementById('objectiveStatus');
        if (!mainBar || !mainText) return;

        var objs = d;
        var primary = null;
        if (Array.isArray(objs)) {
            primary = objs.find(function(o) { return o.type === 'victory'; });
        } else {
            Object.values(objs).forEach(function(o) { if (o.type === 'victory') primary = o; });
        }

        if (!primary) return;
        var team = primary.controllingTeam || primary.capturingTeam || 0;
        var color = TacticalRTS.getTeamColor(team);
        mainBar.style.width = (primary.progress || 0) + '%';
        mainBar.style.backgroundColor = color;
        mainText.textContent = team === 0 ? 'NEUTRAL ZONE' : (team === TacticalRTS.gameState.team ? 'CONTROLLED' : 'HOSTILE');
        mainText.style.color = color;
    };

    TacticalRTS.getTeamColor = function(team) {
        return team === 1 ? '#4a90e2' : team === 2 ? '#e74c3c' : '#bdc3c7';
    };

    // ---- Airstrike Timer ----
    TacticalRTS.startAirstrikeTimer = function(durationSeconds) {
        var alert = document.getElementById('airstrikeAlert');
        var timer = document.getElementById('asTimerVal');
        var progress = document.getElementById('asProgress');
        if (!alert) return;

        TacticalRTS.stopAirstrikeTimer();
        alert.classList.remove('hidden');

        var remaining = durationSeconds * 1000;
        var total = remaining;
        TacticalRTS._airstrikeInterval = setInterval(function() {
            remaining -= 50;
            if (timer) timer.textContent = (remaining / 1000).toFixed(1);
            if (progress) progress.style.width = ((remaining / total) * 100) + '%';
            if (remaining <= 0) TacticalRTS.stopAirstrikeTimer();
        }, 50);
    };

    TacticalRTS.stopAirstrikeTimer = function() {
        if (TacticalRTS._airstrikeInterval) {
            clearInterval(TacticalRTS._airstrikeInterval);
            TacticalRTS._airstrikeInterval = null;
        }
        var alert = document.getElementById('airstrikeAlert');
        if (alert) alert.classList.add('hidden');
    };

    // ---- Platoon Dock ----
    TacticalRTS.spawnPlatoon = function(slot) {
        TacticalRTS.fetchNUI('spawnPlatoon', {
            platoonIndex: slot,
            x: window.innerWidth / 2 / window.innerWidth,
            y: window.innerHeight / 2 / window.innerHeight,
        });
        TacticalRTS.playSFX('deployUnit');
    };

    TacticalRTS.setPlatoonCooldown = function(slot, cd) {
        var el = document.getElementById('cooldown' + slot);
        if (el) el.style.height = cd > 0 ? '100%' : '0%';
    };

    TacticalRTS.addDeployedPlatoon = function(data) {
        var list = document.getElementById('deployedList');
        var panel = document.getElementById('activeSquadsPanel');
        if (!list || !panel) return;

        panel.classList.remove('hidden-box');
        var div = document.createElement('div');
        div.className = 'deployed-item';
        div.dataset.uuid = data.type;
        div.innerHTML =
            '<div class="d-icon" style="color:' + (data.color || '#fff') + '"><i class="' + (data.icon || 'fas fa-chess-pawn') + '"></i></div>' +
            '<div class="d-info"><div class="d-header"><span class="d-name">' + (data.name || 'SQUAD') + '</span></div></div>';
        list.appendChild(div);
    };

    TacticalRTS.updateSelectionDisplay = function(count, health) {
        setText('selectedCount', count);
        var hpEl = document.getElementById('healthPercent');
        if (hpEl) hpEl.textContent = health || 100;
        var bar = document.getElementById('selectionHealth');
        if (bar) bar.style.width = (health || 100) + '%';
    };

    // ---- Results ----
    TacticalRTS.showResultScreen = function(data) {
        var title = document.getElementById('resultTitle');
        var sub = document.getElementById('resultSubtitle');
        if (title) {
            title.textContent = data.victory ? 'VICTORY' : 'DEFEAT';
            title.style.color = data.victory ? 'var(--green)' : 'var(--red)';
        }
        if (sub) sub.textContent = data.reason ? data.reason.toUpperCase() : 'MATCH COMPLETE';
        setText('resLevel', data.levelData?.level || 1);
        setText('resXPCurrent', data.levelData?.currentXP || 0);
        setText('resXPMax', data.levelData?.requiredXP || 3000);

        var xpBar = document.getElementById('resXPBar');
        if (xpBar) xpBar.style.width = (data.levelData?.percent || 0) + '%';
        setText('xpGainedDisplay', data.score || 0);
        setText('statKills', data.stats?.kills || 0);
        setText('statLosses', data.stats?.unitsLost || 0);
        setText('statTime', formatTime(data.stats?.matchTime || 0));
        setText('statObjectives', data.score || 0);

        if (data.matchData?.nextLobby) {
            TacticalRTS.gameState.lobbyCode = data.matchData.nextLobby;
        }
    };

    TacticalRTS.rematch = function() {
        var code = TacticalRTS.gameState.lobbyCode;
        if (code) {
            TacticalRTS.fetchNUI('joinLobby', { code: code }).then(function(r) {
                if (r && r.success && r.lobbyData) {
                    TacticalRTS.renderLobbyScreen(r);
                    TacticalRTS.showScreen('lobbyScreen');
                }
            });
        }
    };

    TacticalRTS.returnToMenu = function() {
        TacticalRTS.gameState.isInMatch = false;
        TacticalRTS.showScreen('mainMenu');
    };

    // ---- Leaderboard & History ----
    TacticalRTS.openLeaderboard = function() {
        TacticalRTS.showScreen('leaderboardScreen');
        var list = document.getElementById('leaderboardList');
        if (list) list.innerHTML = '<div style="padding:50px;text-align:center;color:#666;">ACCESSING DATABASE...</div>';

        TacticalRTS.fetchNUI('getLeaderboard').then(function(data) {
            if (!list) return;
            list.innerHTML = '';
            if (!data || !data.length) {
                list.innerHTML = '<div style="padding:20px;text-align:center">No data available</div>';
                return;
            }
            data.forEach(function(p, i) {
                var rank = i + 1;
                var row = document.createElement('div');
                row.className = 'leaderboard-row rank-' + (rank <= 3 ? rank : 'normal');
                var icon = rank === 1 ? '<i class="fas fa-trophy"></i>' : rank === 2 ? '<i class="fas fa-medal"></i>' : '<span class="rank-num">#' + rank + '</span>';
                row.innerHTML =
                    '<div class="lb-rank">' + icon + '</div>' +
                    '<div class="lb-name"><span class="lvl-tag">LVL ' + (p.level || 1) + '</span> ' + (p.name || 'Unknown') + '</div>' +
                    '<div class="lb-stat">' + (p.wins || 0) + ' <span class="sub-label">WINS</span></div>' +
                    '<div class="lb-stat">' + (p.kills || 0) + ' <span class="sub-label">KILLS</span></div>' +
                    '<div class="lb-stat score-val">' + (p.score || 0).toLocaleString() + '</div>';
                list.appendChild(row);
            });
        });
    };

    TacticalRTS.openHistory = function() {
        TacticalRTS.showScreen('historyScreen');
        var list = document.getElementById('historyList');
        if (list) list.innerHTML = '<div style="padding:20px;text-align:center">Retrieving logs...</div>';

        TacticalRTS.fetchNUI('getHistory').then(function(data) {
            if (!list) return;
            list.innerHTML = '';
            if (!data || !data.length) {
                list.innerHTML = '<div style="padding:20px;text-align:center">No combat history found.</div>';
                return;
            }
            data.forEach(function(m) {
                var isWin = m.result === 'WIN';
                var item = document.createElement('div');
                item.className = 'history-item ' + (isWin ? 'win' : 'loss');
                item.innerHTML =
                    '<div class="history-info">' +
                        '<div class="map-label">' + (m.map_name || '').toUpperCase().replace('_', ' ') + '</div>' +
                        '<div class="opponent-tag"><span class="vs-text">VS</span> ' + (m.opponent_name || 'Unknown') + '</div>' +
                        '<div class="match-date">' + new Date(m.date_played).toLocaleDateString() + '</div>' +
                    '</div>' +
                    '<div class="history-result"><span style="color:' + (isWin ? 'var(--green)' : 'var(--red)') + '">' + (isWin ? 'VICTORY' : 'DEFEAT') + '</span></div>' +
                    '<div class="history-stats"><span class="label">KILLS</span><span class="value">' + (m.kills || 0) + '</span></div>';
                list.appendChild(item);
            });
        });
    };

    // ---- Helpers ----
    function setText(id, val) {
        var el = document.getElementById(id);
        if (el) el.textContent = val;
    }

    function formatTime(seconds) {
        var m = Math.floor(seconds / 60);
        var s = seconds % 60;
        return String(m).padStart(2, '0') + ':' + String(s).padStart(2, '0');
    }
})();
