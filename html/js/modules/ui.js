TacticalRTS.prototype.playSFX = function(name) {
    const sfx = this.sounds[name];
    if (sfx) {
        sfx.currentTime = 0;
        sfx.play().catch(e => {}); // Catch browser blocking errors
    }
};

TacticalRTS.prototype.showNotification = function(message, type = 'info') {
    const container = document.getElementById('notificationContainer');
    if (!container) return;

    // Limit number of notifications to prevent screen clutter
    if (container.children.length >= 5) {
        container.firstChild.remove();
    }

    // 1. Determine Title & Icon based on Type
    let title = "SYSTEM INFO";
    let iconClass = "info-circle";

    switch (type) {
        case 'success':
            title = "OPERATION SUCCESS";
            iconClass = "check-circle";
            break;
        case 'error':
            title = "CRITICAL ALERT";
            iconClass = "exclamation-triangle";
            break;
        case 'warning':
            title = "TACTICAL WARNING";
            iconClass = "bell"; // or radiation/biohazard icon
            break;
        case 'objective': // Custom type for objectives
            title = "OBJECTIVE UPDATE";
            iconClass = "crosshairs";
            type = 'warning'; // Re-use warning colors
            break;
    }

    // 2. Create Elements
    const notif = document.createElement('div');
    notif.className = `rts-notification ${type}`;
    
    // Get current game time string (simulated)
    const timeStr = new Date().toLocaleTimeString('en-US', { hour12: false, hour: "numeric", minute: "numeric" });

    notif.innerHTML = `
        <div class="notif-content">
            <div class="notif-icon-box">
                <i class="fas fa-${iconClass}"></i>
            </div>
            <div class="notif-text-area">
                <div class="notif-header">
                    <span>${title}</span>
                    <span>${timeStr}</span>
                </div>
                <div class="notif-message">${message}</div>
            </div>
        </div>
        <div class="notif-timer-bg">
            <div class="notif-timer-fill"></div>
        </div>
    `;

    // 3. Append & Animate Entry
    container.appendChild(notif);
    
    // Slight delay to trigger CSS transition
    requestAnimationFrame(() => {
        notif.classList.add('show');
    });

    // 4. Timer Logic (Web Animations API)
    const duration = 4000; // 4 seconds
    const timerFill = notif.querySelector('.notif-timer-fill');
    
    if (timerFill) {
        timerFill.animate([
            { width: '100%' },
            { width: '0%' }
        ], {
            duration: duration,
            easing: 'linear'
        });
    }

    // 5. Dismiss Logic
    const dismiss = () => {
        notif.classList.remove('show');
        notif.classList.add('hiding');
        
        // Wait for exit animation to finish before removing from DOM
        setTimeout(() => {
            if (notif.parentNode === container) {
                container.removeChild(notif);
            }
        }, 300);
    };

    // Auto dismiss
    const timeoutId = setTimeout(dismiss, duration);

    // Click to dismiss early
    notif.addEventListener('click', () => {
        clearTimeout(timeoutId);
        dismiss();
    });
};

TacticalRTS.prototype.getNotificationIcon = function(type) {
    switch (type) {
        case 'success':
            return 'check-circle';
        case 'error':
            return 'exclamation-circle';
        case 'warning':
            return 'exclamation-triangle';
        default:
            return 'info-circle';
    }
};

TacticalRTS.prototype.updateServerInfo = function(stats) {
    const playerCount = document.getElementById('playerCount');
    const activeBattles = document.getElementById('activeBattles');
    const serverPing = document.getElementById('serverPing'); // ID selector
    const estTime = document.getElementById('estTime');

    if (stats) {
        if (playerCount) playerCount.textContent = stats.onlineCount;
        if (activeBattles) activeBattles.textContent = stats.activeBattles;
        if (serverPing && stats.ping) serverPing.textContent = stats.ping; // Update Ping

        // Logic to calculate wait time based on open lobbies
        if (estTime) {
            const currentText = estTime.textContent.toUpperCase();
            
            // If the UI is currently displaying a counting timer (contains a colon like 0:05) 
            // or says "SEARCHING", ignore the server's text update so the animation doesn't glitch.
            if (!currentText.includes(':') && !currentText.includes('SEARCHING')) {
                estTime.textContent = stats.estimatedWait || "-";
            }
        }
    } else {
        if (playerCount) playerCount.textContent = '--';
        if (activeBattles) activeBattles.textContent = '--';
    }
};

TacticalRTS.prototype.formatNumber = function(num) {
    if (!num) return '0';
    if (num >= 1000000) {
        return (num / 1000000).toFixed(1).replace(/\.0$/, '') + 'M';
    }
    if (num >= 1000) {
        return (num / 1000).toFixed(1).replace(/\.0$/, '') + 'K';
    }
    return num.toString();
};

TacticalRTS.prototype.updateStats = function(myStats) {
    this.myStats = myStats; 

    // Update Commander Name
    const commanderNameDisplay = document.getElementById('commanderNameDisplay');
    if (commanderNameDisplay) {
        const name = (myStats.name || 'UNKNOWN').toUpperCase();
        commanderNameDisplay.textContent = `${name}`;
    }

    const statWins = document.getElementById('statWins');
    const statKills = document.getElementById('statKillsTotal');
    const statMatches = document.getElementById('statMatches');
    const statScore = document.getElementById('statScore');

    const s = myStats || { wins: 0, kills: 0, matches: 0, score: 0 };

    if (statWins) statWins.textContent = this.formatNumber(s.wins);
    if (statKills) statKills.textContent = this.formatNumber(s.kills);
    if (statMatches) statMatches.textContent = this.formatNumber(s.matches);
    
    //  Apply Format to Score (10000 -> 10K)
    if (statScore) statScore.textContent = this.formatNumber(s.score);

    // LEVEL UPDATES
    if (myStats.levelData) {
        const ld = myStats.levelData;
        const badge = document.getElementById('profileLevelBadge');
        if (badge) badge.textContent = `LVL ${ld.level}`;

        const bar = document.getElementById('profileXPBar');
        if (bar) bar.style.width = `${ld.percent}%`;

        const txtCur = document.getElementById('xpCurrent');
        const txtMax = document.getElementById('xpMax');
        
        //  Apply Format to XP as well
        if (txtCur) txtCur.textContent = this.formatNumber(ld.currentXP);
        if (txtMax) txtMax.textContent = this.formatNumber(ld.requiredXP);
    }
};

TacticalRTS.prototype.openLeaderboard = function() {
    this.showScreen('leaderboardScreen');
    const list = document.getElementById('leaderboardList');
    if (list) list.innerHTML = '<div style="padding:50px; text-align:center; color:#666;">ACCESSING GLOBAL DATABASE...</div>';

    this.fetchNUI('getLeaderboard').then(data => {
        if (!list) return;
        list.innerHTML = '';

        if (!data || data.length === 0) {
            list.innerHTML = '<div style="padding:20px; text-align:center">No Data Available</div>';
            return;
        }

        data.forEach((p, index) => {
            const row = document.createElement('div');
            const rank = index + 1;
            
            // Determine Rank Style
            let rankClass = 'rank-normal';
            let rankIcon = `<span class="rank-num">#${rank}</span>`;

            if (rank === 1) {
                rankClass = 'rank-1'; // Gold
                rankIcon = `<i class="fas fa-trophy"></i>`;
            } else if (rank === 2) {
                rankClass = 'rank-2'; // Silver
                rankIcon = `<i class="fas fa-medal"></i>`;
            } else if (rank === 3) {
                rankClass = 'rank-3'; // Bronze
                rankIcon = `<i class="fas fa-medal"></i>`;
            }

            row.className = `leaderboard-row ${rankClass}`;
            
            // HTML Structure
            row.innerHTML = `
                <div class="lb-rank">${rankIcon}</div>
                <div class="lb-name">
                    <span class="lvl-tag">LVL ${p.level || 1}</span> 
                    <span class="player-name">${p.name || 'Unknown'}</span>
                </div>
                <div class="lb-stat">${p.wins} <span class="sub-label">WINS</span></div>
                <div class="lb-stat">${p.kills} <span class="sub-label">KILLS</span></div>
                <div class="lb-stat score-val">${p.score.toLocaleString()}</div>
            `;
            list.appendChild(row);
        });
    });
};

TacticalRTS.prototype.openHistory = function() {
        this.showScreen('historyScreen');
        const list = document.getElementById('historyList');
        if (list) list.innerHTML = '<div style="padding:20px; text-align:center">Retrieving Battle Logs...</div>';

        this.fetchNUI('getHistory').then(data => {
            if (!list) return;
            list.innerHTML = '';

            if (!data || data.length === 0) {
                list.innerHTML = '<div style="padding:20px; text-align:center">No combat history found.</div>';
                return;
            }

            data.forEach(match => {
                const isWin = match.result === 'WIN';
                const resultClass = isWin ? 'win' : 'loss';
                const resultText = isWin ? 'VICTORY' : 'DEFEAT';
                const opponent = match.opponent_name || "Unknown Enemy";

                // Format Date (Simple)
                const date = new Date(match.date_played).toLocaleDateString();

                const item = document.createElement('div');
                item.className = `history-item ${resultClass}`;
                
               item.innerHTML = `
    <div class="history-info">
        <div class="map-label">${match.map_name.toUpperCase().replace('_', ' ')}</div>
        <div class="opponent-tag">
            <span class="vs-text">VS</span> 
            <span class="opponent-name">${opponent}</span>
        </div>
        <div class="match-date">${date}</div>
    </div>
    
    <div class="history-result">
        <div>
            <span class="result-glow-text" style="color:${isWin ? 'var(--green)':'var(--red)'}">
                ${resultText}
            </span>
            
        </div>
    </div>
    
    <div class="history-stats">
        <div class="stat-block">
            <span class="label">KILLS</span>
            <span class="value">${match.kills}</span>
        </div>
        <div class="stat-block">
            <span class="label">SCORE</span>
            <span class="value">${match.score.toLocaleString()}</span>
        </div>
    </div>
`;
                list.appendChild(item);
            });
        });
    };

TacticalRTS.prototype.openSettings = function() {
    const modal = document.getElementById('settingsModal');
    const music = document.getElementById('bgMusic');
    
    const musicSlider = document.getElementById('musicVolume');
    const sfxSlider = document.getElementById('sfxVolume'); //  Select SFX Slider
    const surrenderBtn = document.getElementById('surrenderBtn');

    // Sync Music Slider
    if (music && musicSlider) {
        musicSlider.value = Math.floor(music.volume * 100);
    }

    //  Sync SFX Slider (Get volume from the 'hover' sound as a reference)
    if (this.sounds.hover && sfxSlider) {
        sfxSlider.value = Math.floor(this.sounds.hover.volume * 100);
    }

    // Toggle Surrender Button based on game state
    if (surrenderBtn) {
        if (this.gameState.isInMatch) {
            surrenderBtn.classList.remove('hidden');
        } else {
            surrenderBtn.classList.add('hidden');
        }
    }

    if (modal) modal.classList.remove('hidden');
};

TacticalRTS.prototype.closeModal = function(modalId) {
    document.getElementById(modalId).classList.add('hidden');
};

TacticalRTS.prototype.openHelp = function() {
    const modal = document.getElementById('helpModal');
    if (!modal) return;

    const container = modal.querySelector('.modal-body');
    if (!container) return;

    modal.classList.remove('hidden');
    container.innerHTML = '';

    // --- SECTION 1: CONTROLS ---
    const k = this.keyConfig || { SelectAllUnits: 'SPACE', OpenMenu: 'F5' };

    let html = `
        <div class="help-section">
            <h3><i class="fas fa-keyboard"></i> BATTLEFIELD CONTROLS</h3>
            <ul class="controls-list">
                <li><strong>${k.SelectAllUnits || 'SPACE'}</strong> <span>Select All Units</span></li>
                <li><strong>${k.SelectUnitsType1 || '1'}-${k.SelectUnitsType4 || '4'}</strong> <span>Select Platoon Group</span></li>
                <li><strong>${k.OpenMenu || 'F5'}</strong> <span>Tactical Menu</span></li>
                <li><strong>LMB + DRAG</strong> <span>Box Selection</span></li>
                <li><strong>RMB</strong> <span>Move / Attack</span></li>
            </ul>
        </div>
    `;

    // --- SECTION 2: OBJECTIVES ---
    html += `
        <div class="help-section">
            <h3><i class="fas fa-flag"></i> OBJECTIVES</h3>
            <p style="color:#aaa; font-size: 0.9em; margin-bottom:5px;">Capture the central zone or eliminate enemies to win.</p>
            <p style="color:#aaa; font-size: 0.9em;">Control resources to boost command points.</p>
        </div>
    `;

    // --- SECTION 3: COMPACT UNIT GRID ---
    // Added 'display: grid' style here for 2-column layout
    html += `<div class="help-section">
        <h3><i class="fas fa-users-cog"></i> UNIT CLASSIFICATION</h3>
        <div class="unit-types" style="display: grid; grid-template-columns: 1fr 1fr; gap: 10px;">`;

    const descMap = {
        infantry: "Low cost, versatile",
        vehicles: "High armor & damage",
        aircraft: "Fast, air superiority",
        helicopters: "Close air support",
        default: "Specialized unit"
    };

    if (this.categories && Object.keys(this.categories).length > 0) {
        const cats = Object.entries(this.categories)
            .map(([id, data]) => ({ id, ...data }))
            .sort((a, b) => (a.sort || 99) - (b.sort || 99));

        cats.forEach(cat => {
            let iconDisplay = cat.icon;
            if (cat.icon && (cat.icon.includes('fa-') || cat.icon.includes('fas'))) {
                iconDisplay = `<i class="${cat.icon}"></i>`;
            }
            const description = descMap[cat.id] || descMap.default;

            // COMPACT STYLE: Reduced padding, smaller fonts
            html += `
                <div class="unit-type" style="display: flex; align-items: center; gap: 10px; padding: 10px; background: rgba(0, 0, 0, 0.3); border-radius: 6px; border-left: 3px solid ${cat.color || '#fff'};">
                    <div style="font-size: 1.2em; color: ${cat.color || '#fff'}; width: 25px; text-align: center;">
                        ${iconDisplay}
                    </div>
                    <div style="overflow: hidden;">
                        <div style="font-weight: 700; color: #fff; font-size: 0.9em; text-transform: uppercase; white-space: nowrap;">${cat.name}</div>
                        <div style="font-size: 0.75em; color: #8a94a6; margin-top: 1px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">${description}</div>
                    </div>
                </div>
            `;
        });
    } else {
        html += `<div style="color: #aaa; grid-column: span 2;">Retrieving Unit Database...</div>`;
    }

    html += `</div></div>`;
    container.innerHTML = html;
};

TacticalRTS.prototype.exitGame = function() {
    this.fetchNUI('close', {});
    document.body.style.display = 'none'; // Instant hide locally
};

TacticalRTS.prototype.viewStats = function() {
    this.showNotification('Statistics feature coming soon', 'info');
};

TacticalRTS.prototype.resetQueueUI = function() {
    this.isQueued = false;
    clearInterval(this.queueTimerInterval);

    const btn = document.getElementById('quickMatch');
    const btnText = btn.querySelector('span');
    const btnIcon = btn.querySelector('i');
    const estTime = document.getElementById('estTime');

    // Reset Visuals
    btn.classList.remove('btn-danger');
    btn.classList.add('btn-primary');
    btnText.textContent = "FIND MATCH";
    btnIcon.className = "fas fa-bolt";

    if (estTime) {
        // Check if we have cached stats from the 5s poller; use it immediately so it doesn't look static!
        if (this.cachedStats && this.cachedStats.estimatedWait) {
            estTime.textContent = this.cachedStats.estimatedWait;
        } else {
            estTime.textContent = "-";
        }
    }
};

TacticalRTS.prototype.acceptAiMatch = function() {
    const modal = document.getElementById('aiPromptModal');
    if (modal) modal.classList.add('hidden');
    
    if (this.aiPromptTimer) clearTimeout(this.aiPromptTimer);
    this.resetQueueUI(); // Reset the red "Cancel" button back to blue
    
    this.showNotification('Preparing A.I. Battle...', 'info');
    this.fetchNUI('startAiMatchFromQueue'); 
};

TacticalRTS.prototype.declineAiMatch = function() {
    const modal = document.getElementById('aiPromptModal');
    if (modal) modal.classList.add('hidden');
    // Do nothing else, let the queue timer keep ticking in the background
};

TacticalRTS.prototype.startLiveStatsPoller = function() {
    // Clear any existing interval just in case
    if (this.liveStatsInterval) clearInterval(this.liveStatsInterval);
    
    // Run every 5 seconds (5000ms)
    this.liveStatsInterval = setInterval(() => {
        // ONLY ask the server for updates if we are sitting in the menu or lobby
        if (this.gameState.currentScreen === 'mainMenu' || this.gameState.currentScreen === 'lobbyScreen') {
            this.fetchNUI('requestLiveStats', {}).then(stats => {
                if (stats) this.updateServerInfo(stats);
            }).catch(() => {});
        }
    }, 5000); 
};

TacticalRTS.prototype.updateCursorPosition = function(x, y) {
    const cursor = document.getElementById('gameCursor');
    if (cursor) {
        cursor.style.left = `${x}px`;
        cursor.style.top = `${y}px`;
    }
};

TacticalRTS.prototype.showSelectionRectangle = function(x1, y1, x2, y2) {
    const rect = document.getElementById('selectionRectangle');
    if (rect) {
        const left = Math.min(x1, x2);
        const top = Math.min(y1, y2);
        const width = Math.abs(x2 - x1);
        const height = Math.abs(y2 - y1);

        rect.style.left = `${left}px`;
        rect.style.top = `${top}px`;
        rect.style.width = `${width}px`;
        rect.style.height = `${height}px`;
        rect.style.display = 'block';
    }
};

TacticalRTS.prototype.hideSelectionRectangle = function() {
    const rect = document.getElementById('selectionRectangle');
    if (rect) {
        rect.style.display = 'none';
    }
};

TacticalRTS.prototype.zoomMinimap = function(factor) {
    const zoomLevel = document.getElementById('zoomLevel');
    if (zoomLevel) {
        let currentZoom = parseInt(zoomLevel.textContent);
        currentZoom = Math.max(50, Math.min(200, Math.round(currentZoom * factor)));
        zoomLevel.textContent = `${currentZoom}%`;
    }
};
