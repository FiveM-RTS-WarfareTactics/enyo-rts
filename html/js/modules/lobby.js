// ===========================================================================
//  RTS NUI - Lobby Module (Create/Join, Platoon Builder, Drag & Drop)
// ===========================================================================

(function() {
    if (!window.TacticalRTS) return;

    // ---- Lobby Screen Rendering ----
    TacticalRTS.renderLobbyScreen = function(data) {
        var d = data.lobbyData || data;
        setText('mapName', (TacticalRTS.mapData[TacticalRTS.currentMap]?.name || 'UNKNOWN').toUpperCase());
        setText('hostName', d.hostName || 'COMMANDER');
        setText('lobbyCodeDisplay', TacticalRTS.gameState.lobbyCode || '------');
        TacticalRTS.renderLobbyPlayers(d);

        // Map preview
        var preview = document.getElementById('mapPreview');
        if (preview && TacticalRTS.mapData[TacticalRTS.currentMap]) {
            preview.style.backgroundImage = 'url(images/maps/' + (TacticalRTS.mapData[TacticalRTS.currentMap].thumbnail || 'grapeseed.png') + ')';
        }
        setText('previewMapName', (TacticalRTS.mapData[TacticalRTS.currentMap]?.name || 'UNKNOWN').toUpperCase());

        // Host bot controls
        var hostControls = document.getElementById('hostBotControls');
        if (hostControls) hostControls.style.display = d.isHost ? 'block' : 'none';

        TacticalRTS.resetLobbyState();
    };

    TacticalRTS.renderLobbyPlayers = function(data) {
        var list = document.getElementById('playersList');
        if (!list) return;

        var players = data.playersData || [];
        setText('playersCount', players.length + '/' + (data.maxPlayers || 2));
        list.innerHTML = '';

        players.forEach(function(p) {
            var div = document.createElement('div');
            div.className = 'player-slot';
            div.innerHTML =
                '<div class="player-avatar"><i class="fas fa-user-astronaut"></i></div>' +
                '<div class="player-name">' + (p.name || 'Unknown') + '</div>' +
                '<div class="player-status ' + (p.isReady ? 'ready' : 'waiting') + '">' +
                    (p.isReady ? 'READY' : 'WAITING') +
                '</div>' +
                (p.isHost ? '<div class="host-badge">HOST</div>' : '');
            list.appendChild(div);
        });

        // Update bot button
        var btn = document.getElementById('toggleBotBtn');
        if (!btn) return;
        var hasBot = players.some(function(p) { return p.name && p.name.includes('[AI]'); });
        if (hasBot) {
            btn.dataset.action = 'kick';
            btn.innerHTML = '<i class="fas fa-user-slash"></i> REMOVE A.I. COMMANDER';
        } else {
            btn.dataset.action = 'add';
            btn.innerHTML = '<i class="fas fa-robot"></i> ADD A.I. COMMANDER';
        }

        // Ready status text
        var allReady = players.every(function(p) { return p.isReady; });
        var full = players.length >= (data.maxPlayers || 2);
        setText('readyStatusText', full && allReady ? 'MATCH LAUNCHING' : 'AWAITING COMMANDERS');
    };

    // ---- Lobby Actions ----
    TacticalRTS.createLobby = function() {
        TacticalRTS.fetchNUI('createLobby', { map: TacticalRTS.currentMap });
    };

    TacticalRTS.joinLobby = function() {
        var input = document.getElementById('lobbyCodeInput');
        var code = input ? input.value : '';
        TacticalRTS.fetchNUI('joinLobby', { code: code }).then(function(r) {
            if (r && r.success) {
                TacticalRTS.gameState.lobbyCode = code.toUpperCase();
                if (r.lobbyData) TacticalRTS.renderLobbyScreen(r);
                TacticalRTS.showScreen('lobbyScreen');
            } else {
                TacticalRTS.showNotification(r?.message || 'Lobby not found', 'error');
            }
        });
    };

    TacticalRTS.leaveLobby = function() {
        TacticalRTS.fetchNUI('leaveLobby', {});
        TacticalRTS.gameState.isInLobby = false;
        TacticalRTS.gameState.playerReady = false;
    };

    TacticalRTS.toggleReady = function() {
        TacticalRTS.gameState.playerReady = !TacticalRTS.gameState.playerReady;
        TacticalRTS.fetchNUI('readyToggle', { ready: TacticalRTS.gameState.playerReady });
        var btn = document.getElementById('readyToggle');
        if (btn) {
            btn.classList.toggle('ready', TacticalRTS.gameState.playerReady);
            btn.innerHTML = TacticalRTS.gameState.playerReady
                ? '<i class="fas fa-check-circle"></i><span>READY</span>'
                : '<i class="fas fa-play-circle"></i><span>READY</span>';
        }
    };

    TacticalRTS.copyLobbyCode = function() {
        var code = TacticalRTS.gameState.lobbyCode;
        if (!code) return;
        navigator.clipboard.writeText(code).catch(function() {});
        TacticalRTS.showNotification('Code copied: ' + code, 'success');
    };

    TacticalRTS.resetLobbyState = function() {
        TacticalRTS.gameState.playerReady = false;
        var btn = document.getElementById('readyToggle');
        if (btn) {
            btn.classList.remove('ready');
            btn.innerHTML = '<i class="fas fa-play-circle"></i><span>READY</span>';
        }
    };

    TacticalRTS.startLobbyCountdown = function(d) {
        var container = document.getElementById('countdownContainer');
        if (container) container.style.display = 'block';
        var timer = document.getElementById('countdownTimer');
        if (!timer) return;

        var time = d || Config?.Lobby?.ReadyCheckDuration || 5;
        if (TacticalRTS.countdownInterval) clearInterval(TacticalRTS.countdownInterval);
        TacticalRTS.countdownInterval = setInterval(function() {
            if (timer) timer.textContent = time;
            TacticalRTS.playSFX('countdownBip');
            time--;
            if (time < 0) {
                clearInterval(TacticalRTS.countdownInterval);
                if (container) container.style.display = 'none';
            }
        }, 1000);
    };

    TacticalRTS.abortCountdown = function() {
        if (TacticalRTS.countdownInterval) clearInterval(TacticalRTS.countdownInterval);
        var container = document.getElementById('countdownContainer');
        if (container) container.style.display = 'none';
    };

    // ---- Matchmaking ----
    TacticalRTS.quickMatch = function() {
        if (TacticalRTS.isQueued) {
            TacticalRTS.fetchNUI('leaveMatchmaking', {});
            TacticalRTS.isQueued = false;
            var btn = document.getElementById('quickMatch');
            if (btn) btn.innerHTML = '<span>FIND MATCH</span> <i class="fas fa-chevron-right"></i>';
            return;
        }
        TacticalRTS.isQueued = true;
        var btn = document.getElementById('quickMatch');
        if (btn) btn.innerHTML = '<span>CANCEL SEARCH</span> <i class="fas fa-times"></i>';
        TacticalRTS.fetchNUI('joinMatchmaking', {});
    };

    TacticalRTS.surrenderGame = function() {
        TacticalRTS.closeModal('settingsModal');
        TacticalRTS.fetchNUI('surrenderMatch', {});
    };

    TacticalRTS.exitGame = function() {
        TacticalRTS.fetchNUI('disconnectPlayer', {});
    };

    function setText(id, val) {
        var el = document.getElementById(id);
        if (el) el.textContent = val;
    }
})();
