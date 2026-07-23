// ===========================================================================
//  RTS NUI - Modals (Settings, Help)
// ===========================================================================

(function() {
    if (!window.TacticalRTS) return;

    TacticalRTS.openSettings = function() {
        var modal = document.getElementById('settingsModal');
        if (!modal) return;

        var music = document.getElementById('bgMusic');
        var musicSlider = document.getElementById('musicVolume');
        var sfxSlider = document.getElementById('sfxVolume');
        var surrenderBtn = document.getElementById('surrenderBtn');

        if (music && musicSlider) musicSlider.value = Math.floor(music.volume * 100);
        if (TacticalRTS.sounds.hover && sfxSlider) sfxSlider.value = Math.floor(TacticalRTS.sounds.hover.volume * 100);
        if (surrenderBtn) surrenderBtn.classList.toggle('hidden', !TacticalRTS.gameState.isInMatch);

        modal.classList.remove('hidden');
    };

    TacticalRTS.closeModal = function(id) {
        var el = document.getElementById(id);
        if (el) el.classList.add('hidden');
    };

    TacticalRTS.saveSettings = function() {
        var music = document.getElementById('bgMusic');
        var musicSlider = document.getElementById('musicVolume');
        var sfxSlider = document.getElementById('sfxVolume');

        if (music && musicSlider) music.volume = musicSlider.value / 100;
        if (sfxSlider) {
            var vol = sfxSlider.value / 100;
            Object.values(TacticalRTS.sounds).forEach(function(s) { s.volume = vol; });
        }

        TacticalRTS.showNotification('Settings applied', 'success');
        TacticalRTS.closeModal('settingsModal');
        TacticalRTS.playSFX('menuClick');
    };

    TacticalRTS.openHelp = function() {
        var modal = document.getElementById('helpModal');
        if (!modal) return;
        var body = modal.querySelector('.modal-body');
        if (body) {
            body.innerHTML =
                '<p><strong>Camera:</strong> Move mouse to screen edges to pan. Scroll wheel to zoom.</p>' +
                '<p><strong>Selection:</strong> Left-click and drag to select units. SPACE = select all. Numpad 1-3 for category.</p>' +
                '<p><strong>Orders:</strong> Right-click to move. Right-click enemy to attack.</p>' +
                '<p><strong>Deploy:</strong> Click platoon slots (1-5) to spawn units at cursor position.</p>' +
                '<p><strong>Win:</strong> Capture the primary objective or eliminate all enemies.</p>';
        }
        modal.classList.remove('hidden');
    };
})();
