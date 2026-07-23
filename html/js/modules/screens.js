TacticalRTS.prototype.showLoading = function(message) {
    const screen = document.getElementById('loadingScreen');
    const status = document.getElementById('loadingStatusText');
    const tipText = document.getElementById('loadingTipText');

    if (screen) screen.classList.remove('hidden');
    if (status && message) status.textContent = message.toUpperCase();

    // Random Tip Logic
    if (tipText && this.tips && this.tips.length > 0) {
        tipText.textContent = this.tips[Math.floor(Math.random() * this.tips.length)];
    }
};

TacticalRTS.prototype.hideLoading = function() {
    const screen = document.getElementById('loadingScreen');
    if (screen) screen.classList.add('hidden');
};

TacticalRTS.prototype.showScreen = function(screenName, data) {
    // 1. Hide ALL screens first
    document.querySelectorAll('.screen').forEach(screen => {
        screen.classList.add('hidden');
        screen.style.display = 'none'; 
    });

    // ---------------------------------------------------------
    //  THE FIX: DYNAMIC TRANSPARENCY
    // ---------------------------------------------------------
    if (screenName === 'gameUI') {
        // When in-game, the body MUST be transparent to see the 3D world
        document.body.classList.add('game-mode-active');
        document.body.style.backgroundColor = 'transparent'; 
    } else {
        // In the menu, keep it black to hide the sky/bridge
        document.body.classList.remove('game-mode-active');
        document.body.style.backgroundColor = '#000'; 
    }
    // ---------------------------------------------------------

    // 2. Find the target screen
    const targetScreen = document.getElementById(screenName);

    if (targetScreen) {
        // 3. Show the target
        targetScreen.classList.remove('hidden');
        targetScreen.style.display = 'flex'; 
        this.gameState.currentScreen = screenName;
    } else {
        console.error(`RTS ERROR: Could not find screen with ID '${screenName}'`);
        return;
    }

    // 4. Handle specific screen logic
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
