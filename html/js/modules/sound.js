// ===========================================================================
//  RTS NUI - Sound Module
// ===========================================================================

(function() {
    if (!window.TacticalRTS) return;

    TacticalRTS.sounds = {
        hover: new Audio('sounds/hover-1.mp3'),
        menuClick: new Audio('sounds/click-2.mp3'),
        menuOpen: new Audio('sounds/menu-open.mp3'),
        dispatch: new Audio('sounds/start.mp3'),
        alert: new Audio('sounds/error.mp3'),
        countdownBip: new Audio('sounds/countdown.mp3'),
        deployUnit: new Audio('sounds/click-1.mp3'),
    };

    Object.values(TacticalRTS.sounds).forEach(function(s) { s.volume = 0.4; });
    TacticalRTS.sounds.hover.volume = 0.1;

    TacticalRTS.playSFX = function(name) {
        var s = TacticalRTS.sounds[name];
        if (s) {
            s.currentTime = 0;
            s.play().catch(function() {});
        }
    };
})();
