// ===========================================================================
//  RTS NUI - Event Bindings & Input
// ===========================================================================

(function() {
    if (!window.TacticalRTS) return;

    TacticalRTS.bindEvents = function() {
        var doc = document;

        // Hover sounds
        doc.addEventListener('mouseover', function(e) {
            if (e.target.matches('.btn, .unit-card, .quickbar-slot, .platoon-unit, .deployed-item, .history-item')) {
                TacticalRTS.playSFX('hover');
            }
        });

        // Music volume
        var musicSlider = doc.getElementById('musicVolume');
        if (musicSlider) {
            musicSlider.addEventListener('input', function(e) {
                var music = doc.getElementById('bgMusic');
                if (music) music.volume = e.target.value / 100;
            });
        }

        // SFX volume
        var sfxSlider = doc.getElementById('sfxVolume');
        if (sfxSlider) {
            sfxSlider.addEventListener('input', function(e) {
                var vol = e.target.value / 100;
                Object.values(TacticalRTS.sounds).forEach(function(s) { s.volume = vol; });
            });
            sfxSlider.addEventListener('change', function() {
                TacticalRTS.playSFX('menuClick');
            });
        }

        // Click delegation
        doc.addEventListener('click', function(e) {
            var t = e.target;

            t.closest('#quickMatch')      && TacticalRTS.quickMatch();
            t.closest('#createLobby')     && TacticalRTS.createLobby();
            t.closest('#joinLobby')       && TacticalRTS.joinLobby();
            t.closest('#settingsBtn')     && TacticalRTS.openSettings();
            t.closest('#helpBtn')         && TacticalRTS.openHelp();
            t.closest('#exitBtn')         && TacticalRTS.exitGame();

            t.closest('#mapNext')         && TacticalRTS.nextMap();
            t.closest('#mapPrev')         && TacticalRTS.prevMap();

            t.closest('#leaveLobby')      && TacticalRTS.leaveLobby();
            t.closest('#copyCode')        && TacticalRTS.copyLobbyCode();
            t.closest('#readyToggle')     && TacticalRTS.toggleReady();
            t.closest('#clearAll')        && TacticalRTS.clearAllPlatoons();

            t.closest('#viewLeaderboard') && TacticalRTS.openLeaderboard();
            t.closest('#viewHistory')     && TacticalRTS.openHistory();

            t.closest('#rematchBtn')      && TacticalRTS.rematch();
            t.closest('#returnToMenuBtn') && TacticalRTS.returnToMenu();

            t.closest('#midGameSettings') && TacticalRTS.openSettings();
            t.closest('#surrenderBtn')    && TacticalRTS.surrenderGame();

            t.closest('#closeSettings')   && TacticalRTS.closeModal('settingsModal');
            t.closest('#closeHelp')       && TacticalRTS.closeModal('helpModal');
            t.closest('#saveSettings')    && TacticalRTS.saveSettings();

            t.closest('#toggleBotBtn')    && TacticalRTS.toggleBot();

            // Quickbar deploy
            var slot = t.closest('.quickbar-slot');
            if (slot && !slot.classList.contains('disabled')) {
                TacticalRTS.spawnPlatoon(slot.dataset.slot);
            }

            // Category filter
            var catBtn = t.closest('.category-btn');
            if (catBtn) {
                TacticalRTS.filterUnits(catBtn.dataset.category);
                TacticalRTS.updateCategoryButtons(catBtn);
            }

            // Remove unit
            var rm = t.closest('.remove-unit');
            if (rm) {
                var unitType = rm.dataset.unitType;
                var s = rm.closest('.platoon-slot').dataset.slot;
                TacticalRTS.removeUnitFromSlot(unitType, s);
            }

            // Deployed squad selection
            var squad = t.closest('.deployed-item');
            if (squad) {
                squad.classList.add('pulse-select');
                setTimeout(function() { squad.classList.remove('pulse-select'); }, 200);
                TacticalRTS.fetchNUI('selectPlatoonGroup', { uuid: parseInt(squad.dataset.uuid) });
            }
        });

        // Keyboard
        doc.addEventListener('keydown', function(e) {
            if (e.key === 'Enter') {
                var input = doc.getElementById('lobbyCodeInput');
                if (doc.activeElement === input) TacticalRTS.joinLobby();
            }
            if (e.key === 'Escape') {
                var sm = doc.getElementById('settingsModal');
                var hm = doc.getElementById('helpModal');
                if (sm && !sm.classList.contains('hidden')) return TacticalRTS.closeModal('settingsModal');
                if (hm && !hm.classList.contains('hidden')) return TacticalRTS.closeModal('helpModal');
                if (TacticalRTS.gameState.currentScreen === 'lobbyScreen') TacticalRTS.leaveLobby();
            }
        });
    };

    // ---- Input System (Rectangle select + right-click move) ----
    TacticalRTS.initInputSystem = function() {
        var selectRect = document.getElementById('selectionRectangle');
        var isDragging = false, startX = 0, startY = 0;

        window.addEventListener('mousedown', function(e) {
            if (!TacticalRTS.gameState.isInMatch) return;
            if (e.target.closest('.quickbar-slot, .modal, button, .hud-header-container, .hud-corner-right, .hud-bottom-section')) return;

            if (e.button === 0) {
                isDragging = true;
                startX = e.clientX;
                startY = e.clientY;
                if (selectRect) {
                    selectRect.style.left = startX + 'px';
                    selectRect.style.top = startY + 'px';
                    selectRect.style.width = '0px';
                    selectRect.style.height = '0px';
                    selectRect.classList.remove('hidden');
                }
            } else if (e.button === 2) {
                TacticalRTS.fetchNUI('issueCommand', {
                    type: 'move',
                    x: e.clientX / window.innerWidth,
                    y: e.clientY / window.innerHeight,
                });
            }
        });

        window.addEventListener('mousemove', function(e) {
            if (!TacticalRTS.gameState.isInMatch || !isDragging || !selectRect) return;
            var w = Math.abs(e.clientX - startX);
            var h = Math.abs(e.clientY - startY);
            selectRect.style.width = w + 'px';
            selectRect.style.height = h + 'px';
            selectRect.style.left = Math.min(e.clientX, startX) + 'px';
            selectRect.style.top = Math.min(e.clientY, startY) + 'px';
        });

        window.addEventListener('mouseup', function(e) {
            if (!TacticalRTS.gameState.isInMatch || !isDragging || e.button !== 0) return;
            isDragging = false;
            if (selectRect) selectRect.classList.add('hidden');

            var dist = Math.sqrt(Math.pow(e.clientX - startX, 2) + Math.pow(e.clientY - startY, 2));
            var w = window.innerWidth, h = window.innerHeight;

            if (dist > 15) {
                TacticalRTS.fetchNUI('selectUnits', {
                    x1: startX / w, y1: startY / h,
                    x2: e.clientX / w, y2: e.clientY / h,
                });
            } else {
                TacticalRTS.fetchNUI('selectUnit', { x: e.clientX, y: e.clientY });
            }
        });

        // Zoom
        window.addEventListener('wheel', function(e) {
            if (!TacticalRTS.gameState.isInMatch) return;
            TacticalRTS.fetchNUI('cameraZoom', { direction: e.deltaY < 0 ? 'in' : 'out' });
        }, { passive: true });
    };

    TacticalRTS.toggleBot = function() {
        var btn = document.getElementById('toggleBotBtn');
        if (!btn) return;
        var isAdd = btn.dataset.action === 'add';
        TacticalRTS.fetchNUI(isAdd ? 'addBot' : 'kickBot', {});
        TacticalRTS.playSFX('menuClick');
    };
})();
