window.addEventListener('message', (e) => {
    if (e.data.eventName === 'loadProgress') {
        
        document.body.style.display = 'block';
        const loadScreen = document.getElementById('loadingScreen');
        if (loadScreen) {
            loadScreen.classList.remove('hidden');
            loadScreen.style.display = 'flex';
        }

        const bar = document.getElementById('loadingBarFill');
        const status = document.getElementById('loadingStatusText');
        
        const pct = Math.floor(e.data.loadFraction * 100);

        if (bar) bar.style.width = pct + '%';
        
        if (status) {
            if (pct < 10) {
                status.textContent = `EXECUTING INIT CORE... ${pct}%`;
            } else if (pct < 40) {
                status.textContent = `FETCHING RESOURCE DATA... ${pct}%`;
            } else if (pct < 55) {
                status.textContent = `EXECUTING INIT BEFORE MAP LOADED... ${pct}%`;
            } else if (pct < 75) {
                status.textContent = `MOUNTING MAP ASSETS... ${pct}%`;
            } else if (pct < 90) {
                status.textContent = `EXECUTING INIT AFTER MAP LOADED... ${pct}%`;
            } else if (pct < 98) {
                status.textContent = `EXECUTING INIT SESSION... ${pct}%`;
            } else if (pct < 100) {
                status.textContent = `AWAITING CLIENT SCRIPTS... ${pct}%`;
            } else {
                status.textContent = `HANDOVER COMPLETE AWAITING RENDER`;
            }
        }
    }
});
class TacticalRTS {
    constructor() {
        this.gameState = {
            currentScreen: 'loading',
            isInLobby: false,
            isInMatch: false,
            lobbyCode: null,
            playerReady: false,
            platoons: {},
            selectedUnits: [],
            commandPoints: 0,
            team: 0,
            isHost: false
        };
        this.weight = 20,
        this.tips = [
            "Control the objectives. Or don't, if you enjoy being poor.",
            "Tanks are expensive. Try not to drive them off a cliff.",
            "If you are losing, surrendering saves time... but makes you a coward.",
            "Running out of money is a skill issue. Manage your economy better.",
            "Level up to unlock aircraft. Until then, enjoy walking.",
            "The enemy is capturing your objectives while you read this.",
            "You can deploy heavy support, or you can keep losing. Your choice."
        ];

        this.sounds = {
    hover: new Audio('sounds/hover-1.mp3'),
    menuClick: new Audio('sounds/click-2.mp3'), // Clean "Tap"
    menuOpen: new Audio('sounds/menu-open.mp3'),  // Pneumatic/Heavy

    dispatch: new Audio('sounds/start.mp3'),  // Tech/Radio "Bleep"
    alert: new Audio('sounds/error.mp3'),     // High-priority alert

    countdownBip: new Audio('sounds/countdown.mp3'), // Short sharp bip
    deployUnit: new Audio('sounds/click-1.mp3'), // Tech/Heavy Spawn sound
};

Object.values(this.sounds).forEach(s => s.volume = 0.4);
this.sounds.hover.volume = 0.1;

        this.loadingInterval = null;
        this.mapKeys = []; 
        this.currentMapIndex = 0; 
        this.draggedUnit = null;
        this.dragOverSlot = null;
        this.countdownInterval = null;
        this.unitData = null;
        this.platoonData = {};
        this.currentMap = 'grapeseed';
        this.unitData = {};
        this.unitConfig = {}; 
        this.categories = {};
        this.mapData = {}; 
        this.unitElements = {};
        this.overlayContainer = null;
        this.isQueued = false;
        this.queueTimerInterval = null;
        this.chatTimer = null;
        this.currentChatChannel = "GLOBAL";
        this.isRtsUiOpen = false;
        this.init(true);
        window.addEventListener('keydown', function(e) {
            if (e.key === 'F10') { e.preventDefault(); fetch('https://'+GetParentResourceName()+'/toggleAdmin', {method:'POST',headers:{'Content-Type':'application/json'},body:'{}'}); }
        });
    }
updateObjectiveUI(objectives) {
    if (!objectives) return;
    const objArray = Array.isArray(objectives) ? objectives : Object.values(objectives);

    if (!this.overlayContainer) {
        this.overlayContainer = document.getElementById('game-input-layer');
    }

    const screenW = window.innerWidth || 1920;
    const screenH = window.innerHeight || 1080;
    const currentTimestamp = Date.now();

    objArray.forEach(obj => {
        
        const isPrimary = (obj.type === 'victory' || obj.name === "Safe House" || obj.name === "City Hall");

        if (isPrimary) {
            const mainBar = document.getElementById('objectiveProgress');
            const mainText = document.getElementById('objectiveStatus');

            if (mainBar && mainText) {
                let statusText = "NEUTRAL";
                let barColor = "#bdc3c7";
                let textColor = "#bdc3c7";

                if (obj.owner === 0) {
                    if (obj.progress <= 0 || obj.capper === 0) {
                        statusText = "NEUTRAL ZONE";
                    } else {
                        const rel = this.getRelation(obj.capper);
                        statusText = (rel === 'ally') ? "CAPTURING" : "HOSTILE CAPTURE";
                        barColor = this.getTeamColor(obj.capper);
                        textColor = barColor;
                    }
                } else {
                    const rel = this.getRelation(obj.owner);
                    barColor = this.getTeamColor(obj.owner);
                    textColor = barColor;
                    statusText = (rel === 'ally') ? "CONTROLLED" : "HOSTILE CONTROL";
                    
                    if(rel === 'ally' && obj.capper !== 0 && obj.capper !== obj.owner) {
                        textColor = "#f1c40f"; 
                        statusText = "DEFENSE FAILING";
                    }
                }
                mainBar.style.width = obj.progress + '%';
                mainBar.style.backgroundColor = barColor;
                mainText.innerText = statusText;
                mainText.style.color = textColor;
            }
        }

        const elId = 'obj-' + obj.name.replace(/\s+/g, '-');
        let el = document.getElementById(elId);

        if (!el) {
            el = document.createElement('div');
            el.id = elId;
            el.className = 'objective-box'; 
            el.innerHTML = `
                <div class="obj-icon"><i class="fas"></i></div>
                <div class="obj-bar-bg"><div class="obj-bar-fill"></div></div>
                <div class="obj-name">${obj.name}</div>
            `;
            this.overlayContainer.appendChild(el);
        }

        if (isPrimary) {
            if (!el.classList.contains('primary-objective')) el.classList.add('primary-objective');
            if (el.classList.contains('resource-objective')) el.classList.remove('resource-objective');
        } else {
            if (!el.classList.contains('resource-objective')) el.classList.add('resource-objective');
            if (el.classList.contains('primary-objective')) el.classList.remove('primary-objective');
        }

        el.dataset.lastSeen = currentTimestamp;

        if (!obj.isOnScreen) {
            el.style.display = 'none';
        } else {
            el.style.display = 'flex';
            const x = (obj.x * screenW).toFixed(0);
            const y = (obj.y * screenH).toFixed(0);
            el.style.transform = `translate(${x}px, ${y}px) translate(-50%, -50%)`;
            
            let targetTeam = 0;
            if (obj.owner !== 0) targetTeam = obj.owner; // Owner takes priority
            else if (obj.capper !== 0) targetTeam = obj.capper; // Capper takes secondary priority

            const teamColor = this.getTeamColor(targetTeam); 
            
            let iconClass = 'fa-circle'; 

            if (isPrimary) {
                iconClass = 'fa-location-crosshairs'; // Primary always Crown
            } else {
                const n = obj.name.toLowerCase();
                if (n.includes('oil') || n.includes('fuel') || n.includes('gas')) iconClass = 'fa-oil-can';
                else if (n.includes('ammo') || n.includes('munitions') || n.includes('supply')) iconClass = 'fa-box-open';
                else if (n.includes('comms') || n.includes('radar') || n.includes('uplink')) iconClass = 'fa-satellite-dish';
                else if (n.includes('medic') || n.includes('hospital')) iconClass = 'fa-briefcase-medical';
                else if (n.includes('depot') || n.includes('silo')) iconClass = 'fa-money-bill-wheat';
                else iconClass = 'fa-cube'; // Generic Resource
            }

            const iconI = el.querySelector('.obj-icon i');
            if (iconI && !iconI.classList.contains(iconClass)) {
                iconI.className = `fas ${iconClass}`;
            }

            const iconContainer = el.querySelector('.obj-icon');
            const barFill = el.querySelector('.obj-bar-fill');

            if (iconContainer) {
                iconContainer.style.color = (targetTeam === 0) ? '#e0e0e0' : teamColor;
                iconContainer.style.textShadow = (targetTeam === 0) ? '0 1px 2px #000' : `0 0 15px ${teamColor}`;
            }

            if (barFill) {
                barFill.style.width = obj.progress + '%';
                barFill.style.backgroundColor = teamColor;
                
                if (targetTeam === 0 && obj.progress > 0) {
                     barFill.style.backgroundColor = '#bdc3c7';
                }
            }
        }
    });

    document.querySelectorAll('.objective-box').forEach(el => {
        if (parseInt(el.dataset.lastSeen) !== currentTimestamp) {
            el.style.display = 'none';
        }
    });
}

updateUnitPositions(units) {
    if (!this.overlayContainer) {
        this.overlayContainer = document.getElementById('game-input-layer');
        if (!this.overlayContainer) return;
    }

    const currentTimestamp = Date.now();
    const screenW = window.innerWidth || 1920;
    const screenH = window.innerHeight || 1080;

    units.forEach(unit => {
        const unitId = String(unit.id);
        let el = this.unitElements[unitId];

        if (!el) {
            el = document.createElement('div');
            el.className = 'unit-hitbox';
            el.dataset.id = unitId;

            el.onmousedown = (e) => {
                e.stopPropagation();
                if (e.button === 0) {
                    if (unit.team === this.gameState.team) {
                        this.fetchNUI('selectUnit', { unitId: parseInt(unitId) });
                    }
                } else if (e.button === 2) {
                    if (unit.team !== this.gameState.team) {
                        this.fetchNUI('issueCommand', { type: 'attack', targetId: parseInt(unitId) });
                        el.style.borderColor = "red";
                        setTimeout(() => el.style.borderColor = "transparent", 200);
                    }
                }
            };

            el.innerHTML = `
                <div class="unit-health-bar">
                    <div class="unit-health-text"></div> <div class="unit-damage-flash"></div>
                    <div class="unit-health-fill"></div>
                </div>
            `;
            this.overlayContainer.appendChild(el);
            this.unitElements[unitId] = el;
        }

        el.style.display = 'block';
        el.dataset.lastSeen = currentTimestamp;

        const x = (unit.x * screenW).toFixed(0);
        const y = (unit.y * screenH).toFixed(0);
        el.style.transform = `translate(${x}px, ${y}px)`;

        const textEl = el.querySelector('.unit-health-text');
        if (textEl) {
            const minHealth = 100; // The value where it dies
            const trueMax = unit.max; // e.g., 800

            const effectiveRange = trueMax - minHealth;

            const effectiveCurrent = Math.max(0, unit.cur - minHealth);

            let displayValue = 0;
            if (effectiveRange > 0) {
                displayValue = (effectiveCurrent / effectiveRange) * trueMax;
            }

            textEl.textContent = `${Math.floor(displayValue)}/${trueMax}`;
        }

        const hpFill = el.querySelector('.unit-health-fill');
        const flashFill = el.querySelector('.unit-damage-flash');
        
        const minHealth = 100;
        let visualPercent = ((unit.cur - minHealth) / (unit.max - minHealth)) * 100;
        visualPercent = Math.max(0, Math.min(100, visualPercent));

        if (hpFill) {
            hpFill.style.width = visualPercent + '%';
            if (unit.team === this.gameState.team) {
                hpFill.classList.remove('enemy');
                hpFill.style.backgroundColor = '';
            } else {
                hpFill.classList.add('enemy');
                hpFill.style.backgroundColor = '';
            }
        }

        if (flashFill) {
            flashFill.style.width = visualPercent + '%';
        }

        if (this.gameState.selectedUnits.includes(parseInt(unitId))) {
            el.classList.add('selected');
            el.style.borderColor = "#00ff00";
        } else {
            el.classList.remove('selected');
            el.style.borderColor = "transparent";
        }
    });

    Object.keys(this.unitElements).forEach(key => {
        const el = this.unitElements[key];
        const lastSeen = parseInt(el.dataset.lastSeen || 0);
        if (lastSeen !== currentTimestamp) {
            if (currentTimestamp - lastSeen > 2000) {
                el.remove();
                delete this.unitElements[key];
            } else {
                el.style.display = 'none';
            }
        }
    });
}
    //}
updateDeployedPlatoons(list) {
    const container = document.getElementById('deployedList');
    const parentBox = document.getElementById('activeSquadsPanel');
    
    if (!container || !parentBox) return;
    
    container.innerHTML = '';

    if (!list || !Array.isArray(list) || list.length === 0) {
        parentBox.classList.add('hidden-box');
        return; 
    }

    parentBox.classList.remove('hidden-box');

    list.forEach(p => {
        const div = document.createElement('div');
        div.className = 'deployed-item';
        div.dataset.uuid = p.uuid;

        let statusColor = '#4cd137'; 
        let health = parseInt(p.health) || 0;
        if (health < 50) statusColor = '#fbc531';
        if (health < 25) statusColor = '#ff4757';

        div.innerHTML = `
            <div class="d-icon" style="color:${p.color || '#fff'}"><i class="${p.icon}"></i></div>
            <div class="d-info">
                <div class="d-header">
                    <span class="d-name">${(p.name || 'PLATOON').toUpperCase()}</span>
                    <span class="d-count mono">${p.aliveCount}/${p.maxCount}</span>
                </div>
                <div class="d-bar-bg">
                    <div class="d-bar-fill" style="width:${health}%; background:${statusColor}"></div>
                </div>
            </div>
        `;
        
        container.appendChild(div);
    });
}
    init(first) {
        const isGameMode = !!window.invokeNative; 
        this.overlayContainer = document.getElementById('game-input-layer');

        if (this.tips && this.tips.length > 0) {
            const tipEl = document.getElementById('loadingTipText');
            if (tipEl) tipEl.textContent = this.tips[Math.floor(Math.random() * this.tips.length)];
            setInterval(() => {
                if (tipEl) tipEl.textContent = this.tips[Math.floor(Math.random() * this.tips.length)];
            }, 3000);
        }

        if (!isGameMode) {
            console.log("RTS: Running as Server Loading Screen");
        } else {
            console.log("RTS: Game Engine Ready. Handshaking...");
            
            const bar = document.getElementById('loadingBarFill');
            const status = document.getElementById('loadingStatusText');
            if(bar) bar.style.width = '100%';
            if(status) status.textContent = "CONFIGURING INTERFACE...";

            window.addEventListener('message', this.handleMessage.bind(this));
            this.loadUnitData();
            this.loadMapData();
            this.bindGlobalEvents();
            this.startMouseTracker();
            this.initInputSystem();
            this.startLiveStatsPoller();

            if (first) {
                const handshake = setInterval(() => {
                    if (this.gameState.currentScreen === 'mainMenu') {
                        clearInterval(handshake);
                        return;
                    }
                    this.fetchNUI('initialize', { dedicated: true });
                }, 500); 
            }
        }
    }
    initInputSystem() {
        const selectRect = document.getElementById('selectionRectangle');
        let isDragging = false;
        let startX = 0;
        let startY = 0;

        window.addEventListener('mousedown', (e) => {
            if (!this.gameState.isInMatch) return;

            if (e.target.closest('.quickbar-slot') ||
                e.target.closest('.top-bar') ||
                e.target.closest('.modal') ||
                e.target.closest('button')) {
                return;
            }

            if (e.button === 0) { // Left Click
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
                const normX = e.clientX / window.innerWidth;
                const normY = e.clientY / window.innerHeight;

                this.fetchNUI('issueCommand', {
                    type: 'move',
                    x: normX, // Sending 0.0 - 1.0
                    y: normY
                });
            }
        });

        window.addEventListener('mousemove', (e) => {
            if (!this.gameState.isInMatch) return;

            if (isDragging && selectRect) {
                const currentX = e.clientX;
                const currentY = e.clientY;

                const width = Math.abs(currentX - startX);
                const height = Math.abs(currentY - startY);
                const left = Math.min(currentX, startX);
                const top = Math.min(currentY, startY);

                selectRect.style.width = width + 'px';
                selectRect.style.height = height + 'px';
                selectRect.style.left = left + 'px';
                selectRect.style.top = top + 'px';
            }
        });

        window.addEventListener('mouseup', (e) => {
            if (!this.gameState.isInMatch) return;

            if (e.button === 0 && isDragging) { // Left Release
                isDragging = false;
                if (selectRect) selectRect.classList.add('hidden');

                const endX = e.clientX;
                const endY = e.clientY;
                const dist = Math.sqrt(Math.pow(endX - startX, 2) + Math.pow(endY - startY, 2));

                const w = window.innerWidth;
                const h = window.innerHeight;

                if (dist > 15) {
                    this.fetchNUI('selectUnits', {
                        x1: startX / w,
                        y1: startY / h,
                        x2: endX / w,
                        y2: endY / h
                    });
                } else {
                    this.fetchNUI('selectUnit', {
                        x: endX,
                        y: endY
                    });
                }
            }
        });
    }
    startMouseTracker() {
     
        window.addEventListener('wheel', (e) => {
            if (!this.gameState.isInMatch) return;

            const direction = e.deltaY < 0 ? 'in' : 'out';

            this.fetchNUI('cameraZoom', { direction: direction });
        });
        document.addEventListener('mousemove', (e) => {
            const cursor = document.getElementById('gameCursor');
            if (cursor) {
                cursor.style.left = e.clientX + 'px';
                cursor.style.top = e.clientY + 'px';
                cursor.style.transform = 'none';
            }
        });

    }
        
    async surrenderGame() {
        this.closeModal('settingsModal');
        this.showNotification('Surrendering command...', 'warning');
        
        try {
            await this.fetchNUI('surrenderMatch', {});
        } catch (e) {
            console.error(e);
        }
    }
    bindGlobalEvents() {
    document.addEventListener('mouseover', (e) => {
    if (e.target.matches('.btn, .unit-card, .quickbar-slot, .platoon-unit, .deployed-item, .history-item')) {
        this.playSFX('hover');
    }
});
const musicSlider = document.getElementById('musicVolume');
if (musicSlider) {
    musicSlider.addEventListener('input', (e) => {
        const volume = e.target.value / 100;
        const music = document.getElementById('bgMusic');
        if (music) music.volume = volume;
    });
}

const sfxSlider = document.getElementById('sfxVolume');
if (sfxSlider) {
    sfxSlider.addEventListener('input', (e) => {
        const volume = e.target.value / 100;
        
        Object.values(this.sounds).forEach(s => {
            s.volume = volume;
        });
    });

    sfxSlider.addEventListener('change', () => {
        this.playSFX('menuClick'); 
    });
}
    document.addEventListener('click', (e) => {
        const target = e.target;

        if (target.closest('.quickbar-slot')) {
            const slotEl = target.closest('.quickbar-slot');
            if (!slotEl.classList.contains('disabled')) {
                this.playSFX('deployUnit'); 
            } else {
                this.playSFX('alert'); // Subtle "error" chirp if on cooldown
            }
            return;
        }

        if (target.closest('.btn, .category-btn, .carousel-arrow, .close-modal')) {
            const isHeavyMenu = target.closest('#settingsBtn, #helpBtn, #midGameSettings');
            
            if (isHeavyMenu) {
                this.playSFX('menuOpen'); // Heavier sound for settings/help
            } else {
                this.playSFX('menuClick'); // Standard UI "tick" for navigation
            }
        }
        
        if (target.closest('#copyCode, #readyToggle')) {
            this.playSFX('dispatch'); // Use tactical sound for "Ready" up
        }
    });
            document.addEventListener('mousemove', (e) => {
                const cursor = document.getElementById('gameCursor');
                if (cursor) {
                    cursor.style.left = `${e.clientX}px`;
                    cursor.style.top = `${e.clientY}px`;
                }
            });
            if (musicSlider) {
                musicSlider.addEventListener('input', (e) => {
                    const volume = e.target.value / 100;
                    const music = document.getElementById('bgMusic');
                    if (music) music.volume = volume;
                });
            }
            document.addEventListener('click', (e) => {
                if (e.target.closest('button') || e.target.closest('.btn') || e.target.closest('.platoon-slot')) {
                }
                if (e.target.closest('#midGameSettings')) {
                    this.openSettings();
                }
                if (e.target.closest('#mapNext')) {
                this.nextMap();
            }
            if (e.target.closest('#mapPrev')) {
                this.prevMap();
            }
            if (e.target.closest('#surrenderBtn')) {
               
                    this.surrenderGame();
                
            }
                if (e.target.closest('.category-btn')) {
                    const btn = e.target.closest('.category-btn');
                    const category = btn.dataset.category; // Gets 'infantry', 'vehicles', or 'all'

                    this.filterUnits(category);
                    this.updateCategoryButtons(btn);
                }
                const squadItem = e.target.closest('.deployed-item');
                if (squadItem) {
                    const uuid = squadItem.dataset.uuid;

                    squadItem.classList.add('pulse-select');
                    setTimeout(() => squadItem.classList.remove('pulse-select'), 200);

                    this.fetchNUI('selectPlatoonGroup', { uuid: parseInt(uuid) });
                }
                if (e.target.closest('#quickMatch')) this.quickMatch();
                if (e.target.closest('#createLobby')) this.createLobby();
                if (e.target.closest('#joinLobby')) this.joinLobby();
                if (e.target.closest('#viewStats')) this.viewStats();
                if (e.target.closest('#settingsBtn')) this.openSettings();
                
                if (e.target.closest('#gameSettingsBtn')) this.openSettings();
                if (e.target.closest('#helpBtn')) this.openHelp();
                if (e.target.closest('#exitBtn')) this.exitGame();

                if (e.target.closest('#viewLeaderboard')) this.openLeaderboard();
                if (e.target.closest('#viewHistory')) this.openHistory();

                if (e.target.closest('#leaveLobby')) this.leaveLobby();
                if (e.target.closest('#copyCode')) this.copyLobbyCode();
                if (e.target.closest('#readyToggle')) this.toggleReady();
                if (e.target.closest('#savePlatoons')) this.savePlatoons();
                if (e.target.closest('#clearAll')) this.clearAllPlatoons();

                if (e.target.closest('#toggleBotBtn')) {
                    const btn = e.target.closest('#toggleBotBtn');
                    if (btn.dataset.action === 'add') {
                        this.addBotToLobby();
                    } else {
                        this.kickBotFromLobby();
                    }
                }

                if (e.target.closest('.remove-unit')) {
                    const btn = e.target.closest('.remove-unit');
                    const slot = btn.closest('.platoon-slot').dataset.slot;
                    const type = btn.dataset.unitType;
                    this.removeUnitFromSlot(type, slot);
                }

                if (e.target.closest('.quickbar-slot')) {
                    const slot = e.target.closest('.quickbar-slot');
                    if (!slot.classList.contains('disabled')) this.spawnPlatoon(slot.dataset.slot);
                }

                if (e.target.closest('#closeSettings')) this.closeModal('settingsModal');
                if (e.target.closest('#closeHelp')) this.closeModal('helpModal');
                if (e.target.closest('#saveSettings')) this.saveSettings();
            });

            document.addEventListener('keydown', (e) => {
                if (e.key === 'Enter') {
                    const input = document.getElementById('lobbyCodeInput');
                    if (document.activeElement === input) this.joinLobby();
                }

                if (e.key === 'Escape') {
                    if (this.gameState.currentScreen === 'gameUI') this.hideCommandPanel();
                    else if (this.gameState.currentScreen === 'lobbyScreen') this.leaveLobby();
                    const settingsModal = document.getElementById('settingsModal');
                    if (settingsModal && !settingsModal.classList.contains('hidden')) {
                        this.closeModal('settingsModal');
                        return; // Stop here
                    }

                    const helpModal = document.getElementById('helpModal');
                    if (helpModal && !helpModal.classList.contains('hidden')) {
                        this.closeModal('helpModal');
                        return; // Stop here
                    }

                    if (this.gameState.currentScreen === 'gameUI') {
                        this.hideCommandPanel();
                    } else if (this.gameState.currentScreen === 'lobbyScreen') {
                        this.leaveLobby();
                    }
                }
            });

            this.initManualDragSystem();

            document.addEventListener('keydown', (e) => {
                const inputWrapper = document.getElementById('rts-chat-input-wrapper');
                const chatInput = document.getElementById('rts-chat-input');
                if (!inputWrapper || !chatInput) return;
                const isTyping = inputWrapper.style.visibility === "visible";
                if (!isTyping && (e.key === 't' || e.key === 'T' || e.key === 'Enter')) {
                    if (document.activeElement && document.activeElement.tagName === "INPUT") return;
                    e.preventDefault();
                    this.openChatUI();
                    return;
                }
                if (isTyping) {
                    if (e.key === 'Enter') {
                        e.preventDefault();
                        let msg = chatInput ? chatInput.value.trim() : "";
                        if (msg !== "") this.fetchNUI('sendChatMessage', { message: msg });
                        this.closeChatUI();
                    }
                    if (e.key === 'Escape') this.closeChatUI();
                }
            });
        }
    initDragAndDropSystem() {
        const unitsList = document.getElementById('unitsList');
        if (unitsList) {
            document.addEventListener('dragstart', (e) => {
                const card = e.target.closest('.unit-card');
                if (card) {
                    this.draggedUnit = card.dataset.unitType;
                    e.dataTransfer.setData('text/plain', this.draggedUnit);
                    e.dataTransfer.effectAllowed = 'copyMove';

                    var dragIcon = card.cloneNode(true);
                    dragIcon.classList.remove('dragging'); // Ensure ghost is visible
                    dragIcon.style.position = "absolute";
                    dragIcon.style.top = "-1000px";
                    dragIcon.style.opacity = "1";
                    dragIcon.style.width = card.offsetWidth + "px"; // Keep size
                    document.body.appendChild(dragIcon);
                    e.dataTransfer.setDragImage(dragIcon, 0, 0);

                    setTimeout(() => {
                        card.classList.add('dragging');
                        document.body.removeChild(dragIcon); // Clean up ghost source
                    }, 0);

                }
            });

            unitsList.addEventListener('dragend', (e) => {
                const card = e.target.closest('.unit-card');
                if (card) card.classList.remove('dragging');

                this.draggedUnit = null;

                document.querySelectorAll('.platoon-slot').forEach(slot => {
                    slot.classList.remove('drag-over');
                });
            });
        }

        const slotContainer = document.querySelector('.platoon-slots');
        if (slotContainer) {
            slotContainer.addEventListener('dragover', (e) => {
                const slot = e.target.closest('.platoon-slot');
                if (slot) {
                    e.preventDefault(); // This is required to allow dropping!
                    slot.classList.add('drag-over');
                    this.dragOverSlot = slot.dataset.slot;
                }
            });

            slotContainer.addEventListener('dragleave', (e) => {
                const slot = e.target.closest('.platoon-slot');
                if (slot) {
                    slot.classList.remove('drag-over');
                }
            });

            slotContainer.addEventListener('drop', (e) => {
                e.preventDefault();
                const slot = e.target.closest('.platoon-slot');
                if (slot && this.draggedUnit) {
                    slot.classList.remove('drag-over');
                    const slotNum = slot.dataset.slot;
                    this.showUnitSelectionModal(this.draggedUnit, slotNum);
                }
            });
        }
    }
    startLoadingAnimation(targetScreen = 'mainMenu', incomingData = {}) {
        const screen = document.getElementById('loadingScreen');
        const bar = document.getElementById('loadingBarFill'); // New ID
        const statusText = document.getElementById('loadingStatusText'); // New ID
        const tipText = document.getElementById('loadingTipText'); // New Feature

        if (screen) screen.classList.remove('hidden');
        if (bar) bar.style.width = '0%';
        
        if (tipText && this.tips && this.tips.length > 0) {
            tipText.textContent = this.tips[Math.floor(Math.random() * this.tips.length)];
        }

        if (this.loadingInterval) clearInterval(this.loadingInterval);

        let progress = 0;
        this.loadingInterval = setInterval(() => {
            let add = Math.random() * 7;
            if (progress < 30) add = Math.random() * 10;
            else if (progress < 60) add = Math.random() * 5;
            else if (progress < 90) add = Math.random() * 15;
            else add = Math.random() * 10;
            
            progress += add;
            if (progress > 100) progress = 100;

            if (bar) bar.style.width = progress + '%';

            if (statusText) {
                if (progress < 30) statusText.textContent = 'LOADING CORE SYSTEMS...';
                else if (progress < 60) statusText.textContent = 'INITIALIZING BATTLEFIELD...';
                else if (progress < 90) statusText.textContent = 'CONFIGURING UNITS...';
                else statusText.textContent = 'READY FOR DEPLOYMENT';
            }

            if (progress >= 100) {
                clearInterval(this.loadingInterval);
                
                setTimeout(() => {
                    if (screen) screen.classList.add('hidden');

                    this.showScreen(targetScreen, incomingData);

                    if (!incomingData || Object.keys(incomingData).length === 0) {
                        this.fetchNUI('initialize', {}).then(() => {
                            console.log('RTS NUI Initialized (Cold Start)');
                        });
                    }
                }, 500);
            }
        }, 210);
    }

    bindEvents() {
            document.addEventListener('mousemove', (e) => {
                const cursor = document.getElementById('gameCursor');
                if (cursor) {
                    cursor.style.left = `${e.clientX}px`;
                    cursor.style.top = `${e.clientY}px`;
                }
            });
            document.addEventListener('click', (e) => {
                if (e.target.closest('#quickMatch')) this.quickMatch();
                if (e.target.closest('#createLobby')) this.createLobby();
                if (e.target.closest('#joinLobby')) this.joinLobby();
                if (e.target.closest('#viewStats')) this.viewStats();
                if (e.target.closest('#settingsBtn')) this.openSettings();
                if (e.target.closest('#helpBtn')) this.openHelp();
                if (e.target.closest('#exitBtn')) this.exitGame();

                if (e.target.closest('#mapNext')) this.nextMap();
                if (e.target.closest('#mapPrev')) this.prevMap();

                if (e.target.closest('#leaveLobby')) this.leaveLobby();
                if (e.target.closest('#copyCode')) this.copyLobbyCode();
                if (e.target.closest('#readyToggle')) this.toggleReady();
                if (e.target.closest('#savePlatoons')) this.savePlatoons();
                if (e.target.closest('#clearAll')) this.clearAllPlatoons();

                if (e.target.closest('.category-btn')) {
                    const btn = e.target.closest('.category-btn');
                    const category = btn.dataset.category;
                    this.filterUnits(category);
                    this.updateCategoryButtons(btn);
                }

                if (e.target.closest('.remove-unit')) {
                    const removeBtn = e.target.closest('.remove-unit');
                    const unitType = removeBtn.dataset.unitType;
                    const slot = removeBtn.closest('.platoon-slot').dataset.slot;
                    this.removeUnitFromSlot(unitType, slot);
                }

                if (e.target.closest('.quickbar-slot')) {
                    const slotElement = e.target.closest('.quickbar-slot');
                    if (!slotElement.classList.contains('disabled')) {
                        const slot = slotElement.dataset.slot;
                        this.spawnPlatoon(slot);
                    }
                }

                if (e.target.closest('.command-btn')) {
                    const command = e.target.closest('.command-btn').dataset.command;
                    this.issueCommand(command);
                }

                if (e.target.closest('#closeCommands')) this.hideCommandPanel();

                if (e.target.closest('#zoomIn')) this.zoomMinimap(1.2);
                if (e.target.closest('#zoomOut')) this.zoomMinimap(0.8);

                if (e.target.closest('#rematchBtn')) this.rematch();
                if (e.target.closest('#returnToMenuBtn')) this.returnToMenu();

                if (e.target.closest('#closeSettings')) this.closeModal('settingsModal');
                if (e.target.closest('#closeHelp')) this.closeModal('helpModal');
                if (e.target.closest('#saveSettings')) this.saveSettings();
            });

            const mapSelect = document.getElementById('mapSelect');
            if (mapSelect) {
                mapSelect.addEventListener('change', (e) => {
                    this.currentMap = e.target.value;
                    this.updateMapPreview(e.target.value);
                });
            }

            const lobbyCodeInput = document.getElementById('lobbyCodeInput');
            if (lobbyCodeInput) {
                lobbyCodeInput.addEventListener('keypress', (e) => {
                    if (e.key === 'Enter') {
                        this.joinLobby();
                    }
                });
            }

            this.initDragAndDropSystem();

            document.addEventListener('keydown', (e) => {
                if (e.key === 'Escape') {
                    if (this.gameState.currentScreen === 'gameUI') {
                        this.hideCommandPanel();
                    } else if (this.gameState.currentScreen === 'lobbyScreen') {
                        this.leaveLobby();
                    }
                }
            });
            document.addEventListener('keydown', (e) => {
                const inputWrapper = document.getElementById('rts-chat-input-wrapper');
                const chatInput = document.getElementById('rts-chat-input');
                if (!inputWrapper || !chatInput) return;
                const isTyping = inputWrapper.style.visibility === "visible";

                if (!isTyping && (e.key === 't' || e.key === 'T' || e.key === 'Enter')) {
                    if (document.activeElement && document.activeElement.tagName === "INPUT") return;
                    e.preventDefault();
                    this.openChatUI();
                    return;
                }

                if (isTyping) {
                    if (e.key === 'Enter') {
                        e.preventDefault();
                        let msg = chatInput ? chatInput.value.trim() : "";
                        if (msg !== "") {
                            this.fetchNUI('sendChatMessage', { message: msg });
                        }
                        this.closeChatUI();
                    }
                    else if (e.key === 'Escape') {
                        e.preventDefault();
                        this.closeChatUI();
                    }
                }
            });
            this.initManualDragSystem();
        }

    initManualDragSystem() {
        let dragClone = null;
        let dragData = null;
        let dragOffsetX = 0;
        let dragOffsetY = 0;

        document.addEventListener('mousedown', (e) => {
            if (e.button !== 0) return; // Only Left Click

            const card = e.target.closest('.unit-card');
            if (!card || card.classList.contains('locked')) return;

            e.preventDefault();

            const rect = card.getBoundingClientRect();
            dragOffsetX = e.clientX - rect.left;
            dragOffsetY = e.clientY - rect.top;

            dragData = card.dataset.unitType;

            dragClone = card.cloneNode(true);
            dragClone.className = 'unit-card dragging-clone';

            dragClone.style.width = `${rect.width}px`;
            dragClone.style.height = `${rect.height}px`;

            document.body.appendChild(dragClone);

            const x = e.clientX - dragOffsetX;
            const y = e.clientY - dragOffsetY;
            dragClone.style.transform = `translate3d(${x}px, ${y}px, 0)`;

            card.classList.add('dragging-source');

        });

        document.addEventListener('mousemove', (e) => {
            if (!dragClone) return;

            const x = e.clientX - dragOffsetX;
            const y = e.clientY - dragOffsetY;
            dragClone.style.transform = `translate3d(${x}px, ${y}px, 0)`;
        });

        document.addEventListener('mouseup', (e) => {
            if (!dragClone) return;

            dragClone.remove();
            dragClone = null;
            document.querySelectorAll('.dragging-source').forEach(el => el.classList.remove('dragging-source'));

            const elementUnderMouse = document.elementFromPoint(e.clientX, e.clientY);
            const slot = elementUnderMouse ? elementUnderMouse.closest('.platoon-slot') : null;

            if (slot && dragData) {
                this.showUnitSelectionModal(dragData, slot.dataset.slot);
            }

            dragData = null;
        });
    }
    handleMessage(event) {
        const data = event.data;

        if (!data || !data.action) return;

        switch (data.action) {
            case 'abortCountdown':
                this.abortCountdown();
                break;
            case 'updatePopulation':
                this.updatePopulationDisplay(data);
                break;
            case 'adminForceStart':
                this.savePlatoons(); // Force the save
                
                setTimeout(() => {
                    this.fetchNUI('adminConfirmForceStart', {});
                }, 500); 
                break;
            case 'showCentralMenu':
                this.isRtsUiOpen = true;
                if (data.serverStats) this.updateServerInfo(data.serverStats);
                if (data.serverStats && data.serverStats.myStats) this.updateStats(data.serverStats.myStats);

                const loader = document.getElementById('loadingScreen');
                if (loader) {
                    loader.style.transition = 'opacity 1s ease-out';
                    loader.style.opacity = '0';
                    setTimeout(() => { loader.style.display = 'none'; }, 1000);
                }
                break;
            case 'updateServerData':
                if (data.serverStats) {
                    this.cachedStats = data.serverStats; 
                    
                    this.updateServerInfo(data.serverStats);
                    if (data.serverStats.myStats) {
                        this.updateStats(data.serverStats.myStats);
                    }
                }
                break;
            case 'updateDeployedPlatoons':
                this.updateDeployedPlatoons(data.platoons);
                break;

                break;
            case 'updateLobby':
                if (this.isQueued) this.resetQueueUI();
                
                const codeDisplay = document.getElementById('lobbyCodeDisplay');
                if (codeDisplay && data.lobbyCode) {
                    codeDisplay.textContent = data.lobbyCode;
                }
                
                this.updateLobbyPlayers(data);
                break;
            case 'startAirstrikeTimer':
                this.startAirstrikeTimer(data.duration);
                break;

            case 'stopAirstrikeTimer':
                this.stopAirstrikeTimer();
                break;
            case 'setUnitConfig':
                this.unitConfig = data.units;
                this.unitData = data.units;
                this.categories = data.categories;
                this.mapData = data.maps;
                this.keyConfig = data.keys;

                this.renderCategoryButtons();
                this.renderUnitList('all');
                this.renderMapList();

                if (this.gameState.currentScreen !== 'mainMenu') {
                    this.showScreen('mainMenu');
                    const loader = document.getElementById('loadingScreen');
                    if (loader && loader.style.display !== 'none') {
                        loader.style.transition = 'opacity 1s ease-out';
                        loader.style.opacity = '0';
                        setTimeout(() => { loader.style.display = 'none'; }, 1000);
                    }
                }
                break;
            case 'toggleCinematic':
    const uiMain = document.getElementById('gameUI'); 
    const selectionPanel = document.getElementById('activeSquadsPanel');
    const inputLayer = document.getElementById('game-input-layer');
    const notificationBox = document.getElementById('notificationContainer');
    const crosshair = document.getElementById('gameCursor');

    if (data.state) {
        if (uiMain) uiMain.style.visibility = 'hidden';
        if (selectionPanel) selectionPanel.style.visibility = 'hidden';
        if (inputLayer) inputLayer.style.display = 'none';
        if (notificationBox) notificationBox.style.display = 'none';
        if (crosshair) crosshair.style.display = 'none';
        
        document.body.style.background = 'none';
    } else {
        if (uiMain) uiMain.style.visibility = 'visible';
        if (selectionPanel) selectionPanel.style.visibility = 'visible';
        if (inputLayer) inputLayer.style.display = 'block';
        if (notificationBox) notificationBox.style.display = 'block';
        if (crosshair) crosshair.style.display = 'block';
    }
    break;
            case 'updateObjectiveUI':
                this.updateObjectiveUI(data.objectives);
                break;
            case 'updateUnitPositions':
                this.updateUnitPositions(data.units);
                break;
            case 'hideUI':
                this.isRtsUiOpen = false;
                document.body.style.display = 'none';
                break;
            case 'unhideUI':
                this.isRtsUiOpen = true;
                document.body.style.display = ''; // Restores default CSS visibility
                break;
            case 'lobbyCreated':
                this.isRtsUiOpen = true;
                this.currentChatChannel = "LOBBY";
                this.handleLobbyCreated(data);
                break;

            case 'lobbyJoined':
                this.isRtsUiOpen = true;
                this.currentChatChannel = "LOBBY";
                this.handleLobbyJoined(data);
                break;

            case 'playerLeft':
                this.showNotification(`${data.playerName} left the lobby`, 'warning');
                break;

            case 'playerReadyUpdate':
                this.updatePlayerReadyStatus(data.playerId, data.ready);
                break;

            case 'startCountdown':
                this.startCountdown(data.duration);
                break;

            case 'startMatch':
                this.isRtsUiOpen = true;
                this.currentChatChannel = "MATCH";
                this.startMatch(data);
                break;

            case 'unitSpawned':
                break;

            case 'updateSelection':
                this.updateSelectionInfo(data);
                break;

            case 'updateResources':
                this.updateResourceDisplay(data);
                break;

            case 'updateTimer':
                this.updateTimerDisplay(data);
                break;

            case 'updateCapture':
                this.updateCaptureDisplay(data);
                break;

           case 'objectiveCaptured':
                const isAlly = data.team === this.gameState.team;
                this.showNotification(
                    `${data.name} captured by ${isAlly ? 'Allied Forces' : 'Enemy Forces'}`,
                    isAlly ? 'success' : 'error'
                );
                break;

            case 'updatePlatoonCooldown':
                this.updatePlatoonCooldown(data.index, data.cooldown);
                break;

            case 'endMatch':
                this.currentChatChannel = "GLOBAL";
                this.showMatchResult(data);
                break;

            case 'updateCursor':
                this.updateCursorPosition(data.x, data.y);
                break;

            case 'updateSelectionRectangle':
                this.showSelectionRectangle(data.x1, data.y1, data.x2, data.y2);
                break;

            case 'clearSelectionRectangle':
                this.hideSelectionRectangle();
                break;

            case 'resetUI':
                this.currentChatChannel = "GLOBAL";
                this.showScreen('mainMenu');
                if (data.serverStats) {
                    this.updateServerInfo(data.serverStats);
                    if (data.serverStats.myStats) {
                        this.updateStats(data.serverStats.myStats);
                    }
                }
                this.gameState.isInLobby = false;
                this.gameState.playerReady = false;
                this.gameState.isInMatch = false;
                break;

            case 'hideUI':

            case 'addChatMessage':
                this.addChatMessage(data.sender, data.message, data.channel);
                break;
        }
    }

    openChatUI() {
        const inputWrapper = document.getElementById('rts-chat-input-wrapper');
        const chatInput = document.getElementById('rts-chat-input');
        this.showChatBox();
        if (inputWrapper) inputWrapper.style.visibility = "visible";
        document.getElementById('rts-chat-channel').innerText = "[" + this.currentChatChannel + "]";
        if (chatInput) chatInput.focus();
        document.getElementById('rts-chat-messages').scrollTop = document.getElementById('rts-chat-messages').scrollHeight;
        this.fetchNUI('chatTyping', { typing: true });
    }

    closeChatUI() {
        const inputWrapper = document.getElementById('rts-chat-input-wrapper');
        const chatInput = document.getElementById('rts-chat-input');
        if (chatInput) { chatInput.value = ""; chatInput.blur(); }
        if (inputWrapper) inputWrapper.style.visibility = "hidden";
        this.resetChatFadeTimer();
        this.fetchNUI('chatTyping', { typing: false });
    }

    addChatMessage(sender, message, channel) {
        const messagesDiv = document.getElementById('rts-chat-messages');
        const msgDiv = document.createElement('div');
        msgDiv.className = `chat-msg ${channel}`;
        const channelTag = channel.toUpperCase();
        msgDiv.innerHTML = `<span class="sender">[${channelTag}] ${sender}:</span> <span class="text">${message}</span>`;
        messagesDiv.appendChild(msgDiv);
        if (messagesDiv.childNodes.length > 50) {
            messagesDiv.removeChild(messagesDiv.firstChild);
        }
        messagesDiv.scrollTop = messagesDiv.scrollHeight;
        this.showChatBox();
        this.resetChatFadeTimer();
    }

    showChatBox() {
        const container = document.getElementById('rts-chat-container');
        if (container) container.classList.add('active');
        if (this.chatTimer) clearTimeout(this.chatTimer);
    }

    resetChatFadeTimer() {
        if (this.chatTimer) clearTimeout(this.chatTimer);
        this.chatTimer = setTimeout(() => {
            const inputWrapper = document.getElementById('rts-chat-input-wrapper');
            const isTyping = inputWrapper && inputWrapper.style.visibility === "visible";
            if (!isTyping) {
                const container = document.getElementById('rts-chat-container');
                if (container) container.classList.remove('active');
            }
        }, 7000);
    }

    async fetchNUI(action, data) {
        return fetch(`https://${GetParentResourceName()}/${action}`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify(data)
            })
            .then(resp => resp.json())
            .catch(err => {
                console.error('NUI Fetch Error:', err);
                console.log(`https://${GetParentResourceName()}/${action}`);
                return { success: false, message: 'Connection failed' };
            });
    }

    async quickMatch() {
        const btn = document.getElementById('quickMatch');
        const btnText = btn.querySelector('span');
        const btnIcon = btn.querySelector('i');
        const estTime = document.getElementById('estTime');

        if (!this.isQueued) {
            try {
                const res = await this.fetchNUI('joinQueue');
                if (res.success) {
                    this.isQueued = true;

                    btn.classList.remove('btn-primary');
                    btn.classList.add('btn-danger');
                    btnText.textContent = "CANCEL SEARCH";
                    btnIcon.className = "fas fa-times";

                    let seconds = 0;
                    if (estTime) estTime.textContent = "SEARCHING: 00:00";

                    this.queueTimerInterval = setInterval(() => {
                        seconds++;
                        const m = Math.floor(seconds / 60).toString().padStart(2, '0');
                        const s = (seconds % 60).toString().padStart(2, '0');
                        if (estTime) estTime.textContent = `SEARCHING: ${m}:${s}`;
                    }, 1000);

                    this.showNotification('Joined matchmaking queue', 'info');

                    const waitTime = (res && res.playerCount <= 1) ? 5000 : 30000;
                    
                    this.aiPromptTimer = setTimeout(() => {
                        if (this.isQueued) { 
                            const modal = document.getElementById('aiPromptModal');
                            if (modal) modal.classList.remove('hidden');
                            this.playSFX('alert'); // Play a sound so they notice the popup
                        }
                    }, waitTime);
                }
            } catch (e) { console.error(e); }

        } else {
            try {
                await this.fetchNUI('leaveQueue');
                this.resetQueueUI();
                this.showNotification('Matchmaking cancelled', 'warning');
                
                if (this.aiPromptTimer) clearTimeout(this.aiPromptTimer);
                const modal = document.getElementById('aiPromptModal');
                if (modal) modal.classList.add('hidden');
            } catch (e) { console.error(e); }
        }
    }

    async createLobby() {
        const mapSelect = document.getElementById('mapSelect');
        const map = this.currentMap || 'grapeseed';
        this.currentMap = map;

        this.showNotification('Creating lobby...', 'info');

        try {
            const response = await this.fetchNUI('createLobby', { map });

            if (response.success) {
                this.gameState.lobbyCode = response.code;
                this.gameState.isHost = true;
            } else {
                this.showNotification(response.message || 'Failed to create lobby', 'error');
            }
        } catch (error) {
            console.error('Create lobby error:', error);
            this.showNotification('Failed to create lobby', 'error');
        }
    }

    async joinLobby() {
        const lobbyCodeInput = document.getElementById('lobbyCodeInput');
        if (!lobbyCodeInput) return;

        const code = lobbyCodeInput.value.toUpperCase().trim();

        if (code.length !== 6) {
            this.showNotification('Invalid lobby code (6 characters required)', 'error');
            return;
        }

        this.showNotification('Joining lobby...', 'info');

        try {
            const payload = { code: code || this.nextLobbyCode };

            const response = await this.fetchNUI('joinLobby', payload);

            if (response.success) {
                this.gameState.lobbyCode = payload.code;
                this.gameState.isHost = false;
                if (lobbyCodeInput) lobbyCodeInput.value = '';

                this.handleLobbyJoined(response);

            } else {
                this.showNotification(response.message || 'Failed to join lobby', 'error');
            }
        } catch (error) {
            console.error('Join lobby error:', error);
        }
    }

    async leaveLobby() {
        try {
            await this.fetchNUI('leaveLobby', {});
            this.showScreen('mainMenu');
            this.gameState.isInLobby = false;
            this.gameState.playerReady = false;
            this.gameState.isHost = false;
            this.platoonData = {};
        } catch (error) {
            console.error('Leave lobby error:', error);
        }
    }

copyLobbyCode() {

    const display = document.getElementById('lobbyCodeDisplay');
    const btn = document.getElementById('copyCode');
    
    const container = btn ? btn.closest('.lobby-code-box') : null;

    if (!display || !container) {
        console.error("[RTS ERROR] Could not find display or container box");
        return;
    }

    const originalCode = display.textContent;
    const icon = btn.querySelector('i');

    const triggerEffect = () => {
        display.textContent = "COPIED";
        
        if (icon) {
            icon.className = "fas fa-check-circle";
        }

        container.classList.add('code-copied-state');
        
        setTimeout(() => {
            display.textContent = originalCode;
            container.classList.remove('code-copied-state');
            if (icon) {
                icon.className = "fas fa-copy";
            }
        }, 300);
    };

    if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(originalCode)
            .then(() => {
                triggerEffect();
            })
            .catch(err => {
                this.fallbackCopy(originalCode);
                triggerEffect(); // Visual feedback even on fallback
            });
    } else {
        this.fallbackCopy(originalCode);
        triggerEffect();
    }
}

    async toggleReady() {
        if (!this.gameState.playerReady) {
            await this.savePlatoons();
        }

        this.gameState.playerReady = !this.gameState.playerReady;

        const readyBtn = document.getElementById('readyToggle');
        const indicator = document.getElementById('readyIndicator');
        const statusText = document.getElementById('readyStatusText');

        if (this.gameState.playerReady) {
            if (readyBtn) {
                readyBtn.innerHTML = '<i class="fas fa-pause-circle"></i><span>NOT READY</span>';
                readyBtn.classList.add('ready');
            }
            if (indicator) {
                indicator.innerHTML = '<i class="fas fa-check-circle"></i><span>READY</span>';
                indicator.classList.add('ready');
            }
            if (statusText) statusText.textContent = 'DEPLOYMENT CONFIRMED';
        } else {
            if (readyBtn) {
                readyBtn.innerHTML = '<i class="fas fa-play-circle"></i><span>READY</span>';
                readyBtn.classList.remove('ready');
            }
            if (indicator) {
                indicator.innerHTML = '<i class="fas fa-times-circle"></i><span>NOT READY</span>';
                indicator.classList.remove('ready');
            }
            if (statusText) statusText.textContent = 'AWAITING COMMANDERS';
        }

        await this.fetchNUI('readyToggle', { ready: this.gameState.playerReady });
    }
getRelation(teamId) {
    if (teamId === 0) return 'neutral';
    if (teamId === this.gameState.team) return 'ally';
    return 'enemy';
}

getTeamColor(teamId) {
    const rel = this.getRelation(teamId);
    if (rel === 'ally') return '#00a8ff'; // Blue
    if (rel === 'enemy') return '#ff4757'; // Red
    return '#bdc3c7'; // Neutral Grey
}

   startCountdown(duration) {
    const countdownContainer = document.getElementById('countdownContainer');
    const countdownTimer = document.getElementById('countdownTimer');

    if (!countdownContainer || !countdownTimer) return;

    countdownContainer.style.display = 'block';
    countdownTimer.textContent = duration;
    let timeLeft = duration;

    this.playSFX('countdownBip');

    if (this.countdownInterval) {
        clearInterval(this.countdownInterval);
    }

    this.countdownInterval = setInterval(() => {
        timeLeft--;
        
        if (timeLeft > 0) {
            countdownTimer.textContent = timeLeft;
            this.playSFX('countdownBip');
        } 
        else {
            clearInterval(this.countdownInterval);
            countdownTimer.textContent = "0";
            
            setTimeout(() => {
                countdownContainer.style.display = 'none';
            }, 500);
        }
    }, 1000);
}

renderCategoryButtons() {
    const container = document.querySelector('.unit-categories');
    if (!container || !this.categories) return;

    container.innerHTML = '';

    const allBtn = document.createElement('button');
    allBtn.className = 'category-btn active';
    allBtn.dataset.category = 'all';
    allBtn.innerHTML = `<i class="fas fa-th-large"></i> <span>ALL</span>`;
    container.appendChild(allBtn);

    let sortedCats = Object.entries(this.categories).map(([key, data]) => {
        return { id: key, name: data.name, icon: data.icon, sort: data.sort || 99 };
    });
    sortedCats.sort((a, b) => a.sort - b.sort);

    sortedCats.forEach(cat => {
        const btn = document.createElement('button');
        btn.className = 'category-btn';
        btn.dataset.category = cat.id;
        btn.innerHTML = `<i class="${cat.icon}"></i> <span>${cat.name}</span>`;
        container.appendChild(btn);
    });
}

renderUnitList(category = 'all') {
    const list = document.getElementById('unitsList');
    if (!list) return;
    list.innerHTML = '';

    const playerLevel = (this.myStats && this.myStats.levelData) ? this.myStats.levelData.level : 1;

    let highestUnlockFound = -1;
    let newestUnitKey = null;

    Object.entries(this.unitConfig).forEach(([key, unit]) => {
        const unlockLvl = unit.unlockLevel || 0;
        if (unlockLvl <= playerLevel && unlockLvl > highestUnlockFound) {
            highestUnlockFound = unlockLvl;
            newestUnitKey = key;
        }
    });

    const sortedUnits = Object.entries(this.unitConfig).sort(([, a], [, b]) => {
        return (a.unlockLevel || 0) - (b.unlockLevel || 0);
    });

    sortedUnits.forEach(([key, unit]) => {
        if (category === 'all' || unit.category === category) {
            
            const unlockLvl = unit.unlockLevel || 0;
            const isLocked = playerLevel < unlockLvl;
            const isNew = (key === newestUnitKey) && !isLocked;

            const card = document.createElement('div');
            
            let classString = 'unit-card';
            if (isLocked) classString += ' locked';
            if (isNew) classString += ' has-badge'; 
            
            card.className = classString;
            card.dataset.unitType = key;

            if (isLocked) {
                card.removeAttribute('draggable');
            } else {
                card.setAttribute('draggable', 'true');
            }

            const bgImage = unit.thumbnail ? `images/units/${unit.thumbnail}` : 'images/units/default.png';
            card.style.backgroundImage = `url('${bgImage}')`;

            const nameText = isLocked 
                ? `<span class="locked-text">UNLOCK LVL ${unlockLvl}</span>` 
                : unit.name;

            const badgeHTML = isNew ? `<div class="new-badge">NEW</div>` : '';

            card.innerHTML = `
                ${badgeHTML}
                
                <div class="unit-weight">
                    ${unit.weight} <i class="fas fa-weight-hanging"></i>
                </div>

                <div class="unit-header">
                    <div class="unit-name">${nameText}</div>
                </div>
                
                ${!isLocked ? `
                    <div class="card-stat stat-hp">
                        <i class="fas fa-heart"></i> ${unit.health}
                    </div>
                    <div class="card-stat stat-cost">
                        ${unit.cost} <i class="fas fa-coins"></i>
                    </div>
                ` : `
                    <div class="lock-overlay"><i class="fas fa-lock"></i></div>
                `}
            `;

            list.appendChild(card);
        }
    });
}

showUnitSelectionModal(unitType, slot) {
    const unit = this.unitData[unitType];
    if (!unit) {
        this.showNotification("Unit data error", "error");
        return;
    }

    const existingModal = document.querySelector('.selection-modal');
    if (existingModal) existingModal.remove();

    const uName = unit.name || 'UNKNOWN';
    const uCost = parseInt(unit.cost || 0);
    const uWeight = parseInt(unit.weight || 0);
    const uDesc = unit.description || 'System data unavailable.';
    
    const bgImage = unit.thumbnail ? `images/units/${unit.thumbnail}` : 'images/units/default.png';

    const modalWrapper = document.createElement('div');
    modalWrapper.className = 'modal selection-modal';
    modalWrapper.style.display = 'flex'; 

    modalWrapper.innerHTML = `
        <div class="modal-content tech-panel" style="width: 500px; padding: 0;">
            
            <div style="padding: 20px 30px; background: rgba(0,0,0,0.3); border-bottom: 1px solid rgba(255,255,255,0.1); display: flex; justify-content: space-between; align-items: center;">
                <div>
                    <h3 class="gold-text" style="font-family: var(--font-head); margin: 0; font-size: 1.4rem; letter-spacing: 1px;">RECRUIT UNIT</h3>
                    <div style="font-family: var(--font-mono); font-size: 0.8rem; color: #666;">SEQ: ${Date.now().toString().slice(-6)}</div>
                </div>
                <button class="close-modal" style="position: static;"><i class="fas fa-times"></i></button>
            </div>

            <div style="padding: 30px;">
                
                <div class="modal-grid-layout">
                    <div class="unit-preview-box" style="background-image: url('${bgImage}');"></div>
                    
                    <div class="unit-data-rows">
                        <div style="font-family: var(--font-head); font-size: 1.2rem; color: var(--cyan); margin-bottom: 5px;">${uName}</div>
                        <div class="data-row">
                            <span class="data-lbl">UNIT COST</span>
                            <span class="data-val" style="color: var(--green);">${uCost}</span>
                        </div>
                        <div class="data-row">
                            <span class="data-lbl">PAYLOAD LOAD</span>
                            <span class="data-val" style="color: var(--cyan);">${uWeight}</span>
                        </div>
                        <div style="font-size: 0.85rem; color: #888; font-style: italic; margin-top: 5px; line-height: 1.2;">
                            "${uDesc}"
                        </div>
                    </div>
                </div>

                <div class="deployment-control">
                    <div class="slider-header">
                        <span class="data-lbl" style="color: var(--cyan);">QUANTITY SELECTOR</span>
                        <div class="count-display-large" id="modalUnitCount">1</div>
                    </div>
                    <input type="range" id="modalRangeInput" class="tech-slider" min="1" max="10" value="1" step="1">
                    <div style="display: flex; justify-content: space-between; margin-top: 5px; font-family: var(--font-mono); font-size: 0.7rem; color: #555;">
                        <span>1</span><span>10</span>
                    </div>
                </div>

                <div class="deployment-totals">
                    <div>
                        <div class="total-lbl">TOTAL REQUISITION COST</div>
                        <div style="font-size: 0.75rem; color: #666; font-family: var(--font-mono);">TOTAL LOAD: <span id="modalTotalWeight" style="color: #ccc;">${uWeight}</span></div>
                    </div>
                    <div class="total-val" id="modalTotalCost">${uCost}</div>
                </div>

                <div style="display: flex; gap: 15px;">
                    <button class="btn btn-secondary cancel" style="flex: 1;">ABORT</button>
                    <button class="btn btn-primary confirm" style="flex: 1;">CONFIRM</button>
                </div>

            </div>
        </div>
    `;

    document.body.appendChild(modalWrapper);

    const rangeInput = modalWrapper.querySelector('#modalRangeInput');
    const countDisplay = modalWrapper.querySelector('#modalUnitCount');
    const totalCostDisplay = modalWrapper.querySelector('#modalTotalCost');
    const totalWeightDisplay = modalWrapper.querySelector('#modalTotalWeight');

    rangeInput.addEventListener('input', (e) => {
        const count = parseInt(e.target.value);
        
        countDisplay.textContent = count;
        
        totalCostDisplay.textContent = `$${(count * uCost).toLocaleString()}`;
        totalWeightDisplay.textContent = (count * uWeight);
    });

    modalWrapper.querySelector('.close-modal').onclick = () => modalWrapper.remove();
    modalWrapper.querySelector('.cancel').onclick = () => modalWrapper.remove();

    modalWrapper.querySelector('.confirm').onclick = () => {
        const finalCount = parseInt(rangeInput.value);
        this.addUnitToSlot(unitType, slot, finalCount);
        modalWrapper.remove();
    };
}

renderSlotContent(slot) {
    const slotContent = document.getElementById(`slot${slot}Content`);
    if (!slotContent) return;
    slotContent.innerHTML = '';

    if (!this.platoonData[slot] || this.platoonData[slot].units.length === 0) {
        return; 
    }

    this.platoonData[slot].units.forEach(unit => {
        const unitData = this.unitData[unit.type];
        const unitElement = document.createElement('div');
        unitElement.className = 'platoon-unit'; // CSS class we styled earlier
        
        const bgImage = unitData.thumbnail ? `images/units/${unitData.thumbnail}` : 'images/units/default.png';
        unitElement.style.backgroundImage = `url('${bgImage}')`;

        unitElement.innerHTML = `
            <div class="unit-count">${unit.count}</div>
            <div class="remove-overlay remove-unit" data-unit-type="${unit.type}">
                <i class="fas fa-times"></i>
            </div>
        `;
        
        slotContent.appendChild(unitElement);
    });
}

    async savePlatoons() {
        if (!this.platoonData || Object.keys(this.platoonData).length === 0) {
            this.showNotification('No platoons configured', 'error');
            return;
        }

        try {
            const response = await this.fetchNUI('savePlatoons', { platoons: this.platoonData });
            if (response.success) {
                this.showNotification('Platoons saved successfully', 'success');
            }
        } catch (error) {
            console.error('Save platoons error:', error);
            this.showNotification('Failed to save platoons', 'error');
        }
    }

updateMapPreview(mapKey) {
        const map = this.mapData[mapKey];
        if (!map) return;

        const previewMapName = document.getElementById('previewMapName');
        const mapSize = document.querySelector('.map-size');
        const objectiveCount = document.getElementById('objectiveCount');
        const timeLimit = document.getElementById('timeLimit');
        
        const mapDesc = document.getElementById('mapDescription');

        if (previewMapName) previewMapName.textContent = map.name.toUpperCase();

        if (mapSize) {
            const size = (map.range * 2).toFixed(0);
            mapSize.textContent = `COMBAT ZONE: ${size}M`;
        }

        if (objectiveCount) {
            const count = map.objectives ? map.objectives.length : 0;
            objectiveCount.textContent = count;
        }

        if (timeLimit) timeLimit.textContent = "15:00";

        if (mapDesc) {
            mapDesc.textContent = map.description || "No tactical data available for this sector.";
        }

        const mapPreview = document.getElementById('mapPreview');
        if (mapPreview) {
            const imageUrl = map.thumbnail ? `images/maps/${map.thumbnail}` : 'images/maps/default.jpg';
            mapPreview.style.background = `
                linear-gradient(to bottom, transparent 50%, rgba(0, 0, 0, 0.9)),
                url('${imageUrl}')
            `;
            mapPreview.style.backgroundSize = 'cover';
            mapPreview.style.backgroundPosition = 'center';
        }
    }
       
    async spawnPlatoon(slot) {
        if (!this.gameState.isInMatch) {
            this.showNotification('Not in a match', 'error');
            return;
        }

        if (!this.platoonData[slot] || this.platoonData[slot].units.length === 0) {
            this.showNotification('No platoon configured for this slot', 'error');
            return;
        }

        const slotElement = document.querySelector(`.quickbar-slot[data-slot="${slot}"]`);
        const cooldownElement = document.getElementById(`cooldown${slot}`);

        if (slotElement && slotElement.classList.contains('disabled')) {
            return;
        }

        const platoonCost = this.platoonData[slot].totalCost;
        if (this.gameState.commandPoints < platoonCost) {
            this.showNotification(`Not enough command points (Need: $${platoonCost})`, 'error');
            return;
        }

        if (slotElement) slotElement.classList.add('disabled');

        let cooldown = 30;
        if (cooldownElement) {
            cooldownElement.textContent = cooldown;
            cooldownElement.style.display = 'flex';

            const cooldownInterval = setInterval(() => {
                cooldown--;
                cooldownElement.textContent = cooldown;

                if (cooldown <= 0) {
                    clearInterval(cooldownInterval);
                    cooldownElement.style.display = 'none';
                    if (slotElement) slotElement.classList.remove('disabled');
                }
            }, 1000);
        }

        this.gameState.commandPoints -= platoonCost;
        this.updateResourceDisplay({
            commandPoints: this.gameState.commandPoints,
            incomeRate: 150
        });

        try {
            await this.fetchNUI('spawnPlatoon', {
                platoonIndex: parseInt(slot),
                x: window.innerWidth / 2,
                y: window.innerHeight / 2
            });
        } catch (error) {
            console.error('Spawn platoon error:', error);
        }
    }

saveSettings() {
    const musicSlider = document.getElementById('musicVolume');
    const sfxSlider = document.getElementById('sfxVolume'); // 
    const music = document.getElementById('bgMusic');

    if (music && musicSlider) {
        music.volume = musicSlider.value / 100;
    }

    if (sfxSlider) {
        const sfxVol = sfxSlider.value / 100;
        Object.values(this.sounds).forEach(s => {
            s.volume = sfxVol;
        });
    }

    this.showNotification('Settings applied', 'success');
    this.closeModal('settingsModal');
    
    this.playSFX('menuClick');
}

}

document.addEventListener('DOMContentLoaded', () => {
    window.tacticalRTS = new TacticalRTS();
});

if (typeof GetParentResourceName === 'undefined') {
    window.GetParentResourceName = () => 'enyo-rts';
}