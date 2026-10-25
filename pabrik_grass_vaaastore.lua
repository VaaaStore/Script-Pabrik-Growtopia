local SC = "AUTO PABRIK GRASS VaaaStore v1.0"
local C = {
    plant_count   = 10,            -- jumlah platform yang ditanam (ke kanan dari posisi awal bot)
    plant_offset  = 2,             -- mulai tanam dari posisi awal bot
    seed_id     = "18",  -- nama item (dicari otomatis); isi seed_id/block_id/vend_id jika gagal
    block_id    = "19",  -- nama item (dicari otomatis); isi seed_id/block_id/vend_id jika gagal
    vend_name     = "Vending Machine",
    seed_id = nil, block_id = nil, vend_id = nil,
    vend_pos      = nil,           -- {x, y} manual; kosong = cari Vending terdekat dari posisi awal
    restock_min    = 120,          -- max seed di backpack
    restock_amount = 100,          -- jumlah seed yang di setor
    vend_cap       = 5000,         -- kapasitas vending
    vend_stock_start = 0,          -- isi vending saat script mulai (jika tidak tahu, isi 0)
    manual_wait    = 300000,       -- batas tunggu stock manual (mode belajar), ms
    stack_cap     = 200,           -- maksimal satu jenis item di tas
    pnb_offsets   = {-1, 0, 1},    -- tile yang dipecah: baris di atas bot (x + offset, y - 1)
    pnb_max_idle  = 20,            -- putaran PNB tanpa kemajuan sebelum dihentikan
    max_hits      = 12,            -- hit max block
    delay_min     = 150,           -- delay acak minimum (ms)
    delay_max     = 1000,          -- delay acak maksimum (ms)
    grow_default  = 120,           -- detik, dipakai jika growTime item tidak terbaca
    grow_extra    = 60,            -- detik tambahan batas tunggu tumbuh
    dump_vend     = "vending_dump.txt"
}

local function log_hp(t) log("[" .. SC .. "] " .. tostring(t)) end
local RUN, ID, home, V = true, {}, {x = 0, y = 0}, {wait = false, dialog = nil, learning = false, rec = {}, dlgs = {}}
local stats, start_world, vend_stock = {cycles = 0, planted = 0, stocked = 0}, "", C.vend_stock_start
local pref
do
    local ok, p = pcall(function()
        local m = require("preferences")
        m:new("pabrik_grass_vaaastore")
        return m
    end)
    if ok then
        pref = p
        pcall(function() pref:load() end)
    end
end
local function pget(k, d)
    if not pref then return d end
    local ok, v = pcall(function() return pref:get(k, d) end)
    if ok and v ~= nil then return v end
    return d
end
local function pset(k, v)
    if pref then pcall(function() pref:set(k, v) pref:save() end) end
end

local lag = 0
local function pause(lo, hi) sleep(math.random(lo or C.delay_min, hi or C.delay_max) + lag) end
local function lag_bad() lag = math.min(lag + 300, 2000) end
local function lag_ok() lag = math.max(lag - 100, 0) end

local function wait_until(fn, ms)
    local t = getTime()
    while getTime() - t < ms do
        local ok, r = pcall(fn)
        if ok and r then return true end
        sleep(100)
    end
    return false
end

local function inv(id)
    for _, it in pairs(getInventory()) do
        if it.id == id then return it.amount end
    end
    return 0
end

local function tile(x, y)
    local ok, t = pcall(getTile, x, y)
    if ok then return t end
end

local function tile_pos()
    local me = getLocal()
    return me.posX // 32, me.posY // 32
end

local function world_name()
    local ok, w = pcall(getCurrentWorldName)
    return (ok and w) or ""
end

local function ready()
    local ok, me = pcall(getLocal)
    return ok and me ~= nil and me.posX ~= nil and world_name() ~= ""
end

local function resolve(name, manual)
    if manual then return manual end
    local ok, id = pcall(findItemID, name)
    if ok and type(id) == "number" and id > 0 then return id end
    local ok2, info = pcall(getItemInfoByName, name)
    if ok2 and info and info.id and info.id > 0 then return info.id end
end

local function walk_to(x, y)
    local px, py = tile_pos()
    if px == x and py == y then return true end
    FindPath(x, y)
    local t = getTime()
    while getTime() - t < 3000 do
        px, py = tile_pos()
        if px == x and py == y then return true end
        sleep(200)
    end
    return false
end

local function act(x, y, item)
    local me = getLocal()
    sendPacketRaw(false, {type = 3, value = item, px = x, py = y, x = me.posX, y = me.posY})
end

local function obj_tile(o) return o.pos.x // 32, o.pos.y // 32 end

local function collect()
    local px, py = tile_pos()
    for _, o in pairs(getObjectList()) do
        local ox, oy = obj_tile(o)
        if math.abs(ox - px) <= 3 and math.abs(oy - py) <= 3 then
            sendPacketRaw(false, {type = 11, value = o.id, x = o.pos.x, y = o.pos.y})
        end
    end
end

local function floor_total(item)
    local n = 0
    for _, o in pairs(getObjectList()) do
        if o.itemid == item then n = n + o.amount end
    end
    return n
end

local function fetch_floor(item)
    for _, o in pairs(getObjectList()) do
        if o.itemid == item then
            if inv(item) >= C.stack_cap then return end
            local ox, oy = obj_tile(o)
            if walk_to(ox, oy) then
                collect()
                pause()
            end
        end
    end
end

local function banner(title, lines)
    local d = {
        "set_default_color|`o",
        "add_label_with_icon|big|`w" .. title .. "``|left|" .. (ID.seed or 242) .. "|",
        "add_spacer|small|"
    }
    for _, l in ipairs(lines) do d[#d + 1] = "add_smalltext|" .. l .. "``|left|" end
    d[#d + 1] = "add_spacer|small|"
    d[#d + 1] = "end_dialog|pabrik_grass_vaaastore|Close|OKE|"
    pcall(growtopia.sendDialog, table.concat(d, "\n"))
end

local function banner_start()
    banner(SC, {
        "`2VaaaStore - Pabrik rumput otomatis",
        "`oAlur: Plant > Harvest > PNB > Sweep > Restock Vending.",
        "`oPosisi awal: " .. home.x .. "," .. home.y .. " (titik pulang).",
        "`oTanam " .. C.plant_count .. " blok ke kanan mulai X+" .. C.plant_offset .. ".",
        "`oRestock " .. C.restock_amount .. " seed saat seed di tas >= " .. C.restock_min .. ".",
        "`9Berhenti otomatis saat Vending penuh (" .. C.vend_cap .. ")."
    })
end

local function banner_stop(reason)
    banner(SC .. " - SELESAI", {
        "`4Script berhenti: " .. reason,
        "`oSiklus selesai: " .. stats.cycles,
        "`oTanaman ditanam: " .. stats.planted,
        "`oSeed masuk Vending: " .. stats.stocked .. " (isi sekarang: " .. vend_stock .. ")",
        "`2Terima kasih sudah memakai VaaaStore."
    })
end

local function shutdown(reason)
    if not RUN then return end
    RUN = false
    log_hp("BERHENTI: " .. reason)
    banner_stop(reason)
    pcall(removeHook, "onVariant")
    pcall(removeHook, "onSendPacket")
end

local function plant_tile(x, y)
    for _ = 1, 2 do
        act(x, y, ID.seed)
        pause()
        local ok = wait_until(function()
            local g = tile(x, y)
            return g and g.fg == ID.seed
        end, 1500)
        if ok then
            lag_ok()
            return true
        end
        lag_bad()
    end
    return false
end

local function plant_phase()
    log_hp("Plant...")
    local list = {}
    for i = 0, C.plant_count - 1 do
        local x, y = home.x + C.plant_offset + i, home.y
        local t, b = tile(x, y), tile(x, y + 1)
        if not t or not b or b.fg == 0 then break end
        if t.fg == ID.seed then
            list[#list + 1] = {x = x, y = y}
        elseif t.fg == 0 then
            if inv(ID.seed) <= 0 then break end
            if walk_to(x, y) and plant_tile(x, y) then
                list[#list + 1] = {x = x, y = y}
                stats.planted = stats.planted + 1
            else
                break
            end
        else
            break
        end
    end
    log_hp("Plant selesai: " .. #list .. " tile")
    return list
end

local function wait_ready(list)
    local gt = C.grow_default
    local ok, info = pcall(getItemInfoByID, ID.seed)
    if ok and info and info.growTime and info.growTime > 0 then gt = info.growTime end
    local deadline = getTime() + (gt + C.grow_extra) * 1000
    log_hp("Menunggu tumbuh (" .. gt .. " detik)...")
    while getTime() < deadline and RUN do
        local pending = 0
        for _, p in ipairs(list) do
            local t = tile(p.x, p.y)
            if t and t.fg == ID.seed and not t.readyharvest then pending = pending + 1 end
        end
        if pending == 0 then return true end
        sleep(2000)
    end
    return false
end

local function harvest_tile(p)
    if not walk_to(p.x, p.y) then return false end
    for _ = 1, 3 do
        act(p.x, p.y, 18)
        pause()
        local done = wait_until(function()
            local g = tile(p.x, p.y)
            return g and (g.fg ~= ID.seed or not g.readyharvest)
        end, 1500)
        if done then
            lag_ok()
            collect()
            return true
        end
        lag_bad()
    end
    return false
end

local function harvest(list)
    log_hp("Harvest...")
    local done = 0
    for _, p in ipairs(list) do
        local t = tile(p.x, p.y)
        if t and t.fg == ID.seed and t.readyharvest and harvest_tile(p) then done = done + 1 end
    end
    log_hp("Harvest selesai: " .. done)
    return done
end

local function pnb_tile(x, y)
    local t0 = tile(x, y)
    if not t0 or (t0.fg ~= 0 and t0.fg ~= ID.block) then return end
    if t0.fg == 0 then
        if inv(ID.block) <= 0 then return end
        act(x, y, ID.block)
        pause()
        local placed = wait_until(function()
            local g = tile(x, y)
            return g and g.fg == ID.block
        end, 1500)
        if not placed then
            lag_bad()
            return
        end
    end
    for _ = 1, C.max_hits do
        act(x, y, 18)
        pause()
        local g = tile(x, y)
        if g and g.fg ~= ID.block then
            lag_ok()
            return
        end
    end
end

local function pnb()
    log_hp("PNB...")
    local last, idle = nil, 0
    while RUN do
        local remain = inv(ID.block) + floor_total(ID.block)
        if remain == 0 then
            log_hp("PNB selesai, block bersih")
            return true
        end
        if last and remain >= last then idle = idle + 1 else idle = 0 end
        if idle >= C.pnb_max_idle then
            log_hp("PNB macet, sisa block: " .. remain)
            return false
        end
        last = remain
        if inv(ID.block) <= 0 then fetch_floor(ID.block) end
        if inv(ID.block) > 0 and walk_to(home.x, home.y) then
            for _, dx in ipairs(C.pnb_offsets) do pnb_tile(home.x + dx, home.y - 1) end
            collect()
        end
        pause()
    end
    return false
end

local function sweep()
    log_hp("Sweep...")
    for _ = 1, 5 do
        fetch_floor(ID.block)
        fetch_floor(ID.seed)
        if inv(ID.block) > 0 then pnb() end
        local block_left = inv(ID.block) + floor_total(ID.block)
        local seed_left = floor_total(ID.seed)
        if block_left == 0 and (seed_left == 0 or inv(ID.seed) >= C.stack_cap) then break end
    end
    walk_to(home.x, home.y)
end

local function wrench(x, y)
    local me = getLocal()
    sendPacketRaw(false, {type = 3, value = 32, px = x, py = y, x = me.posX, y = me.posY})
end

local function find_vending()
    if C.vend_pos then return C.vend_pos[1], C.vend_pos[2] end
    local best, bd
    for _, t in pairs(getTiles()) do
        if t.fg == ID.vend then
            local d = math.abs(t.x - home.x) + math.abs(t.y - home.y)
            if not bd or d < bd then best, bd = t, d end
        end
    end
    if best then return best.x, best.y end
end

local function stand_near(vx, vy)
    local px, py = tile_pos()
    if math.abs(px - vx) <= 2 and math.abs(py - vy) <= 2 then return true end
    for _, d in ipairs({{-1, 0}, {1, 0}, {-2, 0}, {2, 0}, {0, -1}}) do
        local x, y = vx + d[1], vy + d[2]
        local t = tile(x, y)
        if t and t.fg == 0 and walk_to(x, y) then return true end
    end
    return false
end

local function save_tpl(list)
    local enc = {}
    for _, s in ipairs(list) do enc[#enc + 1] = (s:gsub("\n", "~N~")) end
    pset("vend_tpl", table.concat(enc, "@@"))
end

local function load_tpl()
    local s = pget("vend_tpl", "")
    if s == "" then return nil end
    local out = {}
    for part in (s .. "@@"):gmatch("(.-)@@") do
        if part ~= "" then out[#out + 1] = (part:gsub("~N~", "\n")) end
    end
    if #out > 0 then return out end
end

local function build_tpl(rec, vx, vy, item, amount)
    local out = {}
    for _, pkt in ipairs(rec) do
        if pkt:find("tilex|", 1, true) or pkt:lower():find("vend", 1, true) then
            local p = pkt
            p = p:gsub("tilex|" .. vx .. "%f[%D]", "tilex|{X}")
            p = p:gsub("tiley|" .. vy .. "%f[%D]", "tiley|{Y}")
            p = p:gsub("|" .. item .. "%f[%D]", "|{ITEM}")
            p = p:gsub("|" .. amount .. "%f[%D]", "|{AMOUNT}")
            out[#out + 1] = p
        end
    end
    return out
end

local function replay(tpl, vx, vy, amount, before)
    V.wait, V.dialog = true, nil
    wrench(vx, vy)
    if not wait_until(function() return V.dialog ~= nil end, 5000) then
        V.wait = false
        log_hp("Dialog vending tidak muncul")
        return false
    end
    for _, step in ipairs(tpl) do
        local pkt = step
        pkt = pkt:gsub("{X}", tostring(vx))
        pkt = pkt:gsub("{Y}", tostring(vy))
        pkt = pkt:gsub("{ITEM}", tostring(ID.seed))
        pkt = pkt:gsub("{AMOUNT}", tostring(amount))
        sendPacket(2, pkt)
        pause(700, 1200)
    end
    V.wait = false
    return wait_until(function() return before - inv(ID.seed) >= amount end, 6000)
end

local function manual_restock(vx, vy, amount, before)
    V.learning, V.rec, V.dlgs = true, {}, {}
    growtopia.notify("`2Masukkan " .. amount .. " seed ke Vending (script menunggu dan belajar)")
    log_hp("MODE BELAJAR: stock " .. amount .. " seed ke Vending secara manual, script menunggu...")
    local ok = wait_until(function() return before - inv(ID.seed) >= amount end, C.manual_wait)
    V.learning = false
    if not ok then return false end
    local tpl = build_tpl(V.rec, vx, vy, ID.seed, before - inv(ID.seed))
    if #tpl > 0 then
        save_tpl(tpl)
        log_hp("Template restock tersimpan (" .. #tpl .. " langkah). Restock berikutnya otomatis.")
    end
    return true
end

local function restock()
    local vx, vy = find_vending()
    if not vx then return false, "Vending Machine tidak ditemukan" end
    local room = C.vend_cap - vend_stock
    if room <= 0 then return false, "Vending penuh" end
    local amount = math.min(C.restock_amount, room)
    if inv(ID.seed) < amount then return false, "Seed tidak cukup untuk restock" end
    if not stand_near(vx, vy) then return false, "Tidak bisa mendekati Vending" end
    local before, ok = inv(ID.seed), false
    local tpl = load_tpl()
    if tpl then
        ok = replay(tpl, vx, vy, amount, before)
        if not ok then
            log_hp("Restock otomatis gagal, template dihapus, beralih ke mode belajar")
            pset("vend_tpl", "")
        end
    end
    if not ok then ok = manual_restock(vx, vy, amount, before) end
    if not ok then return false, "Restock gagal" end
    local delta = before - inv(ID.seed)
    vend_stock = vend_stock + delta
    stats.stocked = stats.stocked + delta
    log_hp("Restock " .. delta .. " seed, isi Vending: " .. vend_stock .. "/" .. C.vend_cap)
    walk_to(home.x, home.y)
    return true
end

local function on_variant(var)
    local ok, res = pcall(function()
        if var.v1 ~= "OnDialogRequest" or type(var.v2) ~= "string" then return false end
        if V.wait then
            V.dialog = var.v2
            pcall(writeToLocal, C.dump_vend, var.v2)
            return true 
        end
        if V.learning then
            V.dlgs[#V.dlgs + 1] = var.v2
            pcall(writeToLocal, C.dump_vend, table.concat(V.dlgs, "\n-----\n"))
        end
        return false
    end)
    return ok and res or false
end

local function on_send(ptype, pkt)
    pcall(function()
        if V.learning and type(pkt) == "string" and pkt:find("action|dialog_return", 1, true) then
            V.rec[#V.rec + 1] = pkt
        end
    end)
    return false
end

local function guarded(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        log_hp("Error: " .. tostring(err))
        sleep(3000)
    end
    return ok
end

local function same_world() return world_name():upper() == start_world:upper() end
local function main()
    if not wait_until(ready, 30000) then log_hp("Belum masuk world") return end
    start_world = world_name()
    ID.seed, ID.block, ID.vend = resolve(C.seed_name, C.seed_id), resolve(C.block_name, C.block_id), resolve(C.vend_name, C.vend_id)
    log_hp("ID: seed=" .. tostring(ID.seed) .. " block=" .. tostring(ID.block) .. " vending=" .. tostring(ID.vend))
    if not ID.seed or not ID.block then
        shutdown("ID item tidak ditemukan, isi seed_id dan block_id di config")
        return
    end
    home.x, home.y = tile_pos()
    banner_start()
    log_hp("Mulai di " .. start_world .. " titik " .. home.x .. "," .. home.y)
    while RUN do
        if not same_world() then shutdown("keluar dari world " .. start_world) break end
        if inv(ID.seed) <= 0 then shutdown("seed habis") break end
        local list = {}
        guarded(function() list = plant_phase() end)
        if #list == 0 then shutdown("tidak ada tile tanam yang valid") break end
        guarded(function()
            wait_ready(list)
            harvest(list)
            walk_to(home.x, home.y)
            pnb()
            sweep()
        end)
        stats.cycles = stats.cycles + 1
        log_hp("Siklus " .. stats.cycles .. " selesai, seed di tas: " .. inv(ID.seed))
        if inv(ID.seed) >= C.restock_min then
            local ok, why = false, ""
            guarded(function() ok, why = restock() end)
            if not ok then shutdown(why ~= "" and why or "restock gagal") break end
            if vend_stock >= C.vend_cap then shutdown("Vending penuh (" .. vend_stock .. ")") break end
        end
        pause(1000, 2000)
    end
end

addHook(on_variant, "onVariant")
addHook(on_send, "onSendPacket")
applyHook()
log_hp("dimuat")
runThread(main)
