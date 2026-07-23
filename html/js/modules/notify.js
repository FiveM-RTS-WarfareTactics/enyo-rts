// ===========================================================================
//  RTS NUI - Notification System
// ===========================================================================

(function() {
    if (!window.TacticalRTS) return;

    TacticalRTS.showNotification = function(message, type) {
        type = type || 'info';
        var container = document.getElementById('notificationContainer');
        if (!container) return;

        if (container.children.length >= 5) container.firstChild.remove();

        var titles = { success: 'OPERATION SUCCESS', error: 'CRITICAL ALERT', warning: 'TACTICAL WARNING', objective: 'OBJECTIVE UPDATE', info: 'SYSTEM INFO' };
        var icons  = { success: 'check-circle', error: 'exclamation-triangle', warning: 'bell', objective: 'crosshairs', info: 'info-circle' };
        var title  = titles[type] || titles.info;
        var icon   = icons[type] || icons.info;
        var timeStr = new Date().toLocaleTimeString('en-US', { hour12: false, hour: 'numeric', minute: 'numeric' });

        var notif = document.createElement('div');
        notif.className = 'rts-notification ' + type;
        notif.innerHTML =
            '<div class="notif-content">' +
                '<div class="notif-icon-box"><i class="fas fa-' + icon + '"></i></div>' +
                '<div class="notif-text-area">' +
                    '<div class="notif-header"><span>' + title + '</span><span>' + timeStr + '</span></div>' +
                    '<div class="notif-message">' + message + '</div>' +
                '</div>' +
            '</div>' +
            '<div class="notif-timer-bg"><div class="notif-timer-fill"></div></div>';

        container.appendChild(notif);
        requestAnimationFrame(function() { notif.classList.add('show'); });

        var duration = 4000;
        var fill = notif.querySelector('.notif-timer-fill');
        if (fill) fill.animate([{ width: '100%' }, { width: '0%' }], { duration: duration, easing: 'linear' });

        var dismiss = function() {
            notif.classList.remove('show');
            notif.classList.add('hiding');
            setTimeout(function() { if (notif.parentNode) notif.parentNode.removeChild(notif); }, 300);
        };

        var timeoutId = setTimeout(dismiss, duration);
        notif.addEventListener('click', function() { clearTimeout(timeoutId); dismiss(); });
    };
})();
