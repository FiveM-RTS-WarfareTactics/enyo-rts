// Catch FiveM's native loading events immediately
// =========================================================
//  1. NATIVE LOADING SCREEN HANDLER (Runs Immediately)
// =========================================================
window.addEventListener('message', (e) => {
    if (e.data.eventName === 'loadProgress') {
        
        // FORCE THE SCREEN VISIBLE DURING CONNECTION
        document.body.style.display = 'block';
        const loadScreen = document.getElementById('loadingScreen');
        if (loadScreen) {
            loadScreen.classList.remove('hidden');
            loadScreen.style.display = 'flex';
        }

        const bar = document.getElementById('loadingBarFill');
        const status = document.getElementById('loadingStatusText');
        
        // Convert 0.0-1.0 to Percentage
        const pct = Math.floor(e.data.loadFraction * 100);

        // Update Visuals
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
// Tactical RTS NUI Application
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
    // Navigational Sounds
    hover: new Audio('sounds/hover-1.mp3'),
    menuClick: new Audio('sounds/click-2.mp3'), // Clean "Tap"
    menuOpen: new Audio('sounds/menu-open.mp3'),  // Pneumatic/Heavy

    // Tactical/Action Sounds
    dispatch: new Audio('sounds/start.mp3'),  // Tech/Radio "Bleep"
    alert: new Audio('sounds/error.mp3'),     // High-priority alert

    // Screen Entry Ambience
  //  mainMenuEntry: new Audio('sounds/hover-1.mp3'),
    //lobbyEntry: new Audio('sounds/game-ui-entry.mp3'),
   // gameEntry: new Audio('sounds/game-ui-entry.mp3')
    countdownBip: new Audio('sounds/countdown.mp3'), // Short sharp bip
    deployUnit: new Audio('sounds/click-1.mp3'), // Tech/Heavy Spawn sound
};

// Set Volume Levels
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
        this.init(true);
        this.initEditorInputBridge();
    }
initEditorInputBridge() {
    // 1. Capture Mouse Clicks (Left = 0, Right = 2)
    window.addEventListener('mousedown', (e) => {
        if (this.gameState.isInMatch) return; // Don't interfere with game
        const action = (e.button === 0) ? 'CLICK_LEFT' : (e.button === 2 ? 'CLICK_RIGHT' : null);
        if (action) this.fetchNUI('editorAction', { action: action });
    });

    // 2. Capture Mouse Wheel (Zoom)
    window.addEventListener('wheel', (e) => {
        if (this.gameState.isInMatch) return;
        const action = e.deltaY < 0 ? 'ZOOM_IN' : 'ZOOM_OUT';
        this.fetchNUI('editorAction', { action: action });
    }, { passive: true });

    // 3. Capture All Keys (Rotation, Pickup, Clone, Shift)
    window.addEventListener('keydown', (e) => {
        if (this.gameState.isInMatch) return;
        
        const keyMap = {
            'e': 'PICKUP', 'E': 'PICKUP',
            'c': 'CLONE', 'C': 'CLONE',
            'r': 'RESET_HEIGHT', 'R': 'RESET_HEIGHT',
            'Delete': 'DELETE','Del': 'DELETE','Suppr': 'DELETE', 'Backspace': 'EXIT',
            'ArrowLeft': 'ROTATE_LEFT', 'ArrowRight': 'ROTATE_RIGHT',
            'Shift': 'SHIFT_DOWN'
        };

        if (keyMap[e.key]) {
            if (e.key === 'Backspace') e.preventDefault();
            this.fetchNUI('editorAction', { action: keyMap[e.key] });
        }
    });

    window.addEventListener('keyup', (e) => {
        if (e.key === 'Shift') {
            this.fetchNUI('editorAction', { action: 'SHIFT_UP' });
        }
    });
}
        // PASTE THIS INSIDE YOUR CLASS TacticalRTS
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
        
        // --- 1. DETERMINE TYPE ---
        // Victory objectives or specific high-value targets
        const isPrimary = (obj.type === 'victory' || obj.name === "Safe House" || obj.name === "City Hall");

        // --- 2. UPDATE TOP HUD (Global Status Bar) ---
        // We only show the primary objective status in the top HUD to keep it clean
        if (isPrimary) {
            const mainBar = document.getElementById('objectiveProgress');
            const mainText = document.getElementById('objectiveStatus');

            if (mainBar && mainText) {
                let statusText = "NEUTRAL";
                let barColor = "#bdc3c7";
                let textColor = "#bdc3c7";

                if (obj.owner === 0) {
                    // Neutral or Contested
                    if (obj.progress <= 0 || obj.capper === 0) {
                        statusText = "NEUTRAL ZONE";
                    } else {
                        const rel = this.getRelation(obj.capper);
                        statusText = (rel === 'ally') ? "CAPTURING" : "HOSTILE CAPTURE";
                        barColor = this.getTeamColor(obj.capper);
                        textColor = barColor;
                    }
                } else {
                    // Owned
                    const rel = this.getRelation(obj.owner);
                    barColor = this.getTeamColor(obj.owner);
                    textColor = barColor;
                    statusText = (rel === 'ally') ? "CONTROLLED" : "HOSTILE CONTROL";
                    
                    // Flash Yellow if being lost
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

        // --- 3. FLOATING 3D MARKERS ---
        const elId = 'obj-' + obj.name.replace(/\s+/g, '-');
        let el = document.getElementById(elId);

        // Create Element if it doesn't exist
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

        // Apply Classes based on Importance (Handled in CSS)
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
          //  el.style.transform = `translate(${x}px, ${y}px)`;
            el.style.transform = `translate(${x}px, ${y}px) translate(-50%, -50%)`;
            
            // --- 4. COLOR & ICON LOGIC ---
            
            // A. Determine Who Owns It (For Color)
            let targetTeam = 0;
            if (obj.owner !== 0) targetTeam = obj.owner; // Owner takes priority
            else if (obj.capper !== 0) targetTeam = obj.capper; // Capper takes secondary priority

            const teamColor = this.getTeamColor(targetTeam); 
            
            // B. Determine Icon (Based on Type)
            let iconClass = 'fa-circle'; 

            if (isPrimary) {
                iconClass = 'fa-location-crosshairs'; // Primary always Crown
            } else {
                // Smart Resource Icons based on name text
                const n = obj.name.toLowerCase();
                if (n.includes('oil') || n.includes('fuel') || n.includes('gas')) iconClass = 'fa-oil-can';
                else if (n.includes('ammo') || n.includes('munitions') || n.includes('supply')) iconClass = 'fa-box-open';
                else if (n.includes('comms') || n.includes('radar') || n.includes('uplink')) iconClass = 'fa-satellite-dish';
                else if (n.includes('medic') || n.includes('hospital')) iconClass = 'fa-briefcase-medical';
                else if (n.includes('depot') || n.includes('silo')) iconClass = 'fa-money-bill-wheat';
                else iconClass = 'fa-cube'; // Generic Resource
            }

            // C. Apply Icon Class
            const iconI = el.querySelector('.obj-icon i');
            if (iconI && !iconI.classList.contains(iconClass)) {
                iconI.className = `fas ${iconClass}`;
            }

            // D. Apply Colors to DOM elements
            const iconContainer = el.querySelector('.obj-icon');
            const barFill = el.querySelector('.obj-bar-fill');

            // Icon Color: Owned = Team Color, Neutral = Grey/White
            if (iconContainer) {
                iconContainer.style.color = (targetTeam === 0) ? '#e0e0e0' : teamColor;
                // a glow equal to the team color for visibility
                iconContainer.style.textShadow = (targetTeam === 0) ? '0 1px 2px #000' : `0 0 15px ${teamColor}`;
            }

            // Bar Color: Fill matches team color
            if (barFill) {
                barFill.style.width = obj.progress + '%';
                barFill.style.backgroundColor = teamColor;
                
                // If it's totally neutral (0 progress), make the tiny bar grey
                if (targetTeam === 0 && obj.progress > 0) {
                     barFill.style.backgroundColor = '#bdc3c7';
                }
            }
        }
    });

    // Cleanup invisible markers
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

        // --- [UPDATED TEXT CONTENT LOGIC] ---
        const textEl = el.querySelector('.unit-health-text');
        if (textEl) {
            const minHealth = 100; // The value where it dies
            const trueMax = unit.max; // e.g., 800

            // 1. Calculate the actual usable pool (800 - 100 = 700)
            const effectiveRange = trueMax - minHealth;

            // 2. Calculate current usable health (Current - 100)
            const effectiveCurrent = Math.max(0, unit.cur - minHealth);

            // 3. Scale it so 700 usable points looks like 800 points
            // Formula: (CurrentUsable / MaxUsable) * DisplayMax
            let displayValue = 0;
            if (effectiveRange > 0) {
                displayValue = (effectiveCurrent / effectiveRange) * trueMax;
            }

            // Result: 100 HP -> "0/800", 800 HP -> "800/800"
            textEl.textContent = `${Math.floor(displayValue)}/${trueMax}`;
        }

        // --- [VISUAL BAR LOGIC] ---
        const hpFill = el.querySelector('.unit-health-fill');
        const flashFill = el.querySelector('.unit-damage-flash');
        
        // Calculate percentage (0% at 100hp, 100% at 800hp)
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
    //updateUnitPositions(units) {
    //    // Safety Check
    //    if (!this.overlayContainer) {
    //        this.overlayContainer = document.getElementById('game-input-layer');
    //        if (!this.overlayContainer) return;
    //    }
//
    //    const currentTimestamp = Date.now();
    //    // Use a fallback if window size is weird (prevents invisible boxes)
    //    const screenW = window.innerWidth || 1920;
    //    const screenH = window.innerHeight || 1080;
//
    //    units.forEach(unit => {
    //        //  Force ID to String for consistent matching
    //        const unitId = String(unit.id);
//
    //        let el = this.unitElements[unitId];
//
    //        // 1. Create Element (Only if it doesn't exist)
    //        if (!el) {
    //            el = document.createElement('div');
    //            el.className = 'unit-hitbox';
    //            el.dataset.id = unitId;
//
    //            // MOUSE LISTENERS
    //            el.onmousedown = (e) => {
    //                e.stopPropagation(); // Stop map click
//
    //                // Left Click = Select (If Friendly)
    //                if (e.button === 0) {
    //                    if (unit.team === this.gameState.team) {
    //                        this.fetchNUI('selectUnit', { unitId: parseInt(unitId) });
    //                    }
    //                }
    //                // Right Click = Attack (If Enemy)
    //                else if (e.button === 2) {
    //                    if (unit.team !== this.gameState.team) {
    //                        console.log("ATTACK ORDER ->", unitId);
    //                        this.fetchNUI('issueCommand', {
    //                            type: 'attack',
    //                            targetId: parseInt(unitId)
    //                        });
    //                        // Visual Flash
    //                        el.style.borderColor = "red";
    //                        setTimeout(() => el.style.borderColor = "transparent", 200);
    //                    }
    //                }
    //            };
//
    //            el.innerHTML = `
    //                <div class="unit-health-bar">
    //                    <div class="unit-health-text"></div> <div class="unit-damage-flash"></div>
    //                    <div class="unit-health-fill"></div>
    //                </div>
    //            `;
    //            this.overlayContainer.appendChild(el);
    //            this.unitElements[unitId] = el;
    //        }
//
    //        // 2. Update Data
    //        el.style.display = 'block';
    //        el.dataset.lastSeen = currentTimestamp;
//
    //        // 3. Update Position (Translate is faster than Top/Left)
    //        // Lua sends 0.0-1.0. We multiply by screen size.
    //        const x = (unit.x * screenW).toFixed(0);
    //        const y = (unit.y * screenH).toFixed(0);
    //        el.style.transform = `translate(${x}px, ${y}px)`;
//
    //        // [UPDATE TEXT CONTENT]
    //        const textEl = el.querySelector('.unit-health-text');
    //        if (textEl) {
    //            // Displays "1550/2100"
    //            textEl.textContent = `${Math.max(0, unit.cur)}/${unit.max}`;
    //        }
//
    //        // 4. Update Health Bars (Updated Logic)
    //        const hpFill = el.querySelector('.unit-health-fill');
    //        const flashFill = el.querySelector('.unit-damage-flash'); // Select the new bar
//
    //        if (hpFill) {
    //            hpFill.style.width = unit.health + '%';
//
    //            // Color Logic
    //            if (unit.team === this.gameState.team) {
    //                hpFill.classList.remove('enemy');
    //                hpFill.style.backgroundColor = '';
    //            } else {
    //                hpFill.classList.add('enemy');
    //                hpFill.style.backgroundColor = '';
    //            }
    //        }
//
    //        // Update Flash Bar width
    //        if (flashFill) {
    //            flashFill.style.width = unit.health + '%';
    //        }
//
    //        // 5. Selection State
    //        if (this.gameState.selectedUnits.includes(parseInt(unitId))) {
    //            el.classList.add('selected');
    //            el.style.borderColor = "#00ff00";
    //        } else {
    //            el.classList.remove('selected');
    //            el.style.borderColor = "transparent"; // Invisible unless selected
    //        }
    //    });
//
    //    // 3. Soft Cleanup (Prevents Flashing)
    //    // Only delete hitbox if unit is missing for > 2 seconds
    //    Object.keys(this.unitElements).forEach(key => {
    //        const el = this.unitElements[key];
    //        const lastSeen = parseInt(el.dataset.lastSeen || 0);
//
    //        if (lastSeen !== currentTimestamp) {
    //            if (currentTimestamp - lastSeen > 2000) {
    //                el.remove();
    //                delete this.unitElements[key];
    //            } else {
    //                el.style.display = 'none'; // Just hide it momentarily
    //            }
    //        }
    //    });
    //}
        // Inside app.js
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

        // CHANGED: Use <i class="${p.icon}"> instead of text
        // Note: p.icon comes from Config.Platoon (e.g., "fas fa-chess-knight")
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

        // Start cycling tips immediately
        if (this.tips && this.tips.length > 0) {
            const tipEl = document.getElementById('loadingTipText');
            if (tipEl) tipEl.textContent = this.tips[Math.floor(Math.random() * this.tips.length)];
            setInterval(() => {
                if (tipEl) tipEl.textContent = this.tips[Math.floor(Math.random() * this.tips.length)];
            }, 3000);
        }

        if (!isGameMode) {
            // [LOADING SCREEN PHASE]
            console.log("RTS: Running as Server Loading Screen");
            // We do nothing else here, the event listener at the top handles it.
        } else {
            // [GAME PHASE]
            console.log("RTS: Game Engine Ready. Handshaking...");
            
            // Keep the loading screen visible visually while we wait for Lua
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
            // [[ ADD IT RIGHT HERE ]]
            this.startLiveStatsPoller();

            if (first) {
                // Keep asking Lua to open the menu until it responds
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

        // 1. GLOBAL MOUSE DOWN
        window.addEventListener('mousedown', (e) => {
            // Only run this logic if we are in a match
            if (!this.gameState.isInMatch) return;

            // IGNORE clicks on Buttons/UI (Top bar, cards, etc)
            // If the thing we clicked has the class 'interactive', ignore it.
            if (e.target.closest('.quickbar-slot') ||
                e.target.closest('.top-bar') ||
                e.target.closest('.modal') ||
                e.target.closest('button')) {
                return;
            }

         //   console.log("Input Detected:", e.button, e.clientX, e.clientY);

            if (e.button === 0) { // Left Click
                isDragging = true;
                startX = e.clientX;
                startY = e.clientY;

                // Prepare Selection Box
                if (selectRect) {
                    selectRect.style.left = startX + 'px';
                    selectRect.style.top = startY + 'px';
                    selectRect.style.width = '0px';
                    selectRect.style.height = '0px';
                    selectRect.classList.remove('hidden');
                }

            } else if (e.button === 2) {
                //  Normalize coordinates (0.0 to 1.0)
                const normX = e.clientX / window.innerWidth;
                const normY = e.clientY / window.innerHeight;

             //   console.log("MOVE ORDER (Normalized):", normX.toFixed(3), normY.toFixed(3));

                this.fetchNUI('issueCommand', {
                    type: 'move',
                    x: normX, // Sending 0.0 - 1.0
                    y: normY
                });
            }
        });

        // 2. GLOBAL MOUSE MOVE
        window.addEventListener('mousemove', (e) => {
            if (!this.gameState.isInMatch) return;

            // Handle Dragging Visuals
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

        // 3. GLOBAL MOUSE UP
        window.addEventListener('mouseup', (e) => {
            if (!this.gameState.isInMatch) return;

            if (e.button === 0 && isDragging) { // Left Release
                isDragging = false;
                if (selectRect) selectRect.classList.add('hidden');

                const endX = e.clientX;
                const endY = e.clientY;
                const dist = Math.sqrt(Math.pow(endX - startX, 2) + Math.pow(endY - startY, 2));

                // Get Screen Dimensions
                const w = window.innerWidth;
                const h = window.innerHeight;

                if (dist > 15) {
                    // Box Select: Send Normalized Coordinates (0.0 to 1.0)
                    this.fetchNUI('selectUnits', {
                        x1: startX / w,
                        y1: startY / h,
                        x2: endX / w,
                        y2: endY / h
                    });
                } else {
                    // Single Select
                    this.fetchNUI('selectUnit', {
                        x: endX,
                        y: endY
                    });
                }
            }
        });
    }
    startMouseTracker() {
     
        // Capture Mouse Wheel for Zooming
        window.addEventListener('wheel', (e) => {
            if (!this.gameState.isInMatch) return;

            // e.deltaY < 0 means Scrolling UP (Zoom In)
            // e.deltaY > 0 means Scrolling DOWN (Zoom Out)
            const direction = e.deltaY < 0 ? 'in' : 'out';

            this.fetchNUI('cameraZoom', { direction: direction });
        });
        // In bindGlobalEvents() -> mousemove listener
        // In bindGlobalEvents()
        document.addEventListener('mousemove', (e) => {
            const cursor = document.getElementById('gameCursor');
            if (cursor) {
                // Direct pixel assignment is resolution-safe
                cursor.style.left = e.clientX + 'px';
                cursor.style.top = e.clientY + 'px';
                // Ensure no transform is applied via JS
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
        // 1. Hover (Universal)
    document.addEventListener('mouseover', (e) => {
    // .matches() checks only the element itself, not its parents
    if (e.target.matches('.btn, .unit-card, .quickbar-slot, .platoon-unit, .deployed-item, .history-item')) {
        this.playSFX('hover');
    }
});
// --- NEW: LIVE VOLUME CONTROL ---
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
        
        // Loop through all loaded sounds and update their volume
        Object.values(this.sounds).forEach(s => {
            s.volume = volume;
        });
    });

    // Optional: Play a sound when they let go of the slider so they can test the volume
    sfxSlider.addEventListener('change', () => {
        this.playSFX('menuClick'); 
    });
}
    // 2. Specialized Clicks (Delegation)
    document.addEventListener('click', (e) => {
        const target = e.target;

        

        if (target.closest('.quickbar-slot')) {
            const slotEl = target.closest('.quickbar-slot');
            // Only play if not on cooldown and has enough points
            if (!slotEl.classList.contains('disabled')) {
                this.playSFX('deployUnit'); 
            } else {
                this.playSFX('alert'); // Subtle "error" chirp if on cooldown
            }
            return;
        }

        // B. MENU NAVIGATION (Main buttons, tabs, etc.)
        if (target.closest('.btn, .category-btn, .carousel-arrow, .close-modal')) {
            const isHeavyMenu = target.closest('#settingsBtn, #helpBtn, #midGameSettings');
            
            if (isHeavyMenu) {
                this.playSFX('menuOpen'); // Heavier sound for settings/help
            } else {
                this.playSFX('menuClick'); // Standard UI "tick" for navigation
            }
        }
        
        // C. LOBBY ACTIONS
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
            // 2. Global Click Listener (Delegation)
            document.addEventListener('click', (e) => {
                // at the top of the click listener
                if (e.target.closest('button') || e.target.closest('.btn') || e.target.closest('.platoon-slot')) {
                    // this.fetchNUI('playSound', { name: 'CLICK' }); 
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
                // This detects clicks on buttons like "INFANTRY", "VEHICLES", etc.
                if (e.target.closest('.category-btn')) {
                    const btn = e.target.closest('.category-btn');
                    const category = btn.dataset.category; // Gets 'infantry', 'vehicles', or 'all'

                    // Debug log to confirm click works
                 //   console.log('Filter Clicked:', category);

                    this.filterUnits(category);
                    this.updateCategoryButtons(btn);
                }
                const squadItem = e.target.closest('.deployed-item');
                if (squadItem) {
                    const uuid = squadItem.dataset.uuid;
                  //  console.log("Clicked Squad:", uuid); // Debug to F8 console

                    // Visual Feedback
                    squadItem.classList.add('pulse-select');
                    setTimeout(() => squadItem.classList.remove('pulse-select'), 200);

                    // Send to Lua (Ensure uuid is parsed as int if your Lua expects int)
                    this.fetchNUI('selectPlatoonGroup', { uuid: parseInt(uuid) });
                }
                // --- OTHER BUTTONS ---
                // Main Menu
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

                // Lobby Controls
                if (e.target.closest('#leaveLobby')) this.leaveLobby();
                if (e.target.closest('#copyCode')) this.copyLobbyCode();
                if (e.target.closest('#readyToggle')) this.toggleReady();
                if (e.target.closest('#savePlatoons')) this.savePlatoons();
                if (e.target.closest('#clearAll')) this.clearAllPlatoons();

                // [NEW] Bot Controls
                // [NEW] Single Bot Toggle Control
                if (e.target.closest('#toggleBotBtn')) {
                    const btn = e.target.closest('#toggleBotBtn');
                    if (btn.dataset.action === 'add') {
                        this.addBotToLobby();
                    } else {
                        this.kickBotFromLobby();
                    }
                }

                // Remove Unit (Red X)
                if (e.target.closest('.remove-unit')) {
                    const btn = e.target.closest('.remove-unit');
                    const slot = btn.closest('.platoon-slot').dataset.slot;
                    const type = btn.dataset.unitType;
                    this.removeUnitFromSlot(type, slot);
                }

                // Quickbar (Game UI)
                if (e.target.closest('.quickbar-slot')) {
                    const slot = e.target.closest('.quickbar-slot');
                    if (!slot.classList.contains('disabled')) this.spawnPlatoon(slot.dataset.slot);
                }

                // Close Modals
                if (e.target.closest('#closeSettings')) this.closeModal('settingsModal');
                if (e.target.closest('#closeHelp')) this.closeModal('helpModal');
                if (e.target.closest('#saveSettings')) this.saveSettings();
            });

            // 3. Key Press Listener
            document.addEventListener('keydown', (e) => {
                if (e.key === 'Enter') {
                    const input = document.getElementById('lobbyCodeInput');
                    if (document.activeElement === input) this.joinLobby();
                }

                if (e.key === 'Escape') {
                    if (this.gameState.currentScreen === 'gameUI') this.hideCommandPanel();
                    else if (this.gameState.currentScreen === 'lobbyScreen') this.leaveLobby();
                    // 1. If Settings Modal is open -> Close it
                    const settingsModal = document.getElementById('settingsModal');
                    if (settingsModal && !settingsModal.classList.contains('hidden')) {
                        this.closeModal('settingsModal');
                        return; // Stop here
                    }

                    // 2. If Help Modal is open -> Close it
                    const helpModal = document.getElementById('helpModal');
                    if (helpModal && !helpModal.classList.contains('hidden')) {
                        this.closeModal('helpModal');
                        return; // Stop here
                    }

                    // 3. Normal Game Logic
                    if (this.gameState.currentScreen === 'gameUI') {
                        this.hideCommandPanel();
                    } else if (this.gameState.currentScreen === 'lobbyScreen') {
                        this.leaveLobby();
                    }
                }
            });

            // 4. Initialize Drag Events
            this.initManualDragSystem();
        }
        //  Robust Drag & Drop System using Event Delegation
    initDragAndDropSystem() {
        // 1. Handle Unit Dragging (Source)
        const unitsList = document.getElementById('unitsList');
        if (unitsList) {
            document.addEventListener('dragstart', (e) => {
                const card = e.target.closest('.unit-card');
                if (card) {
                    this.draggedUnit = card.dataset.unitType;
                    e.dataTransfer.setData('text/plain', this.draggedUnit);
                    e.dataTransfer.effectAllowed = 'copyMove';

                    // 1. Create a visible ghost image manually
                    var dragIcon = card.cloneNode(true);
                    dragIcon.classList.remove('dragging'); // Ensure ghost is visible
                    dragIcon.style.position = "absolute";
                    dragIcon.style.top = "-1000px";
                    dragIcon.style.opacity = "1";
                    dragIcon.style.width = card.offsetWidth + "px"; // Keep size
                    document.body.appendChild(dragIcon);
                    e.dataTransfer.setDragImage(dragIcon, 0, 0);

                    // 2. Add class to original card (delayed so ghost generates first)
                    setTimeout(() => {
                        card.classList.add('dragging');
                        document.body.removeChild(dragIcon); // Clean up ghost source
                    }, 0);

                  //  console.log('DRAG START:', this.draggedUnit);
                }
            });

            unitsList.addEventListener('dragend', (e) => {
                const card = e.target.closest('.unit-card');
                if (card) card.classList.remove('dragging');

                this.draggedUnit = null;

                // Clean up visual cues on slots
                document.querySelectorAll('.platoon-slot').forEach(slot => {
                    slot.classList.remove('drag-over');
                });
            });
        }

        // 2. Handle Drop Zones (Targets)
        // We attach listeners to the CONTAINER of the slots to ensure they always work
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
                  //  console.log('Dropped', this.draggedUnit, 'into slot', slotNum);
                    this.showUnitSelectionModal(this.draggedUnit, slotNum);
                }
            });
        }
    }
    startLoadingAnimation(targetScreen = 'mainMenu', incomingData = {}) {
        // --- 1. NEW VISUAL SELECTORS (Elegant Look) ---
        const screen = document.getElementById('loadingScreen');
        const bar = document.getElementById('loadingBarFill'); // New ID
        const statusText = document.getElementById('loadingStatusText'); // New ID
        const tipText = document.getElementById('loadingTipText'); // New Feature

        // Show Screen
        if (screen) screen.classList.remove('hidden');
        if (bar) bar.style.width = '0%';
        
        // Random Tip (Keep this, it's nice)
        if (tipText && this.tips && this.tips.length > 0) {
            tipText.textContent = this.tips[Math.floor(Math.random() * this.tips.length)];
        }

        // --- 2. OLD LOGIC (Progress Loop) ---
        if (this.loadingInterval) clearInterval(this.loadingInterval);

        let progress = 0;
        this.loadingInterval = setInterval(() => {
            // Random increments (From your old code)
            let add = Math.random() * 7;
            if (progress < 30) add = Math.random() * 10;
            else if (progress < 60) add = Math.random() * 5;
            else if (progress < 90) add = Math.random() * 15;
            else add = Math.random() * 10;
            
            progress += add;
            if (progress > 100) progress = 100;

            // Visual Update
            if (bar) bar.style.width = progress + '%';

            // Text Updates (Your requested text)
            if (statusText) {
                if (progress < 30) statusText.textContent = 'LOADING CORE SYSTEMS...';
                else if (progress < 60) statusText.textContent = 'INITIALIZING BATTLEFIELD...';
                else if (progress < 90) statusText.textContent = 'CONFIGURING UNITS...';
                else statusText.textContent = 'READY FOR DEPLOYMENT';
            }

            // --- 3. CRITICAL FINISH LOGIC (From Old Code) ---
            if (progress >= 100) {
                clearInterval(this.loadingInterval);
                
                setTimeout(() => {
                    // Hide Screen
                    if (screen) screen.classList.add('hidden');

                    // A. Pass Data to ShowScreen (Restores Stats/Money)
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
                // Main Menu
                if (e.target.closest('#quickMatch')) this.quickMatch();
                if (e.target.closest('#createLobby')) this.createLobby();
                if (e.target.closest('#joinLobby')) this.joinLobby();
                if (e.target.closest('#viewStats')) this.viewStats();
                if (e.target.closest('#settingsBtn')) this.openSettings();
                if (e.target.closest('#helpBtn')) this.openHelp();
                if (e.target.closest('#exitBtn')) this.exitGame();

                if (e.target.closest('#mapNext')) this.nextMap();
                if (e.target.closest('#mapPrev')) this.prevMap();

                // Lobby Screen
                if (e.target.closest('#leaveLobby')) this.leaveLobby();
                if (e.target.closest('#copyCode')) this.copyLobbyCode();
                if (e.target.closest('#readyToggle')) this.toggleReady();
                if (e.target.closest('#savePlatoons')) this.savePlatoons();
                if (e.target.closest('#clearAll')) this.clearAllPlatoons();

                // Category buttons
                if (e.target.closest('.category-btn')) {
                    const btn = e.target.closest('.category-btn');
                    const category = btn.dataset.category;
                    this.filterUnits(category);
                    this.updateCategoryButtons(btn);
                }

                // Remove unit buttons
                if (e.target.closest('.remove-unit')) {
                    const removeBtn = e.target.closest('.remove-unit');
                    const unitType = removeBtn.dataset.unitType;
                    const slot = removeBtn.closest('.platoon-slot').dataset.slot;
                    this.removeUnitFromSlot(unitType, slot);
                }

                // Game UI
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

                // Minimap controls
                if (e.target.closest('#zoomIn')) this.zoomMinimap(1.2);
                if (e.target.closest('#zoomOut')) this.zoomMinimap(0.8);

                // Result Screen
                if (e.target.closest('#rematchBtn')) this.rematch();
                if (e.target.closest('#returnToMenuBtn')) this.returnToMenu();

                // Modal controls
                if (e.target.closest('#closeSettings')) this.closeModal('settingsModal');
                if (e.target.closest('#closeHelp')) this.closeModal('helpModal');
                if (e.target.closest('#saveSettings')) this.saveSettings();
            });

            // Map selection
            const mapSelect = document.getElementById('mapSelect');
            if (mapSelect) {
                mapSelect.addEventListener('change', (e) => {
                    this.currentMap = e.target.value;
                    this.updateMapPreview(e.target.value);
                });
            }

            // Lobby code input
            const lobbyCodeInput = document.getElementById('lobbyCodeInput');
            if (lobbyCodeInput) {
                lobbyCodeInput.addEventListener('keypress', (e) => {
                    if (e.key === 'Enter') {
                        this.joinLobby();
                    }
                });
            }

            // Unit drag and drop
            this.initDragAndDrop();



            // Handle escape key
            document.addEventListener('keydown', (e) => {
                if (e.key === 'Escape') {
                    if (this.gameState.currentScreen === 'gameUI') {
                        this.hideCommandPanel();
                    } else if (this.gameState.currentScreen === 'lobbyScreen') {
                        this.leaveLobby();
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

        // A. MOUSE DOWN (Start Drag)
        document.addEventListener('mousedown', (e) => {
            if (e.button !== 0) return; // Only Left Click

            const card = e.target.closest('.unit-card');
            if (!card || card.classList.contains('locked')) return;

            e.preventDefault();

            // 1. Get Geometry
            const rect = card.getBoundingClientRect();
            dragOffsetX = e.clientX - rect.left;
            dragOffsetY = e.clientY - rect.top;

            // 2. Save Data
            dragData = card.dataset.unitType;

            // 3. Create Visual Clone
            dragClone = card.cloneNode(true);
            dragClone.className = 'unit-card dragging-clone';

            dragClone.style.width = `${rect.width}px`;
            dragClone.style.height = `${rect.height}px`;

            document.body.appendChild(dragClone);

            // 4. Initial Position (using transform for performance)
            const x = e.clientX - dragOffsetX;
            const y = e.clientY - dragOffsetY;
            dragClone.style.transform = `translate3d(${x}px, ${y}px, 0)`;

            // 5. Mark Source
            card.classList.add('dragging-source');

          //  console.log('MANUAL DRAG START:', dragData);
        });

        // B. MOUSE MOVE (Follow Mouse)
        document.addEventListener('mousemove', (e) => {
            if (!dragClone) return;

            // OPTIMIZED: Use translate3d for GPU acceleration (No Lag)
            const x = e.clientX - dragOffsetX;
            const y = e.clientY - dragOffsetY;
            dragClone.style.transform = `translate3d(${x}px, ${y}px, 0)`;
        });

        // C. MOUSE UP (Drop)
        document.addEventListener('mouseup', (e) => {
            if (!dragClone) return;

            // 1. Cleanup Visuals
            dragClone.remove();
            dragClone = null;
            document.querySelectorAll('.dragging-source').forEach(el => el.classList.remove('dragging-source'));

            // 2. Check Drop Target
            // Temporarily hide cursor/clone logic to find what's underneath
            const elementUnderMouse = document.elementFromPoint(e.clientX, e.clientY);
            const slot = elementUnderMouse ? elementUnderMouse.closest('.platoon-slot') : null;

            if (slot && dragData) {
             //   console.log('MANUAL DROP SUCCESS:', dragData, 'INTO', slot.dataset.slot);
                this.showUnitSelectionModal(dragData, slot.dataset.slot);
            }

            dragData = null;
        });
    }
    handleMessage(event) {
        const data = event.data;

        if (!data || !data.action) return;

        // console.log('RTS NUI Message:', data.action, data);

        switch (data.action) {
            case 'abortCountdown':
                this.abortCountdown();
                break;
            case 'updatePopulation':
                this.updatePopulationDisplay(data);
                break;
            case 'adminForceStart':
                this.savePlatoons(); // Force the save
                
                // Wait 500ms to ensure the server finishes processing the save, then start!
                setTimeout(() => {
                    this.fetchNUI('adminConfirmForceStart', {});
                }, 500); 
                break;
            case 'showCentralMenu':
                if (data.serverStats) this.updateServerInfo(data.serverStats);
                if (data.serverStats && data.serverStats.myStats) this.updateStats(data.serverStats.myStats);
            
                this.showScreen('mainMenu');
            
                // FADE OUT LOADING SCREEN
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
                
                //  Update the Code Display immediately when event arrives
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
              //  console.log("RTS: Received Config Data", data); // Check F8 Console for this!

                // 1. Save Data
                this.unitConfig = data.units;
                this.unitData = data.units;
                this.categories = data.categories;
                this.mapData = data.maps; // <--- SAVE MAP DATA
                this.keyConfig = data.keys; // Save keys to class

                // 2. Render
                this.renderCategoryButtons();
                this.renderUnitList('all');
                this.renderMapList();
                break;
            case 'toggleCinematic':
    // These IDs must match your HTML container IDs
    const uiMain = document.getElementById('gameUI'); 
    const selectionPanel = document.getElementById('activeSquadsPanel');
    const inputLayer = document.getElementById('game-input-layer');
    const notificationBox = document.getElementById('notificationContainer');
    const crosshair = document.getElementById('gameCursor');

    if (data.state) {
        // HIDE ALL RTS HUD ELEMENTS
        if (uiMain) uiMain.style.visibility = 'hidden';
        if (selectionPanel) selectionPanel.style.visibility = 'hidden';
        if (inputLayer) inputLayer.style.display = 'none';
        if (notificationBox) notificationBox.style.display = 'none';
        if (crosshair) crosshair.style.display = 'none';
        
        // Ensure background is fully transparent for recording
        document.body.style.background = 'none';
    } else {
        // RESTORE ALL RTS HUD ELEMENTS
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
                document.body.style.display = 'none';
                break;
case 'unhideUI':
            document.body.style.display = ''; // Restores default CSS visibility
            break;
            case 'lobbyCreated':
                this.handleLobbyCreated(data);
                break;

            case 'lobbyJoined':
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
                this.startMatch(data);
                break;

            case 'unitSpawned':
              //  this.showNotification(`Platoon deployed`, 'success');
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
                this.showScreen('mainMenu');

                // [[ FIX: Apply the stats we just received ]] --
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
        }
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
            // --- START QUEUE ---
            try {
                const res = await this.fetchNUI('joinQueue');
                if (res.success) {
                    this.isQueued = true;

                    // Visuals: Change to Cancel
                    btn.classList.remove('btn-primary');
                    btn.classList.add('btn-danger');
                    btnText.textContent = "CANCEL SEARCH";
                    btnIcon.className = "fas fa-times";

                    // Start Timer
                    let seconds = 0;
                    if (estTime) estTime.textContent = "SEARCHING: 00:00";

                    this.queueTimerInterval = setInterval(() => {
                        seconds++;
                        const m = Math.floor(seconds / 60).toString().padStart(2, '0');
                        const s = (seconds % 60).toString().padStart(2, '0');
                        if (estTime) estTime.textContent = `SEARCHING: ${m}:${s}`;
                    }, 1000);

                    this.showNotification('Joined matchmaking queue', 'info');

                    // --- [NEW] SMART AI PROMPT TIMER ---
                    // Wait 5s if alone, 30s if others are on the server
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
            // --- CANCEL QUEUE ---
            try {
                await this.fetchNUI('leaveQueue');
                this.resetQueueUI();
                this.showNotification('Matchmaking cancelled', 'warning');
                
                // --- [NEW] CLEAR AI MODAL ---
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
            // NOTE: If called from rematch(), 'code' comes from arguments, handled below
            const payload = { code: code || this.nextLobbyCode };

            const response = await this.fetchNUI('joinLobby', payload);

            if (response.success) {
                this.gameState.lobbyCode = payload.code;
                this.gameState.isHost = false;
                if (lobbyCodeInput) lobbyCodeInput.value = '';

                // --- APPLY FIX ---
                // Manually trigger the join handler to ensure state is reset
                this.handleLobbyJoined(response);
                // -----------------

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
  //  console.log("[RTS] Copy Button Clicked"); // Debug Log

    const display = document.getElementById('lobbyCodeDisplay');
    const btn = document.getElementById('copyCode');
    
    // Auto-find the parent box 
    const container = btn ? btn.closest('.lobby-code-box') : null;

    if (!display || !container) {
        console.error("[RTS ERROR] Could not find display or container box");
        return;
    }

    const originalCode = display.textContent;
    const icon = btn.querySelector('i');

    // Trigger Visual Effect
    const triggerEffect = () => {
        // 1. Swap Text to "COPIED"
        display.textContent = "COPIED";
        
        // 2. Change Icon to Checkmark
        if (icon) {
            icon.className = "fas fa-check-circle";
        }

        // 3. Apply the Green Flash Class
        container.classList.add('code-copied-state');
        
      

        // 5. Reset after 1.5 seconds
        setTimeout(() => {
            display.textContent = originalCode;
            container.classList.remove('code-copied-state');
            if (icon) {
                icon.className = "fas fa-copy";
            }
        }, 300);
    };

    // Execute Copy
    if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(originalCode)
            .then(() => {
              //  console.log("[RTS] Clipboard API Success");
                triggerEffect();
            })
            .catch(err => {
              //  console.warn("[RTS] Clipboard API Failed, using fallback", err);
                this.fallbackCopy(originalCode);
                triggerEffect(); // Visual feedback even on fallback
            });
    } else {
       // console.log("[RTS] Using Fallback Copy");
        this.fallbackCopy(originalCode);
        triggerEffect();
    }
}

    async toggleReady() {
        // FIX: Auto-save platoons BEFORE becoming ready
        // If we are currently NOT ready, and we are about to click ready...
        if (!this.gameState.playerReady) {
          //  console.log("Auto-saving platoons before readying up...");
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
    // Returns 'ally', 'enemy', or 'neutral'
getRelation(teamId) {
    if (teamId === 0) return 'neutral';
    if (teamId === this.gameState.team) return 'ally';
    return 'enemy';
}

// Returns the correct color based on relation
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

    // 1. Initial State
    countdownContainer.style.display = 'block';
    countdownTimer.textContent = duration;
    let timeLeft = duration;

    // 2. Play the first bip immediately (e.g., for number 5)
    this.playSFX('countdownBip');

    // 3. Clear any existing intervals to prevent "timer doubling"
    if (this.countdownInterval) {
        clearInterval(this.countdownInterval);
    }

    // 4. The Main Loop
    this.countdownInterval = setInterval(() => {
        timeLeft--;
        
        if (timeLeft > 0) {
            // Update number and play bip (for 4, 3, 2, 1)
            countdownTimer.textContent = timeLeft;
            this.playSFX('countdownBip');
        } 
        else {
            // FINISH: Timer hit 0
            clearInterval(this.countdownInterval);
            countdownTimer.textContent = "0";
            
            

            // Hide container and proceed
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

    // "ALL" Button
    const allBtn = document.createElement('button');
    allBtn.className = 'category-btn active';
    allBtn.dataset.category = 'all';
    allBtn.innerHTML = `<i class="fas fa-th-large"></i> <span>ALL</span>`;
    container.appendChild(allBtn);

    // Sorted Categories
    let sortedCats = Object.entries(this.categories).map(([key, data]) => {
        return { id: key, name: data.name, icon: data.icon, sort: data.sort || 99 };
    });
    sortedCats.sort((a, b) => a.sort - b.sort);

    sortedCats.forEach(cat => {
        const btn = document.createElement('button');
        btn.className = 'category-btn';
        btn.dataset.category = cat.id;
        // Use FontAwesome Icon
        btn.innerHTML = `<i class="${cat.icon}"></i> <span>${cat.name}</span>`;
        container.appendChild(btn);
    });
}

renderUnitList(category = 'all') {
    const list = document.getElementById('unitsList');
    if (!list) return;
    list.innerHTML = '';

    // 1. Get Player Level
    const playerLevel = (this.myStats && this.myStats.levelData) ? this.myStats.levelData.level : 1;

    // 2. Find Newest Unit
    let highestUnlockFound = -1;
    let newestUnitKey = null;

    Object.entries(this.unitConfig).forEach(([key, unit]) => {
        const unlockLvl = unit.unlockLevel || 0;
        if (unlockLvl <= playerLevel && unlockLvl > highestUnlockFound) {
            highestUnlockFound = unlockLvl;
            newestUnitKey = key;
        }
    });

    // 3. Sort & Render
    const sortedUnits = Object.entries(this.unitConfig).sort(([, a], [, b]) => {
        return (a.unlockLevel || 0) - (b.unlockLevel || 0);
    });

    sortedUnits.forEach(([key, unit]) => {
        if (category === 'all' || unit.category === category) {
            
            const unlockLvl = unit.unlockLevel || 0;
            const isLocked = playerLevel < unlockLvl;
            const isNew = (key === newestUnitKey) && !isLocked;

            const card = document.createElement('div');
            
            //  Add 'has-badge' class ONLY if it is new
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

            // Only generate badge HTML if needed
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

    // Remove existing
    const existingModal = document.querySelector('.selection-modal');
    if (existingModal) existingModal.remove();

    // Data Preparation
    const uName = unit.name || 'UNKNOWN';
    const uCost = parseInt(unit.cost || 0);
    const uWeight = parseInt(unit.weight || 0);
    const uDesc = unit.description || 'System data unavailable.';
    
    // IMAGE LOGIC: Get the same image used for the card
    const bgImage = unit.thumbnail ? `images/units/${unit.thumbnail}` : 'images/units/default.png';

    // Create Modal
    const modalWrapper = document.createElement('div');
    modalWrapper.className = 'modal selection-modal';
    modalWrapper.style.display = 'flex'; 

    // Inject New HTML
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

    // --- LOGIC HANDLERS ---
    const rangeInput = modalWrapper.querySelector('#modalRangeInput');
    const countDisplay = modalWrapper.querySelector('#modalUnitCount');
    const totalCostDisplay = modalWrapper.querySelector('#modalTotalCost');
    const totalWeightDisplay = modalWrapper.querySelector('#modalTotalWeight');

    // 1. Live Update Logic
    rangeInput.addEventListener('input', (e) => {
        const count = parseInt(e.target.value);
        
        // Update Big Number
        countDisplay.textContent = count;
        
        // Update Calculations
        totalCostDisplay.textContent = `$${(count * uCost).toLocaleString()}`;
        totalWeightDisplay.textContent = (count * uWeight);
    });

    // 2. Buttons
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
        
        // 1. Set Background Image
        const bgImage = unitData.thumbnail ? `images/units/${unitData.thumbnail}` : 'images/units/default.png';
        unitElement.style.backgroundImage = `url('${bgImage}')`;

        // 2. HTML for Overlay & Badge
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

        // 1. Existing Elements
        const previewMapName = document.getElementById('previewMapName');
        const mapSize = document.querySelector('.map-size');
        const objectiveCount = document.getElementById('objectiveCount');
        const timeLimit = document.getElementById('timeLimit');
        
        // [NEW] Description Element
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

        // 2. [NEW] Update Mission Brief
        if (mapDesc) {
            // Falls back to a default text if description is missing in config
            mapDesc.textContent = map.description || "No tactical data available for this sector.";
        }

        // 3. Background Image Logic (Existing)
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
       
    // Call this function inside startMatch() after this.platoonData is loaded.
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

        // Check if player has enough command points
        const platoonCost = this.platoonData[slot].totalCost;
        if (this.gameState.commandPoints < platoonCost) {
            this.showNotification(`Not enough command points (Need: $${platoonCost})`, 'error');
            return;
        }

        // Disable slot during cooldown
        if (slotElement) slotElement.classList.add('disabled');

        // Start cooldown timer
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

        // Deduct command points
        this.gameState.commandPoints -= platoonCost;
        this.updateResourceDisplay({
            commandPoints: this.gameState.commandPoints,
            incomeRate: 150
        });

        // Send spawn request
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

    // Apply Music Volume
    if (music && musicSlider) {
        music.volume = musicSlider.value / 100;
    }

    //  Apply SFX Volume
    if (sfxSlider) {
        const sfxVol = sfxSlider.value / 100;
        Object.values(this.sounds).forEach(s => {
            s.volume = sfxVol;
        });
    }

    // In a real app, you might send this to Lua to save in KVP
    // this.fetchNUI('saveSettings', { music: musicSlider.value, sfx: sfxSlider.value });

    this.showNotification('Settings applied', 'success');
    this.closeModal('settingsModal');
    
    // Play a confirmation sound at the new volume
    this.playSFX('menuClick');
}

    // Make sure to save the keys: this.keyConfig = data.keys;


    // (You can delete the old getNotificationIcon method, as logic is now inside showNotification)

}

// Initialize when document is ready
document.addEventListener('DOMContentLoaded', () => {
    window.tacticalRTS = new TacticalRTS();
});

// Global function for FiveM NUI
if (typeof GetParentResourceName === 'undefined') {
    window.GetParentResourceName = () => 'enyo-rts';
}
