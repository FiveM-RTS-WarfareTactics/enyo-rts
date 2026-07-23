TacticalRTS.prototype.initUnitRenderer = function() {
    this.unitElements = {};
    // We use the input layer so hitboxes are clickable
    this.overlayContainer = document.getElementById('game-input-layer');
    console.log("Unit Renderer Initialized");
};

TacticalRTS.prototype.startAirstrikeTimer = function(durationSeconds) {
    const alertBox = document.getElementById('airstrikeAlert');
    const timerVal = document.getElementById('asTimerVal');
    const progressFill = document.getElementById('asProgress');

    if (!alertBox) return;

    // Reset
    this.stopAirstrikeTimer();

    alertBox.classList.remove('hidden');
    let remaining = durationSeconds * 1000; // ms
    const total = remaining;

    this.airstrikeInterval = setInterval(() => {
        remaining -= 50; // Update every 50ms

        // Update Text
        if (timerVal) timerVal.textContent = (remaining / 1000).toFixed(1);

        // Update Bar
        if (progressFill) {
            const pct = (remaining / total) * 100;
            progressFill.style.width = `${pct}%`;
        }

        if (remaining <= 0) {
            this.stopAirstrikeTimer();
        }
    }, 50);
};

TacticalRTS.prototype.stopAirstrikeTimer = function() {
        if (this.airstrikeInterval) {
            clearInterval(this.airstrikeInterval);
            this.airstrikeInterval = null;
        }
        const alertBox = document.getElementById('airstrikeAlert');
        if (alertBox) alertBox.classList.add('hidden');
    };

TacticalRTS.prototype.updatePopulationDisplay = function(data) {
    this.gameState.population = data.current;
    this.gameState.maxPopulation = data.max;

    // Lock individual slots if spawning them would exceed the limit
    for (let slot = 1; slot <= 5; slot++) {
        const slotEl = document.querySelector(`.quickbar-slot[data-slot="${slot}"]`);
        if (!slotEl) continue;

        const pData = this.platoonData[slot];
        if (pData) {
            const countNeeded = pData.unitCount || 1;
            
            // If adding this platoon pushes us over the maximum
            if (data.current + countNeeded > data.max) {
                slotEl.classList.add('pop-capped');
                // Send the exact numbers to the CSS (e.g., "MAX: 20/20")
                slotEl.setAttribute('data-pop-msg', `MAX: ${data.current}/${data.max}`);
            } else {
                slotEl.classList.remove('pop-capped');
                slotEl.removeAttribute('data-pop-msg');
            }
        }
    }
};

TacticalRTS.prototype.startMatch = function(data) {
    this.gameState.isInMatch = true;
    this.gameState.team = data.team || 1;
    this.gameState.commandPoints = data.commandPoints || 1500;

    // --- Load the saved platoons from the server ---
    if (data.platoons) {
        this.platoonData = data.platoons;
      //  console.log("Platoons Loaded for Match:", this.platoonData);
    }
    this.updateQuickbarIcons()
        // ----------------------------------------------------
        // In startMatch()
    const music = document.getElementById('bgMusic');
    const source = music.querySelector('source');
    source.src = "sounds/" + data.music;
   // console.log(source.src);
  //  console.log(music);
    music.load();
    if (music) music.play();

    // In showMatchResult() (End of match)
    // Keep playing or stop? You said "End with the match", assuming stop or change track.
    // To stop:
    // if(music) { music.pause(); music.currentTime = 0; }

    // In saveSettings()
    const musVol = document.getElementById('musicVolume').value;
    const sfxVol = document.getElementById('sfxVolume').value;
    const musicEl = document.getElementById('bgMusic');
    if (musicEl) musicEl.volume = musVol / 100;

    // Update team display
    const teamName = document.getElementById('teamName');
    const commanderId = document.getElementById('commanderId');
    const teamBadge = document.getElementById('teamBadge');

    if (teamName) teamName.textContent = "ALLIED COMMAND"; // Always Allied from your view
    if (commanderId) commanderId.textContent = data.team.toString().padStart(2, '0');
    if (teamBadge) {
        teamBadge.style.borderImage = 'linear-gradient(45deg, #00a8ff, #0097e6) 1';
    }

    this.showScreen('gameUI');
    this.initializeGameUI();

    // Set up quickbar costs
    for (let slot = 1; slot <= 5; slot++) {
        if (this.platoonData[slot]) {
            const quickCost = document.getElementById(`quickCost${slot}`);
            if (quickCost) quickCost.textContent = `$${this.platoonData[slot].totalCost}`;

            // Ensure button is enabled
            const slotEl = document.querySelector(`.quickbar-slot[data-slot="${slot}"]`);
            if (slotEl) slotEl.classList.remove('disabled');
        } else {
            // Dim empty slots
            const slotEl = document.querySelector(`.quickbar-slot[data-slot="${slot}"]`);
            if (slotEl) slotEl.classList.add('disabled');
        }
    }
};

TacticalRTS.prototype.initializeGameUI = function() {
        // Initialize resources display
        this.updateResourceDisplay({
            commandPoints: this.gameState.commandPoints,
            incomeRate: 150
        });

        // Initialize timer
        this.updateTimerDisplay({ time: '15:00' });

        // Initialize selection info
        this.updateSelectionInfo({ count: 0, health: 100 });

        // Initialize command points
        const cpValue = document.getElementById('cpValue');
        if (cpValue) cpValue.textContent = this.gameState.commandPoints;
    };

TacticalRTS.prototype.updateQuickbarIcons = function() {
    for (let slot = 1; slot <= 5; slot++) {
        const slotEl = document.querySelector(`.quickbar-slot[data-slot="${slot}"]`);
        if (!slotEl) continue;

        const existing = slotEl.querySelector('.slot-icons-preview');
        if (existing) existing.remove();

        if (this.platoonData[slot] && this.platoonData[slot].units.length > 0) {
            const previewDiv = document.createElement('div');
            previewDiv.className = 'slot-icons-preview';

            this.platoonData[slot].units.forEach(u => {
                const uConfig = this.unitData[u.type];
                if (uConfig) {
                    let count = u.count || 1;
                    if (count > 3) count = 3;

                    for (let i = 0; i < count; i++) {
                        //  Use Image instead of Text
                        const img = document.createElement('img');
                        img.className = 'tiny-unit-icon';
                        // Ensure your images are in html/images/units/
                        img.src = `images/units/${uConfig.thumbnail || 'default.png'}`;
                        previewDiv.appendChild(img);
                    }
                }
            });
            slotEl.appendChild(previewDiv);
        }
    }
};

TacticalRTS.prototype.updatePlatoonCooldown = function(index, cooldown) {
    const cooldownElement = document.getElementById(`cooldown${index}`);
    const slotElement = document.querySelector(`.quickbar-slot[data-slot="${index}"]`);

    if (cooldownElement) {
        if (cooldown > 0) {
            cooldownElement.textContent = cooldown;
            cooldownElement.style.display = 'flex';
            if (slotElement) slotElement.classList.add('disabled');
        } else {
            cooldownElement.style.display = 'none';
            if (slotElement) slotElement.classList.remove('disabled');
        }
    }
};

TacticalRTS.prototype.issueCommand = function(command) {
    if (!this.gameState.isInMatch) return;

    // Show command panel
    const commandPanel = document.getElementById('commandPanel');
    if (commandPanel) {
        commandPanel.style.display = 'block';
    }

    // In a real implementation, you would send the command to the client
    this.showNotification(`${command.toUpperCase()} command selected`, 'info');
};

TacticalRTS.prototype.hideCommandPanel = function() {
    const commandPanel = document.getElementById('commandPanel');
    if (commandPanel) {
        commandPanel.style.display = 'none';
    }
};

TacticalRTS.prototype.updateSelectionInfo = function(data) {
    // Select the container (Quickbar wrapper) or the specific info box
    // Based on your HTML, the info box is .selection-info inside .platoon-quickbar
    const selectionInfo = document.querySelector('.selection-info');

    // Safety check
    if (!selectionInfo) return;

    // Logic: Hide if 0 units selected
    if (!data.count || data.count === 0) {
        selectionInfo.style.opacity = '0';
        selectionInfo.style.visibility = 'hidden'; // Prevents clicking empty space
        return;
    }

    // Show if units selected
    selectionInfo.style.opacity = '1';
    selectionInfo.style.visibility = 'visible';

    const selectedCount = document.getElementById('selectedCount');
    const selectionHealth = document.getElementById('selectionHealth');
    const healthPercent = document.getElementById('healthPercent');

    if (selectedCount) selectedCount.textContent = data.count;

    if (selectionHealth) {
        selectionHealth.style.width = `${data.health}%`;

        // Dynamic Color
        let color = '#4cd137'; // Green
        if (data.health < 50) color = '#fbc531'; // Yellow
        if (data.health < 25) color = '#ff4757'; // Red
        selectionHealth.style.backgroundColor = color;
    }

    if (healthPercent) healthPercent.textContent = `${data.health}%`;
};

TacticalRTS.prototype.updateResourceDisplay = function(data) {
    const cpValue = document.getElementById('cpValue');
    const incomeValue = document.getElementById('incomeValue');

    if (cpValue) cpValue.textContent = Math.floor(data.commandPoints || 0);
    if (incomeValue) incomeValue.textContent = `+${data.incomeRate || 0}/MIN`;

    // Update game state
    this.gameState.commandPoints = data.commandPoints || 0;
};

TacticalRTS.prototype.updateTimerDisplay = function(data) {
    const timeValue = document.getElementById('timeValue');
    if (!timeValue || !data.time) return;

    // 1. CONFIG: Total Match Duration in Seconds (15 Minutes)
    const matchDuration = 15 * 60;

    // 2. Parse the "Elapsed" time coming from Lua (Format: "MM:SS")
    const parts = data.time.split(':');
    const elapsedMinutes = parseInt(parts[0], 10) || 0;
    const elapsedSeconds = parseInt(parts[1], 10) || 0;
    const totalElapsed = (elapsedMinutes * 60) + elapsedSeconds;

    // 3. Calculate Remaining Time
    let remaining = matchDuration - totalElapsed;

    // 4. Handle Overtime (Stop at 00:00)
    if (remaining < 0) remaining = 0;

    // 5. Format back to MM:SS
    const m = Math.floor(remaining / 60).toString().padStart(2, '0');
    const s = (remaining % 60).toString().padStart(2, '0');

    // 6. Update UI
    timeValue.textContent = `${m}:${s}`;

    // Optional: Add visual urgency if time is low (e.g., < 1 minute)
    if (remaining <= 60) {
        timeValue.style.color = '#ff4757'; // Red
        timeValue.classList.add('pulse-fast'); // Assuming you have a CSS animation
    } else {
        timeValue.style.color = '#fff'; // White/Default
        timeValue.classList.remove('pulse-fast');
    }
};

TacticalRTS.prototype.updateCaptureDisplay = function(data) {
    const objectiveProgress = document.getElementById('objectiveProgress');
    const objectiveStatus = document.getElementById('objectiveStatus');

    if (objectiveProgress) objectiveProgress.style.width = `${data.progress || 0}%`;
    if (objectiveStatus) {
        if (data.controllingTeam === 0) {
            objectiveStatus.textContent = 'NEUTRAL';
        } else if (data.controllingTeam === this.gameState.team) {
            objectiveStatus.textContent = 'FRIENDLY';
        } else {
            objectiveStatus.textContent = 'ENEMY';
        }
    }
};

TacticalRTS.prototype.showMatchResult = function(data) {
    this.gameState.isInMatch = false;

    // 1. Handle Rematch Code
    this.nextLobbyCode = (data.matchData && data.matchData.nextLobby) ? data.matchData.nextLobby : this.gameState.lobbyCode;

    // 2. Stop Music / Play SFX
    const music = document.getElementById('bgMusic');
    if (music) { music.pause(); music.currentTime = 0; }
    
    // Play sound based on result
    if(data.victory) this.playSFX('dispatch'); // Victory sound
    else this.playSFX('alert'); // Defeat sound

    // 3. Select Elements
    const container = document.querySelector('.result-container');
    const title = document.getElementById('resultTitle');
    const subtitle = document.getElementById('resultSubtitle');
    const iconBg = document.querySelector('.result-icon-bg i');

    // 4. Apply Theme (Victory/Defeat)
    if (data.victory) {
        container.classList.add('theme-victory');
        container.classList.remove('theme-defeat');
        title.textContent = "VICTORY";
        iconBg.className = "fas fa-trophy";
    } else {
        container.classList.add('theme-defeat');
        container.classList.remove('theme-victory');
        title.textContent = "DEFEAT";
        iconBg.className = "fas fa-skull-crossbones";
    }

    // 5. Reason Text
    // 5. Dynamic Reason Text
    let reasonText = "";

    if (data.victory) {
        // --- VICTORY SCENARIOS ---
        switch (data.reason) {
            case "elimination": 
                reasonText = "HOSTILE FORCES NEUTRALIZED"; 
                break;
            case "capture":     
                reasonText = "SECTOR SECURED"; 
                break;
            case "timeout":     
                reasonText = "TACTICAL SUPERIORITY ACHIEVED"; 
                break;
            case "surrender":   
                reasonText = "ENEMY COMMANDER SURRENDERED"; 
                break;
            default:            
                reasonText = "MISSION ACCOMPLISHED"; 
                break;
        }
    } else {
        // --- DEFEAT SCENARIOS ---
        switch (data.reason) {
            case "elimination": 
                reasonText = "CRITICAL FAILURE: UNIT WIPED OUT"; 
                break;
            case "capture":     
                reasonText = "SECTOR OVERRUN BY ENEMY"; 
                break;
            case "timeout":     
                reasonText = "MISSION FAILED: TIME LIMIT EXPIRED"; 
                break;
            case "surrender":   
                reasonText = "TACTICAL RETREAT ORDERED"; 
                break;
            default:            
                reasonText = "MISSION FAILED"; 
                break;
        }
    }
    
    if (resultSubtitle) resultSubtitle.textContent = reasonText;

    // 6. Update Stats (With Counter Animation)
    const stats = data.stats || { matchTime: 0, kills: 0, unitsLost: 0 };
    
    // Format Time
    const m = Math.floor(Number(stats.matchTime || 0) / 60).toString().padStart(2, '0');
    const s = (Number(stats.matchTime || 0) % 60).toString().padStart(2, '0');
    document.getElementById('statTime').textContent = `${m}:${s}`;

    // Animate Numbers Helper
    const animateValue = (id, start, end, duration) => {
        const obj = document.getElementById(id);
        if(!obj) return;
        let startTimestamp = null;
        const step = (timestamp) => {
            if (!startTimestamp) startTimestamp = timestamp;
            const progress = Math.min((timestamp - startTimestamp) / duration, 1);
            obj.innerHTML = Math.floor(progress * (end - start) + start).toLocaleString();
            if (progress < 1) window.requestAnimationFrame(step);
        };
        window.requestAnimationFrame(step);
    };

    animateValue("statKills", 0, stats.kills || 0, 1500);
    animateValue("statLosses", 0, stats.unitsLost || 0, 1500);
    animateValue("statObjectives", 0, data.score || 0, 2000);

    // 7. Progression (XP Bar)
    if (data.levelData) {
        const ld = data.levelData;
        const resLvl = document.getElementById('resLevel');
        const resBar = document.getElementById('resXPBar');
        const resCur = document.getElementById('resXPCurrent');
        const resMax = document.getElementById('resXPMax');
        const xpGain = document.getElementById('xpGainedDisplay');

        if (resLvl) resLvl.textContent = ld.level;
        if (resCur) resCur.textContent = this.formatNumber(ld.currentXP);
        if (resMax) resMax.textContent = this.formatNumber(ld.requiredXP);
        
        // Calculate XP Gained (Visual approximation)
        if (xpGain) xpGain.textContent = this.formatNumber(data.score || 0);

        if (resBar) {
            // Reset for animation
            resBar.style.width = '0%';
            resBar.style.transition = 'none';
            void resBar.offsetWidth; // Reflow
            
            // Animate fill
            setTimeout(() => { 
                resBar.style.transition = 'width 1.5s cubic-bezier(0.22, 1, 0.36, 1)';
                resBar.style.width = `${ld.percent}%`; 
            }, 300);
        }
    }

    // 8. Show Screen
    this.showScreen('resultScreen');

    // 9. Re-bind Buttons (Safety check)
    const rematchBtn = document.getElementById('rematchBtn');
    const returnBtn = document.getElementById('returnToMenuBtn');

    if (rematchBtn) rematchBtn.onclick = () => this.rematch();
    if (returnBtn) returnBtn.onclick = () => this.returnToMenu();
};

TacticalRTS.prototype.rematch = function() {
    // THE FIX: Prevent double-clicking the button
    const btn = document.getElementById('rematchBtn');
    if (btn && btn.disabled) return;
    if (btn) btn.disabled = true;

    this.showNotification('Connecting to Rematch Lobby...', 'info');
    document.getElementById('resultScreen').classList.add('hidden');

    // THE FIX: Reset Ready State immediately so Add AI button isn't grayed out
    this.gameState.playerReady = false;

    if (this.nextLobbyCode) {
        this.fetchNUI('joinLobby', { code: this.nextLobbyCode }).then(res => {
            if (btn) btn.disabled = false;
            if (res.success) {
                this.handleLobbyJoined(res);
            } else {
                this.showNotification('Rematch lobby unavailable.', 'warning');
                this.returnToMenu();
            }
        });
    } else {
        this.fetchNUI('createLobby', { map: this.currentMap }).then(() => {
            if (btn) btn.disabled = false;
        });
    }
};

TacticalRTS.prototype.returnToMenu = function() {
    this.fetchNUI('leaveLobby');

    this.gameState.isInMatch = false;
    this.gameState.team = 0;
    this.gameState.selectedUnits = [];
    this.gameState.deployedPlatoons = [];

    // we clear platoons because they left the game flow
    this.platoonData = {};
    this.nextLobbyCode = null;

    this.showScreen('mainMenu');
    this.fetchNUI('resetUI');
};
