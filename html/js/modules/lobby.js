TacticalRTS.prototype.addBotToLobby = function() {
    this.fetchNUI('addBot', {});
    this.playSFX('menuClick');
};

TacticalRTS.prototype.kickBotFromLobby = function() {
    this.fetchNUI('kickBot', {});
    this.playSFX('menuClick');
};

TacticalRTS.prototype.resetLobbyState = function() {
    // 1. Reset Internal State variable
    this.gameState.playerReady = false;

    // 2. Reset Button Visuals
    const readyBtn = document.getElementById('readyToggle');
    const indicator = document.getElementById('readyIndicator');
    const statusText = document.getElementById('readyStatusText');

    // Reset Main Button to "Click to Ready" state
    if (readyBtn) {
        readyBtn.innerHTML = '<i class="fas fa-play-circle"></i><span>READY</span>'; // icon if you wish: <i class="fas fa-play-circle"></i> 
        readyBtn.classList.remove('ready'); // Removes the green/active styling
    }

    // Reset small indicator above button
    if (indicator) {
        indicator.innerHTML = ''; // Or your preferred icon
        indicator.classList.remove('ready');
    }

    // Reset Text status
    if (statusText) statusText.textContent = 'AWAITING COMMANDERS';
};

TacticalRTS.prototype.abortCountdown = function() {
    // 1. Kill the interval timer
    if (this.countdownInterval) {
        clearInterval(this.countdownInterval);
        this.countdownInterval = null;
    }
    
    // 2. Hide the UI element and reset text
    const countdownContainer = document.getElementById('countdownContainer');
    const timer = document.getElementById('countdownTimer');
    
    if (countdownContainer) countdownContainer.style.display = 'none';
    if (timer) timer.textContent = '5';
    
    // 3. THE FIX: Physically pause the audio track so the beeping stops instantly!
    if (this.sounds && this.sounds.countdownBip) {
        this.sounds.countdownBip.pause();
        this.sounds.countdownBip.currentTime = 0;
    }
    
    // 4. Notify Player
    this.showNotification('Launch sequence aborted.', 'warning');
};

TacticalRTS.prototype.handleLobbyCreated = function(data) {
    // THE FIX: Set host status immediately!
    this.gameState.isHost = data.isHost || true;
    const playerLevel = (this.myStats && this.myStats.levelData) ? this.myStats.levelData.level : 1;
    this.weight = this.calculateAllowedWeight(
        playerLevel,
        data.weight // { starts, capped, milestone }
    );
    const lobbyCodeDisplay = document.getElementById('lobbyCodeDisplay');
    const hostName = document.getElementById('hostName');
    const mapName = document.getElementById('mapName');

    if (lobbyCodeDisplay) lobbyCodeDisplay.textContent = data.code || '------';
    if (hostName) hostName.textContent = data.hostName || 'Host';
    if (mapName) mapName.textContent = data.map ? data.map.toUpperCase().replace('_', ' ') : 'DESERT ARENA';

    this.currentMap = data.map || 'grapeseed';
    this.updateMapPreview(this.currentMap);
    this.showScreen('lobbyScreen');
    this.resetLobbyState();

    this.updateLobbyPlayers(data); 

    // --- SMART PLATOON LOGIC ---
    if (this.platoonData && Object.keys(this.platoonData).length > 0) {
        // A. REMATCH: Restore previous loadout
        for (let slot = 1; slot <= 5; slot++) {
            this.renderSlotContent(slot);
        }
        this.updateTotalWeight();
        this.updateSlotWeights();
        this.savePlatoons();
    } else {
        // B. FRESH MATCH: Manually wipe the HTML slots empty (No notification)
        for (let slot = 1; slot <= 5; slot++) {
            const slotContent = document.getElementById(`slot${slot}Content`);
            if (slotContent) slotContent.innerHTML = '';
        }
        this.updateTotalWeight();
        this.updateSlotWeights();
    }
};

TacticalRTS.prototype.handleLobbyJoined = function(data) {
    // --- [NEW] CLEAR MODAL IF MATCH FOUND ---
    if (this.aiPromptTimer) clearTimeout(this.aiPromptTimer);
    const aiModal = document.getElementById('aiPromptModal');
    if (aiModal) aiModal.classList.add('hidden');

    // THE FIX: Set host status immediately!
    this.gameState.isHost = data.isHost;
    // ... (rest of the function continues normally)
    
    const playerLevel = (this.myStats && this.myStats.levelData) ? this.myStats.levelData.level : 1;
    this.weight = this.calculateAllowedWeight(
        playerLevel,
        data.weight 
    );
    
    const code = data.code || (data.lobbyData && data.lobbyData.code) || '------';
    const host = data.hostName || (data.lobbyData && data.lobbyData.hostName) || 'Unknown';
    const map = data.map || (data.lobbyData && data.lobbyData.map) || 'grapeseed';

    const lobbyCodeDisplay = document.getElementById('lobbyCodeDisplay');
    const hostName = document.getElementById('hostName');
    const mapName = document.getElementById('mapName');

    if (lobbyCodeDisplay) lobbyCodeDisplay.textContent = code;
    if (hostName) hostName.textContent = host;
    if (mapName) mapName.textContent = map.toUpperCase().replace('_', ' ');

    this.gameState.lobbyCode = code; 
    this.currentMap = map;
    this.updateMapPreview(this.currentMap);

    this.updateLobbyPlayers(data.lobbyData || data);

    this.showScreen('lobbyScreen');
    this.resetLobbyState();
    
    // --- SMART PLATOON LOGIC ---
    if (this.platoonData && Object.keys(this.platoonData).length > 0) {
        // A. REMATCH: Restore previous loadout
        for (let slot = 1; slot <= 5; slot++) {
            this.renderSlotContent(slot);
        }
        this.updateTotalWeight();
        this.updateSlotWeights();
        this.savePlatoons();
    } else {
        // B. FRESH MATCH: Manually wipe the HTML slots empty (No notification)
        for (let slot = 1; slot <= 5; slot++) {
            const slotContent = document.getElementById(`slot${slot}Content`);
            if (slotContent) slotContent.innerHTML = '';
        }
        this.updateTotalWeight();
        this.updateSlotWeights();
    }
};

TacticalRTS.prototype.updateLobbyPlayers = function(data) {
    const playersList = document.getElementById('playersList');
    const playersCount = document.getElementById('playersCount');
    const botControls = document.getElementById('hostBotControls');

    if (!playersList) return;
    playersList.innerHTML = '';

    // 1. Parse Players & Detect if Bot is present
    let players = [];
    if (data.playersData) {
        players = data.playersData;
    } else if (data.playerNames) {
        players = data.playerNames.map((name, i) => ({ name: name, isReady: false, isHost: i === 0 }));
    }

    let hasBot = false;
    players.forEach(p => { if (p.name.includes('[AI]')) hasBot = true; });

    // 2. Manage the Smart Toggle Button
    if (botControls) {
        if (this.gameState.isHost) {
            botControls.style.display = 'block';
            const toggleBtn = document.getElementById('toggleBotBtn');
            
            if (toggleBtn) {
                // Swap Button visuals based on Bot presence
                if (hasBot) {
                    toggleBtn.dataset.action = 'kick';
                    toggleBtn.innerHTML = '<i class="fas fa-ban"></i> KICK A.I. COMMANDER';
                    toggleBtn.className = 'btn btn-danger';
                } else {
                    toggleBtn.dataset.action = 'add';
                    toggleBtn.innerHTML = '<i class="fas fa-robot"></i> ADD A.I. COMMANDER';
                    toggleBtn.className = 'btn btn-secondary';
                }

                // Lock button if the host is READY so they can't glitch the start sequence
                if (this.gameState.playerReady) {
                    toggleBtn.style.opacity = '0.5';
                    toggleBtn.style.pointerEvents = 'none';
                } else {
                    toggleBtn.style.opacity = '1';
                    toggleBtn.style.pointerEvents = 'auto';
                }
            }
        } else {
            botControls.style.display = 'none';
        }
    }

    if (playersCount) playersCount.textContent = `${players.length}/2`;

    // 3. Render Player List
    players.forEach((p) => {
        const playerItem = document.createElement('div');
        playerItem.className = 'player-item';

        const isBot = p.name.includes('[AI]');
        const avatarContent = isBot ? '<i class="fas fa-robot"></i>' : p.name.charAt(0);
        const statusClass = p.isReady ? 'status-ready' : 'status-waiting';
        const statusText = p.isReady ? 'READY' : 'NOT READY';

        playerItem.innerHTML = `
        <div class="player-avatar" style="${isBot ? 'color: var(--cyan); border-color: var(--cyan);' : ''}">${avatarContent}</div>
        <div class="player-info">
            <div class="player-name">
                ${p.name} 
                ${p.isHost ? '<i class="fas fa-crown" style="color: #f1c40f; margin-left: 5px;"></i>' : ''}
            </div>
            <div class="player-status">
                <span class="status-dot ${statusClass}"></span>
                <span>${statusText}</span>
            </div>
        </div>
        `;
        playersList.appendChild(playerItem);
    });
};

TacticalRTS.prototype.updatePlayerReadyStatus = function(playerId, isReady) {
    const playerItems = document.querySelectorAll('.player-item');
    if (playerItems[playerId]) {
        const statusDot = playerItems[playerId].querySelector('.status-dot');
        const statusText = playerItems[playerId].querySelector('.player-status span:last-child');

        if (statusDot) {
            statusDot.classList.remove('status-waiting', 'status-ready');
            statusDot.classList.add(isReady ? 'status-ready' : 'status-waiting');
        }

        if (statusText) {
            statusText.textContent = isReady ? 'READY' : 'AWAITING';
        }
    }
};

TacticalRTS.prototype.fallbackCopy = function(text) {
    const textArea = document.createElement("textarea");
    textArea.value = text;
    document.body.appendChild(textArea);
    textArea.select();
    try {
        document.execCommand('copy'); // Legacy command that works in FiveM
        this.showNotification('Code copied!', 'success');
    } catch (err) {
        this.showNotification('Could not copy code', 'error');
    }
    document.body.removeChild(textArea);
};


