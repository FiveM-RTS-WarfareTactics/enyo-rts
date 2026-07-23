// ===========================================================================
//  RTS NUI - Platoon Builder (Unit Cards, Drag & Drop, Slots)
// ===========================================================================

(function() {
    if (!window.TacticalRTS) return;

    TacticalRTS.loadUnitCards = function() {
        var list = document.getElementById('unitsList');
        if (!list) return;
        list.innerHTML = '';

        var cats = TacticalRTS.categories || {};
        var units = TacticalRTS.unitData || {};
        var sorted = [];

        Object.keys(units).forEach(function(k) {
            var u = units[k];
            sorted.push({ key: k, cat: u.category || 'infantry', sort: cats[u.category]?.sort || 99, unit: u });
        });
        sorted.sort(function(a, b) { return a.sort - b.sort || (a.unit.unlockLevel || 1) - (b.unit.unlockLevel || 1); });

        sorted.forEach(function(item) {
            var u = item.unit;
            var div = document.createElement('div');
            div.className = 'unit-card';
            div.dataset.unitType = item.key;
            div.draggable = true;

            div.innerHTML =
                '<div class="card-img"><img src="images/units/' + (u.thumbnail || 'rifleman.png') + '" /></div>' +
                '<div class="card-body">' +
                    '<div class="card-name">' + (u.name || item.key) + '</div>' +
                    '<div class="card-stats">' +
                        '<span><i class="fas fa-dollar-sign"></i> ' + (u.cost || 0) + '</span>' +
                        '<span><i class="fas fa-weight-hanging"></i> ' + (u.weight || 1) + '</span>' +
                    '</div>' +
                    '<div class="card-level">LVL ' + (u.unlockLevel || 1) + '</div>' +
                '</div>';

            div.addEventListener('dragstart', function(e) {
                TacticalRTS.draggedUnit = item.key;
                e.dataTransfer.setData('text/plain', item.key);
                e.dataTransfer.effectAllowed = 'copy';
                div.classList.add('dragging');
            });
            div.addEventListener('dragend', function() {
                div.classList.remove('dragging');
                TacticalRTS.draggedUnit = null;
            });

            list.appendChild(div);
        });

        // Category buttons
        var catContainer = document.querySelector('.unit-categories');
        if (catContainer) {
            catContainer.innerHTML = '<button class="category-btn active" data-category="all">ALL</button>';
            Object.keys(cats).forEach(function(k) {
                var c = cats[k];
                catContainer.innerHTML += '<button class="category-btn" data-category="' + k + '" style="color:' + (c.color || '#fff') + '">' + c.name + '</button>';
            });
        }

        // Slot drop zones
        document.querySelectorAll('.platoon-slot').forEach(function(slot) {
            slot.addEventListener('dragover', function(e) { e.preventDefault(); slot.classList.add('drag-over'); });
            slot.addEventListener('dragleave', function() { slot.classList.remove('drag-over'); });
            slot.addEventListener('drop', function(e) {
                e.preventDefault();
                slot.classList.remove('drag-over');
                if (TacticalRTS.draggedUnit) TacticalRTS.addUnitToSlot(TacticalRTS.draggedUnit, slot.dataset.slot);
            });
        });
    };

    TacticalRTS.filterUnits = function(cat) {
        document.querySelectorAll('.unit-card').forEach(function(card) {
            var u = TacticalRTS.unitData[card.dataset.unitType];
            if (!u) return;
            card.style.display = (cat === 'all' || u.category === cat) ? 'flex' : 'none';
        });
    };

    TacticalRTS.updateCategoryButtons = function(activeBtn) {
        document.querySelectorAll('.category-btn').forEach(function(b) { b.classList.remove('active'); });
        if (activeBtn) activeBtn.classList.add('active');
    };

    TacticalRTS.addUnitToSlot = function(unitKey, slotNum) {
        var u = TacticalRTS.unitData[unitKey];
        if (!u) return;

        TacticalRTS.platoonData[slotNum] = TacticalRTS.platoonData[slotNum] || { units: [] };
        var platoon = TacticalRTS.platoonData[slotNum];

        // Check if unit already exists
        for (var i = 0; i < platoon.units.length; i++) {
            if (platoon.units[i].type === unitKey) {
                platoon.units[i].count = (platoon.units[i].count || 1) + 1;
                TacticalRTS.refreshSlotDisplay(slotNum);
                return;
            }
        }

        platoon.units.push({ type: unitKey, count: 1 });
        TacticalRTS.refreshSlotDisplay(slotNum);
    };

    TacticalRTS.removeUnitFromSlot = function(unitKey, slotNum) {
        var platoon = TacticalRTS.platoonData[slotNum];
        if (!platoon) return;
        for (var i = 0; i < platoon.units.length; i++) {
            if (platoon.units[i].type === unitKey) {
                platoon.units[i].count--;
                if (platoon.units[i].count <= 0) platoon.units.splice(i, 1);
                break;
            }
        }
        TacticalRTS.refreshSlotDisplay(slotNum);
    };

    TacticalRTS.clearAllPlatoons = function() {
        TacticalRTS.platoonData = {};
        for (var i = 1; i <= 5; i++) TacticalRTS.refreshSlotDisplay(i);
    };

    TacticalRTS.refreshSlotDisplay = function(slotNum) {
        var content = document.getElementById('slot' + slotNum + 'Content');
        var weight = document.getElementById('slot' + slotNum + 'Weight');
        var costEl = document.getElementById('slot' + slotNum + 'Cost');
        if (!content) return;

        var platoon = TacticalRTS.platoonData[slotNum] || { units: [] };
        var totalWeight = 0, totalCost = 0, html = '';

        platoon.units.forEach(function(unit) {
            var u = TacticalRTS.unitData[unit.type];
            if (!u) return;
            var cnt = unit.count || 1;
            totalWeight += (u.weight || 1) * cnt;
            totalCost += (u.cost || 0) * cnt;
            html += '<div class="platoon-unit"><span>' + (u.name || unit.type) + ' x' + cnt + '</span><button class="remove-unit" data-unit-type="' + unit.type + '">x</button></div>';
        });

        content.innerHTML = html || '<div class="empty-slot">DROP UNITS HERE</div>';
        if (weight) weight.textContent = totalWeight;
        if (costEl) costEl.textContent = totalCost;
        TacticalRTS.updateTotalWeight();
    };

    TacticalRTS.updateTotalWeight = function() {
        var total = 0;
        for (var i = 1; i <= 5; i++) {
            var platoon = TacticalRTS.platoonData[i];
            if (platoon) {
                platoon.units.forEach(function(u) {
                    var cfg = TacticalRTS.unitData[u.type];
                    total += (cfg?.weight || 1) * (u.count || 1);
                });
            }
        }
        var tw = document.getElementById('totalWeight');
        if (tw) tw.textContent = total;
    };
})();
