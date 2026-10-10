.pragma library

// KWin's real and settings-preview models share these two role numbers.
var captionRole = 257;
var windowIdRole = 261;

function snapshot(model, windows) {
    if (!model) return [];
    var byId = {};
    for (var i = 0; i < windows.length; ++i)
        byId[String(windows[i].internalId)] = windows[i];
    var result = [];
    for (var row = 0; row < model.rowCount(); ++row) {
        var index = model.index(row, 0);
        var windowId = model.data(index, windowIdRole);
        var id = String(windowId);
        var window = byId[id];
        var frame = window ? window.frameGeometry : { x: row, y: 0 };
        result.push({
            nativeIndex: row, id: id, windowId: windowId, window: window || null,
            caption: model.data(index, captionRole),
            icon: window ? window.icon : model.data(index, 260),
            closeable: window ? window.closeable : false,
            x: frame.x, y: frame.y
        });
    }
    return result.sort(function(a, b) {
        return a.x - b.x || a.y - b.y ||
            (a.id < b.id ? -1 : a.id > b.id ? 1 : a.nativeIndex - b.nativeIndex);
    });
}

// True when a rebuilt snapshot shows the same entries in the same order.
function sameEntries(a, b) {
    return a.length === b.length && a.every(function(row, i) {
        return row.id === b[i].id && row.caption === b[i].caption &&
            row.closeable === b[i].closeable;
    });
}

function wrap(index, count) {
    return count ? (index % count + count) % count : -1;
}

function rowForNative(rows, index) {
    for (var row = 0; row < rows.length; ++row)
        if (rows[row].nativeIndex === index) return row;
    return -1;
}

function direction(previous, next, count) {
    var difference = wrap(next - previous, count);
    if (difference === 1) return 1;
    if (difference === count - 1) return -1;
    return 0;
}
