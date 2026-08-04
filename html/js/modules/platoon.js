TacticalRTS.prototype.initializePlatoonBuilder = function() {
    this.loadUnitData();
    this.renderUnitList();
    this.initializeSlotWeights();
    this.updateMapPreview(this.currentMap);

};

TacticalRTS.prototype.loadUnitData = function() {
    this.unitData2 = {
        rifleman: {
            name: 'RIFLEMAN',
            weight: 2,
            cost: 200,
            icon: '\uD83D\uDD2B',
            category: 'infantry',
            description: 'Standard infantry'
        },
        heavy_gunner: {
            name: 'HEAVY GUNNER',
            weight: 4,
            cost: 350,
            icon: '\uD83D\uDCA5',
            category: 'infantry',
            description: 'Heavy MG support'
        },
        sniper: {
            name: 'SNIPER',
            weight: 3,
            cost: 500,
            icon: '\uD83C\uDFAF',
            category: 'infantry',
            description: 'Long range'
        },
        apc: {
            name: 'ARMORED APC',
            weight: 8,
            cost: 800,
            icon: '\uD83D\uDEE1\uFE0F',
            category: 'vehicles',
            description: 'Troop transport'
        },
        tank: {
            name: 'BATTLE TANK',
            weight: 12,
            cost: 1200,
            icon: '\u2699\uFE0F',
            category: 'vehicles',
            description: 'Heavy armor'
        },
        technical: {
            name: 'ARMED TECHINCAL',
            weight: 5,
            cost: 600,
            icon: '\uD83D\uDE97',
            category: 'vehicles',
            description: 'Fast scout'
        },
        attack_heli: {
            name: 'ATTACK HELI',
            weight: 10,
            cost: 1500,
            icon: '\uD83D\uDE81',
            category: 'aircraft',
            description: 'Air support'
        }
    };
};

TacticalRTS.prototype.loadMapData = function() {
    this.mapData = {};
};

TacticalRTS.prototype.renderMapList = function() {
    if (!this.mapData) return;

    this.mapKeys = Object.keys(this.mapData);
    
    if (this.mapKeys.length > 0) {
        this.currentMapIndex = 0;
        setTimeout(() => this.updateCarouselDisplay(), 100); 
    } else {
        const nameEl = document.getElementById('carouselMapName');
        if (nameEl) nameEl.textContent = "NO MAPS FOUND";
    }
};

TacticalRTS.prototype.updateCarouselDisplay = function() {
    if (this.mapKeys.length === 0) return;

    const mapKey = this.mapKeys[this.currentMapIndex];
    const map = this.mapData[mapKey];

    this.currentMap = mapKey; 

    const bgEl = document.getElementById('carouselBg');
    const nameEl = document.getElementById('carouselMapName');
    const labelEl = document.querySelector('.carousel-label');

    if (nameEl) {
        nameEl.getAnimations().forEach(anim => anim.cancel());
        
        nameEl.classList.remove('is-scrolling');
        
        nameEl.style.textOverflow = 'ellipsis';
        nameEl.style.overflow = 'hidden';
        nameEl.style.transform = 'translateX(0)'; // Reset position
    }

    const finalName = (map.name || mapKey).toUpperCase();
    if (nameEl) nameEl.textContent = finalName;
    
    if (labelEl) labelEl.textContent = `SECTOR ${this.currentMapIndex + 1}/${this.mapKeys.length}`;
    
    if (bgEl) {
        const imageFile = map.thumbnail || 'default.jpg'; 
        bgEl.style.backgroundImage = `url('images/maps/${imageFile}')`;
    }

    if (nameEl) {
        setTimeout(() => {
            if (nameEl.scrollWidth > nameEl.clientWidth) {
                
                const scrollDistance = nameEl.scrollWidth - nameEl.clientWidth + 20; 
                
                nameEl.style.textOverflow = 'clip'; 
                nameEl.style.overflow = 'visible'; 
                nameEl.classList.add('is-scrolling');
                
                nameEl.animate([
                    { transform: 'translateX(0)' },
                    { transform: 'translateX(0)', offset: 0.2 }, // Wait 20% of time
                    { transform: `translateX(-${scrollDistance}px)`, offset: 0.8 }, // Move
                    { transform: `translateX(-${scrollDistance}px)`, offset: 1 } // Wait at end
                ], {
                    duration: 4000, 
                    iterations: Infinity,
                    direction: 'alternate',
                    easing: 'ease-in-out'
                });
            } 
        }, 50);
    }
};

TacticalRTS.prototype.nextMap = function() {
    if (this.mapKeys.length === 0) return;
    this.currentMapIndex++;
    if (this.currentMapIndex >= this.mapKeys.length) this.currentMapIndex = 0;
    this.updateCarouselDisplay();
};

TacticalRTS.prototype.prevMap = function() {
    if (this.mapKeys.length === 0) return;
    this.currentMapIndex--;
    if (this.currentMapIndex < 0) this.currentMapIndex = this.mapKeys.length - 1;
    this.updateCarouselDisplay();
};

TacticalRTS.prototype.filterUnits = function(category) {
    this.renderUnitList(category);
};

TacticalRTS.prototype.updateCategoryButtons = function(activeBtn) {
    document.querySelectorAll('.category-btn').forEach(btn => {
        btn.classList.remove('active');
    });
    activeBtn.classList.add('active');
};

TacticalRTS.prototype.addUnitToSlot = function(unitType, slot, count = 1) {
    const unit = this.unitData[unitType];
    if (!unit) return;

    if (!this.platoonData[slot]) {
        this.platoonData[slot] = { units: [], totalWeight: 0, totalCost: 0 };
    }

    const currentWeight = parseInt(this.platoonData[slot].totalWeight || 0);
    const unitWeight = parseInt(unit.weight || 0);
    const addedWeight = unitWeight * count;

    if ((currentWeight + addedWeight) > this.weight) {
        this.showNotification('Platoon weight limit exceeded (Max '+this.weight+')', 'error');
        return;
    }

    const existing = this.platoonData[slot].units.find(u => u.type === unitType);
    if (existing) {
        existing.count += count;
    } else {
        this.platoonData[slot].units.push({
            type: unitType,
            count: count,
            weight: unitWeight,
            cost: parseInt(unit.cost || 0)
        });
    }

    this.platoonData[slot].totalWeight = currentWeight + addedWeight;
    this.platoonData[slot].totalCost += (parseInt(unit.cost || 0) * count);

    this.renderSlotContent(slot);
    this.updateTotalWeight();
    this.updateSlotWeights();
    this.showNotification(`${count}x ${unit.name || unitType} added`, 'success');
};

TacticalRTS.prototype.removeUnitFromSlot = function(unitType, slot) {
    if (!this.platoonData[slot]) return;

    const unitIndex = this.platoonData[slot].units.findIndex(u => u.type === unitType);
    if (unitIndex !== -1) {
        const unit = this.platoonData[slot].units[unitIndex];
        const unitData = this.unitData[unitType];

        this.platoonData[slot].totalWeight -= unit.weight * unit.count;
        this.platoonData[slot].totalCost -= unit.cost * unit.count;

        this.platoonData[slot].units.splice(unitIndex, 1);

        if (this.platoonData[slot].units.length === 0) {
            delete this.platoonData[slot];
        }

        this.renderSlotContent(slot);
        this.updateTotalWeight();
        this.updateSlotWeights();

        this.showNotification(`${unitData.name} removed from platoon`, 'info');
    }
};

TacticalRTS.prototype.clearAllPlatoons = function() {
 
        this.platoonData = {};
        for (let slot = 1; slot <= 5; slot++) {
            this.renderSlotContent(slot);
        }
        this.updateTotalWeight();
        this.updateSlotWeights();
        this.showNotification('All platoons cleared', 'info');
    
};

TacticalRTS.prototype.updateSlotWeights = function() {
    for (let slot = 1; slot <= 5; slot++) {
        const weight = this.platoonData[slot] ? this.platoonData[slot].totalWeight : 0;
        const cost = this.platoonData[slot] ? this.platoonData[slot].totalCost : 0;

        const weightElement = document.getElementById(`slot${slot}Weight`);
        const costElement = document.getElementById(`slot${slot}Cost`);
        const quickCostElement = document.getElementById(`quickCost${slot}`);

        if (weightElement) weightElement.textContent = weight;
        if (costElement) costElement.textContent = cost;
        if (quickCostElement) quickCostElement.textContent = cost > 0 ? `$${cost}` : '-';
    }
};

TacticalRTS.prototype.updateTotalWeight = function() {
    let totalWeight = 0;
    let totalCost = 0;

    for (let slot = 1; slot <= 5; slot++) {
        if (this.platoonData[slot]) {
            totalWeight += this.platoonData[slot].totalWeight;
            totalCost += this.platoonData[slot].totalCost;
        }
    }

    const totalWeightElement = document.getElementById('totalWeight');
    if (totalWeightElement) totalWeightElement.textContent = totalWeight;

    const weightIndicator = document.querySelector('.weight-value');

    if (weightIndicator) {
        weightIndicator.textContent = totalWeight;

        if (totalWeight > this.weight + 5) {
            weightIndicator.style.color = '#ff4757';
        } else {
            weightIndicator.style.color = '#4cd137';
        }
    }
};

TacticalRTS.prototype.initializeSlotWeights = function() {
    
    for (let slot = 1; slot <= 5; slot++) {
        const weightElement = document.getElementById(`slot${slot}Weight`);
        const costElement = document.getElementById(`slot${slot}Cost`);
        document.getElementById('maxWeight').innerHTML = this.weight * 5;
        if (weightElement) weightElement.textContent = '0';
        if (costElement) costElement.textContent = '0';
    }

    const totalWeightElement = document.getElementById('totalWeight');
    if (totalWeightElement) totalWeightElement.textContent = '0';
};

TacticalRTS.prototype.calculateAllowedWeight = function(playerLevel, config, minLevel = 1) {
    if (!config) return 20; // Default weight fallback
    
    const capLevel = config.capLevel || 60;
    const level = Math.min(playerLevel, capLevel);

    const totalMilestones = Math.floor((capLevel - minLevel) / (config.milestone || 10));
    const currentMilestone = Math.max(
        Math.floor((level - minLevel) / (config.milestone || 10)),
        0
    );

    const weightPerMilestone = ((config.capped || 40) - (config.starts || 20)) / (totalMilestones || 1);

    return Math.floor((config.starts || 20) + (currentMilestone * weightPerMilestone));
};