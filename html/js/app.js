// ===========================================================================
//  RTS NUI - Core Application Shell
//  Thin orchestrator that delegates to focused modules.
// ===========================================================================

window.TacticalRTS = window.TacticalRTS || {};

(function() {
    'use strict';

    // ---- State ----
    TacticalRTS.gameState = {
        currentScreen: 'loading',
        isInLobby: false,
        isInMatch: false,
        lobbyCode: null,
        playerReady: false,
        platoons: {},
        selectedUnits: [],
        commandPoints: 0,
        team: 0,
        isHost: false,
    };

    TacticalRTS.weight = 20;
    TacticalRTS.mapKeys = [];
    TacticalRTS.currentMapIndex = 0;
    TacticalRTS.draggedUnit = null;
    TacticalRTS.dragOverSlot = null;
    TacticalRTS.countdownInterval = null;
    TacticalRTS.currentMap = 'grapeseed';
    TacticalRTS.unitData = {};
    TacticalRTS.platoonData = {};
    TacticalRTS.unitConfig = {};
    TacticalRTS.categories = {};
    TacticalRTS.mapData = {};
    TacticalRTS.unitElements = {};
    TacticalRTS.overlayContainer = null;
    TacticalRTS.isQueued = false;
    TacticalRTS.queueTimerInterval = null;

    TacticalRTS.tips = [
        "Control the objectives. Or don't, if you enjoy being poor.",
        "Tanks are expensive. Try not to drive them off a cliff.",
        "If you are losing, surrendering saves time... but makes you a coward.",
        "Running out of money is a skill issue. Manage your economy better.",
        "Level up to unlock aircraft. Until then, enjoy walking.",
        "The enemy is capturing your objectives while you read this.",
        "You can deploy heavy support, or you can keep losing. Your choice.",
    ];

    // ---- NUI Bridge ----
    TacticalRTS.fetchNUI = async function(event, data) {
        try {
            const resp = await fetch(`https://${GetParentResourceName()}/${event}`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                body: JSON.stringify(data || {}),
            });
            return await resp.json();
        } catch (e) {
            return { success: false };
        }
    };

    // ---- Message Handler ----
    TacticalRTS.handleMessage = function(e) {
        const d = e.data;
        if (!d || !d.action) return;

        const handlers = {
            'setUnitConfig': function() {
                TacticalRTS.unitData = d.units || {};
                TacticalRTS.categories = d.categories || {};
                TacticalRTS.mapData = d.maps || {};
                TacticalRTS.mapKeys = Object.keys(TacticalRTS.mapData);
                TacticalRTS.loadUnitCards();
                TacticalRTS.buildMapCarousel();
            },
            'openMenu': function() {
                document.body.style.display = 'block';
                TacticalRTS.showScreen('mainMenu');
            },
            'returnToMenu': function() {
                TacticalRTS.showScreen('mainMenu');
            },
            'hideUI': function() {
                document.body.style.display = 'none';
            },
            'lobbyCreated': function() {
                TacticalRTS.gameState.lobbyCode = d.code;
                TacticalRTS.gameState.isHost = d.isHost;
                TacticalRTS.currentMap = d.map;
                TacticalRTS.renderLobbyScreen(d);
                TacticalRTS.showScreen('lobbyScreen');
            },
            'startMatch': function() {
                TacticalRTS.gameState.isInMatch = true;
                TacticalRTS.gameState.team = d.team;
                TacticalRTS.showScreen('gameUI');
                TacticalRTS.startGameUI(d);
            },
            'endMatch': function() {
                TacticalRTS.gameState.isInMatch = false;
                TacticalRTS.showScreen('resultScreen');
                TacticalRTS.showResultScreen(d);
            },
            'updateLobby': function() {
                TacticalRTS.renderLobbyPlayers(d);
            },
            'updateResources': function() {
                TacticalRTS.gameState.commandPoints = d.commandPoints;
                TacticalRTS.updateResourceDisplay(d.commandPoints, d.incomeRate);
            },
            'updateTimer': function() {
                TacticalRTS.updateMatchTimer(d);
            },
            'updateUnitPositions': function() {
                TacticalRTS.renderUnitPositions(d.units);
            },
            'updateObjectiveUI': function() {
                TacticalRTS.renderObjectiveMarkers(d.objectives);
            },
            'updateObjectives': function() {
                TacticalRTS.updateObjectiveState(d);
            },
            'objectiveCaptured': function() {
                TacticalRTS.showNotification(`${d.name} captured by Team ${d.team}`, 'objective');
            },
            'updateSelection': function() {
                TacticalRTS.updateSelectionDisplay(d.count, d.health);
            },
            'updatePlatoonCooldown': function() {
                TacticalRTS.setPlatoonCooldown(d.slot, d.cooldown);
            },
            'platoonDeployed': function() {
                TacticalRTS.addDeployedPlatoon(d);
            },
            'startAirstrikeTimer': function() {
                TacticalRTS.startAirstrikeTimer(d.duration);
            },
            'stopAirstrikeTimer': function() {
                TacticalRTS.stopAirstrikeTimer();
            },
            'startCountdown': function() {
                TacticalRTS.startLobbyCountdown(d);
            },
            'abortCountdown': function() {
                TacticalRTS.abortCountdown();
            },
            'showNotification': function() {
                TacticalRTS.showNotification(d.message, d.type);
            },
            'forceJoinLobby': function() {
                TacticalRTS.gameState.isInLobby = true;
                TacticalRTS.gameState.lobbyCode = d.code || d.lobbyData?.code;
                TacticalRTS.gameState.isHost = d.isHost;
                TacticalRTS.currentMap = d.lobbyData?.map || 'grapeseed';
                TacticalRTS.renderLobbyScreen(d);
                TacticalRTS.showScreen('lobbyScreen');
            },
        };

        const handler = handlers[d.action];
        if (handler) handler();
    };

    // ---- Init ----
    TacticalRTS.init = function() {
        const isGameMode = !!window.invokeNative;
        TacticalRTS.overlayContainer = document.getElementById('game-input-layer');

        if (isGameMode) {
            window.addEventListener('message', TacticalRTS.handleMessage.bind(this));
            TacticalRTS.bindEvents();
            TacticalRTS.initInputSystem();
            TacticalRTS.startLiveStatsPoller();

            const handshake = setInterval(function() {
                if (TacticalRTS.gameState.currentScreen === 'mainMenu') {
                    clearInterval(handshake);
                    return;
                }
                TacticalRTS.fetchNUI('initialize', {});
            }, 500);
        }
    };

    // ---- DOM ready ----
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', TacticalRTS.init);
    } else {
        TacticalRTS.init();
    }
})();
