// ===========================================================================
//  RTS NUI - Screen Management & Main Menu
// ===========================================================================

(function() {
    if (!window.TacticalRTS) return;

    var screens = ['loadingScreen', 'mainMenu', 'lobbyScreen', 'gameUI', 'resultScreen', 'leaderboardScreen', 'historyScreen'];

    TacticalRTS.showScreen = function(name, data) {
        screens.forEach(function(id) {
            var el = document.getElementById(id);
            if (el) el.classList.add('hidden');
        });

        var target = document.getElementById(name);
        if (target) {
            target.classList.remove('hidden');
            TacticalRTS.gameState.currentScreen = name;
        }

        if (name === 'mainMenu') {
            TacticalRTS.hideLoading();
            TacticalRTS.fetchNUI('getGlobalStats', {}).then(function(s) {
                if (!s) return;
                var stats = s.myStats || {};
                setText('commanderNameDisplay', 'COMMANDER: ' + (stats.name || 'UNKNOWN'));
                setText('profileLevelBadge', 'LVL ' + (stats.levelData?.level || 1));
                setText('statWins', stats.wins || 0);
                setText('statKillsTotal', stats.kills || 0);
                setText('statMatches', stats.matches || 0);
                setText('statScore', stats.score || 0);
                setText('xpCurrent', stats.levelData?.currentXP || 0);
                setText('xpMax', stats.levelData?.requiredXP || 3000);

                var xpBar = document.getElementById('profileXPBar');
                if (xpBar) xpBar.style.width = (stats.levelData?.percent || 0) + '%';
            });
        }
    };

    TacticalRTS.hideLoading = function() {
        var el = document.getElementById('loadingScreen');
        if (el) el.classList.add('hidden');
    };

    TacticalRTS.startLiveStatsPoller = function() {
        if (TacticalRTS._livePoll) clearInterval(TacticalRTS._livePoll);
        TacticalRTS._livePoll = setInterval(function() {
            if (TacticalRTS.gameState.currentScreen === 'mainMenu' || TacticalRTS.gameState.currentScreen === 'lobbyScreen') {
                TacticalRTS.fetchNUI('requestLiveStats', {}).then(function(stats) {
                    if (!stats) return;
                    setText('playerCount', stats.onlineCount || 0);
                    setText('activeBattles', stats.activeBattles || 0);
                    setText('serverPing', stats.ping || '-');
                    setText('estTime', stats.estimatedWait || 'CALCULATING');
                });
            }
        }, 5000);
    };

    TacticalRTS.buildMapCarousel = function() {
        var bg = document.getElementById('carouselBg');
        var name = document.getElementById('carouselMapName');
        var keys = TacticalRTS.mapKeys;
        if (!keys.length || !bg) return;

        var idx = TacticalRTS.currentMapIndex % keys.length;
        var map = TacticalRTS.mapData[keys[idx]];
        if (!map) return;

        bg.style.backgroundImage = 'url(images/maps/' + (map.thumbnail || 'grapeseed.png') + ')';
        if (name) name.textContent = map.name || keys[idx];
    };

    TacticalRTS.nextMap = function() {
        TacticalRTS.currentMapIndex = (TacticalRTS.currentMapIndex + 1) % TacticalRTS.mapKeys.length;
        TacticalRTS.currentMap = TacticalRTS.mapKeys[TacticalRTS.currentMapIndex];
        TacticalRTS.buildMapCarousel();
        TacticalRTS.playSFX('menuClick');
    };

    TacticalRTS.prevMap = function() {
        TacticalRTS.currentMapIndex = (TacticalRTS.currentMapIndex - 1 + TacticalRTS.mapKeys.length) % TacticalRTS.mapKeys.length;
        TacticalRTS.currentMap = TacticalRTS.mapKeys[TacticalRTS.currentMapIndex];
        TacticalRTS.buildMapCarousel();
        TacticalRTS.playSFX('menuClick');
    };

    function setText(id, val) {
        var el = document.getElementById(id);
        if (el) el.textContent = val;
    }
})();
