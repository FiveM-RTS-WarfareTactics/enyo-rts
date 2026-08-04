TacticalRTS.prototype.showLoading = function(message) {
    const screen = document.getElementById('loadingScreen');
    const status = document.getElementById('loadingStatusText');
    const tipText = document.getElementById('loadingTipText');

    if (screen) screen.classList.remove('hidden');
    if (status && message) status.textContent = message.toUpperCase();

    if (tipText && this.tips && this.tips.length > 0) {
        tipText.textContent = this.tips[Math.floor(Math.random() * this.tips.length)];
    }
};

TacticalRTS.prototype.hideLoading = function() {
    const screen = document.getElementById('loadingScreen');
    if (screen) screen.classList.add('hidden');
};

TacticalRTS.prototype.showScreen = function(screenName, data) {
    document.querySelectorAll('.screen').forEach(screen => {
        screen.classList.add('hidden');
        screen.style.display = 'none'; 
    });

    if (screenName === 'gameUI') {
        document.body.classList.add('game-mode-active');
        document.body.style.backgroundColor = 'transparent'; 
    } else {
        document.body.classList.remove('game-mode-active');
        document.body.style.backgroundColor = '#000'; 
    }

    const targetScreen = document.getElementById(screenName);

    if (targetScreen) {
        targetScreen.classList.remove('hidden');
        targetScreen.style.display = 'flex'; 
        this.gameState.currentScreen = screenName;
    } else {
        console.error(`RTS ERROR: Could not find screen with ID '${screenName}'`);
        return;
    }

    if (screenName === 'mainMenu' && data) {
        if (data.serverStats) {
            this.updateServerInfo(data.serverStats);
            if (data.serverStats.myStats) {
                this.updateStats(data.serverStats.myStats);
            }
        }
    } else if (screenName === 'lobbyScreen') {
        this.initializePlatoonBuilder();
    } else if (screenName === 'gameUI') {
        this.initializeGameUI();
    }
};